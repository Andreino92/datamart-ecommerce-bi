-- =====================================================================
-- 03_etl_carga.sql  |  LIMPIEZA, TRANSFORMACION Y CARGA (stg_* -> dim_* / fact_*)
-- Ejecutar completo en una sola sesion (usa una tabla temporal).
-- =====================================================================

-- ---------------------------------------------------------------------
-- PASO 0. Limpieza del encabezado de pedidos (tipos + nulos con significado)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_pedidos AS
SELECT
    order_id,
    order_date::date                                   AS fecha,          -- texto -> fecha
    order_status                                       AS estado_pedido,
    sales_channel                                      AS canal_venta,
    customer_id,
    payment_method                                     AS metodo_pago,
    payment_status                                     AS estado_pago,
    shipping_method                                    AS metodo_envio,
    warehouse                                          AS almacen,
    NULLIF(delivery_days,'')::numeric::smallint        AS dias_entrega,
    NULLIF(estimated_delivery_days,'')::numeric::smallint AS dias_estimados,
    -- delivery_status venia como 'Cancelled' en pedidos Pending/Returned/Cancelled:
    -- solo los pedidos Completed tienen una entrega real.
    CASE WHEN order_status = 'Completed' THEN delivery_status
         ELSE 'Sin entrega' END                        AS estado_entrega,
    COALESCE(NULLIF(return_reason,''), 'Sin devolución') AS motivo_devolucion,
    NULLIF(customer_rating,'')::numeric(3,1)           AS calificacion,
    marketing_channel                                  AS canal_marketing,
    COALESCE(NULLIF(campaign_name,''), 'Sin campaña')  AS campana,
    COALESCE(NULLIF(coupon_code,''),   'Sin cupón')    AS cupon,
    loyalty_points_earned::int                         AS puntos_ganados,
    loyalty_points_redeemed::int                       AS puntos_canjeados
FROM stg_pedidos;

CREATE INDEX ON tmp_pedidos(order_id);

-- ---------------------------------------------------------------------
-- PASO 1. Dimensiones
-- ---------------------------------------------------------------------

-- dim_tiempo: calendario completo 2021-2025 (generado, no leido del CSV)
INSERT INTO dim_tiempo
SELECT to_char(d,'YYYYMMDD')::int,
       d::date,
       extract(year    FROM d)::smallint,
       extract(quarter FROM d)::smallint,
       extract(month   FROM d)::smallint,
       (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto',
              'Septiembre','Octubre','Noviembre','Diciembre'])[extract(month FROM d)::int],
       to_char(d,'YYYY-MM'),
       extract(day     FROM d)::smallint,
       extract(isodow  FROM d)::smallint,
       (ARRAY['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'])[extract(isodow FROM d)::int],
       extract(isodow  FROM d) >= 6
FROM generate_series('2021-01-01'::date, '2025-12-31'::date, interval '1 day') AS d;

-- dim_ubicacion: ciudad/estado/pais/region de customer_master + moneda segun pais
INSERT INTO dim_ubicacion (ciudad, estado, pais, region, moneda)
SELECT DISTINCT c.customer_city, c.customer_state, c.customer_country, c.region,
       COALESCE(m.currency, 'N/D')
FROM stg_clientes c
LEFT JOIN (SELECT DISTINCT customer_country, currency FROM stg_pedidos) m
       ON m.customer_country = c.customer_country;

-- dim_cliente: maestro de clientes + atributos constantes por cliente tomados de los pedidos
-- (customer_name se excluye a proposito: dato personal que no aporta al analisis)
INSERT INTO dim_cliente (cliente_id_origen, edad, rango_edad, genero, segmento, tipo_cliente,
                         es_cliente_recurrente, num_pedidos_historico, valor_vida_cliente,
                         costo_adquisicion)
SELECT c.customer_id,
       c.customer_age::smallint,
       CASE WHEN c.customer_age::int < 25 THEN '<25'
            WHEN c.customer_age::int < 35 THEN '25-34'
            WHEN c.customer_age::int < 45 THEN '35-44'
            WHEN c.customer_age::int < 55 THEN '45-54'
            WHEN c.customer_age::int < 65 THEN '55-64'
            ELSE '65+' END,
       c.gender,
       c.customer_segment,
       COALESCE(h.tipo_cliente, 'Sin compras'),
       COALESCE(h.recurrente, FALSE),
       h.num_pedidos,
       h.clv,
       c.customer_acquisition_cost::numeric(10,2)
FROM stg_clientes c
LEFT JOIN (SELECT customer_id,
                  max(customer_type)                    AS tipo_cliente,
                  bool_or(is_repeat_customer::boolean)  AS recurrente,
                  max(customer_order_count::int)        AS num_pedidos,
                  max(customer_lifetime_value::numeric) AS clv
           FROM stg_pedidos GROUP BY customer_id) h
       ON h.customer_id = c.customer_id;

INSERT INTO dim_producto (producto_id_origen, nombre_producto, categoria, subcategoria, marca,
                          proveedor, precio_catalogo, costo_catalogo, calificacion_producto)
SELECT product_id, product_name, product_category, product_subcategory, brand, supplier,
       unit_price::numeric(12,2), product_cost::numeric(12,2), product_rating::numeric(3,1)
FROM stg_productos;

INSERT INTO dim_marketing (canal, campana, cupon)
SELECT DISTINCT canal_marketing, campana, cupon FROM tmp_pedidos;

INSERT INTO dim_almacen (codigo_almacen)
SELECT DISTINCT almacen FROM tmp_pedidos ORDER BY 1;

INSERT INTO dim_pedido (estado_pedido, canal_venta, metodo_pago, estado_pago, metodo_envio,
                        estado_entrega, motivo_devolucion)
SELECT DISTINCT estado_pedido, canal_venta, metodo_pago, estado_pago, metodo_envio,
                estado_entrega, motivo_devolucion
FROM tmp_pedidos;

-- Estadisticas para que el optimizador elija buenos planes de join en los hechos
ANALYZE dim_cliente; ANALYZE dim_ubicacion; ANALYZE dim_marketing; ANALYZE dim_almacen;
ANALYZE dim_pedido;  ANALYZE dim_producto;  ANALYZE tmp_pedidos;   ANALYZE stg_clientes;
ANALYZE stg_order_items;

-- ---------------------------------------------------------------------
-- PASO 2. fact_pedidos (una fila por pedido)
-- ---------------------------------------------------------------------
INSERT INTO fact_pedidos
SELECT p.order_id,
       to_char(p.fecha,'YYYYMMDD')::int,
       dc.id_cliente,
       du.id_ubicacion,
       dm.id_marketing,
       da.id_almacen,
       dp.id_dim_pedido,
       p.dias_entrega,
       p.dias_estimados,
       CASE WHEN p.dias_entrega IS NOT NULL
            THEN GREATEST(p.dias_entrega - p.dias_estimados, 0)::smallint END,
       p.calificacion,
       p.puntos_ganados,
       p.puntos_canjeados,
       n.num_lineas,
       p.estado_pedido = 'Returned',
       p.estado_pedido = 'Cancelled',
       p.estado_entrega = 'Delayed'
FROM tmp_pedidos p
JOIN stg_clientes   c  ON c.customer_id = p.customer_id
JOIN dim_cliente    dc ON dc.cliente_id_origen = p.customer_id
JOIN dim_ubicacion  du ON du.ciudad = c.customer_city AND du.estado = c.customer_state
                      AND du.pais   = c.customer_country AND du.region = c.region
JOIN dim_marketing  dm ON dm.canal = p.canal_marketing AND dm.campana = p.campana
                      AND dm.cupon = p.cupon
JOIN dim_almacen    da ON da.codigo_almacen = p.almacen
JOIN dim_pedido     dp ON dp.estado_pedido = p.estado_pedido AND dp.canal_venta = p.canal_venta
                      AND dp.metodo_pago = p.metodo_pago AND dp.estado_pago = p.estado_pago
                      AND dp.metodo_envio = p.metodo_envio AND dp.estado_entrega = p.estado_entrega
                      AND dp.motivo_devolucion = p.motivo_devolucion
JOIN (SELECT order_id, count(*)::smallint AS num_lineas
      FROM stg_order_items GROUP BY order_id) n ON n.order_id = p.order_id;

-- ---------------------------------------------------------------------
-- PASO 3. fact_ventas (una fila por producto dentro de un pedido)
-- Las medidas monetarias salen de las LINEAS (order_items).
-- num_linea numera las lineas de cada pedido segun el orden del archivo; esto
-- resuelve los 87 pares pedido-producto repetidos sin perder ninguna linea.
-- ---------------------------------------------------------------------
INSERT INTO fact_ventas (order_id, num_linea, id_tiempo, id_cliente, id_producto, id_ubicacion,
                         id_marketing, id_almacen, id_dim_pedido, cantidad, precio_unitario,
                         pct_descuento, ventas_brutas, monto_descuento, impuesto, costo_envio,
                         ventas_netas, costo_producto, utilidad)
SELECT i.order_id,
       row_number() OVER (PARTITION BY i.order_id ORDER BY i.stg_row_id)::smallint,
       fp.id_tiempo, fp.id_cliente, dpr.id_producto, fp.id_ubicacion,
       fp.id_marketing, fp.id_almacen, fp.id_dim_pedido,
       i.quantity::int,
       i.unit_price::numeric(12,2),
       i.discount_percentage::numeric(8,6),
       i.gross_sales::numeric(14,2),
       i.discount_amount::numeric(14,2),
       i.tax_amount::numeric(14,2),
       i.shipping_cost::numeric(14,2),
       i.net_sales::numeric(14,2),
       i.product_cost::numeric(14,2),
       i.profit::numeric(14,2)
FROM stg_order_items i
JOIN fact_pedidos fp  ON fp.order_id = i.order_id
JOIN dim_producto dpr ON dpr.producto_id_origen = i.product_id
ORDER BY i.stg_row_id;

ANALYZE;
