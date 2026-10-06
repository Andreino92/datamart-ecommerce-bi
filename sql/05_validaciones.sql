-- =====================================================================
-- 05_validaciones.sql  |  CONSULTAS DE VALIDACION DE LA CARGA
-- Cubre: (A) cantidad de registros, (B) integridad de relaciones,
--        (C) valores nulos relevantes, (D) totales y medidas principales.
-- La vista v_resultado_validaciones resume todo en una sola tabla.
-- =====================================================================
CREATE OR REPLACE VIEW v_resultado_validaciones AS
WITH chk(orden, nombre, esperado, obtenido, tipo) AS (VALUES
 -- (A) CANTIDAD DE REGISTROS
 ( 1,'A. stg_pedidos = filas del CSV',                     '138116', (SELECT count(*)::text FROM stg_pedidos),     'eq'),
 ( 2,'A. stg_order_items = filas del CSV',                 '397569', (SELECT count(*)::text FROM stg_order_items), 'eq'),
 ( 3,'A. dim_cliente = clientes del maestro',              '25000',  (SELECT count(*)::text FROM dim_cliente),     'eq'),
 ( 4,'A. dim_producto = productos del catalogo',           '1175',   (SELECT count(*)::text FROM dim_producto),    'eq'),
 ( 5,'A. dim_tiempo = dias 2021-2025 (5 anios, 1 bisiesto)','1826',  (SELECT count(*)::text FROM dim_tiempo),      'eq'),
 ( 6,'A. dim_almacen = almacenes distintos',               '19',     (SELECT count(*)::text FROM dim_almacen),     'eq'),
 ( 7,'A. dim_pedido = combinaciones distintas en origen',
        (SELECT count(*)::text FROM (SELECT DISTINCT order_status, sales_channel, payment_method, payment_status,
                shipping_method, delivery_status, return_reason FROM stg_pedidos) x),
        (SELECT count(*)::text FROM dim_pedido), 'eq'),
 ( 8,'A. dim_marketing = combinaciones distintas en origen',
        (SELECT count(*)::text FROM (SELECT DISTINCT marketing_channel, campaign_name, coupon_code FROM stg_pedidos) x),
        (SELECT count(*)::text FROM dim_marketing), 'eq'),
 ( 9,'A. dim_ubicacion = ciudades distintas en origen',
        (SELECT count(*)::text FROM (SELECT DISTINCT customer_city, customer_state, customer_country, region FROM stg_clientes) x),
        (SELECT count(*)::text FROM dim_ubicacion), 'eq'),
 (10,'A. fact_pedidos = pedidos (1 fila por pedido)',      '138116', (SELECT count(*)::text FROM fact_pedidos),    'eq'),
 (11,'A. fact_ventas = lineas de pedido (grano del hecho)','397569', (SELECT count(*)::text FROM fact_ventas),     'eq'),
 -- (B) INTEGRIDAD REFERENCIAL
 (12,'B. fact_ventas con alguna clave sin dimension',      '0',
        (SELECT count(*)::text FROM fact_ventas f
          LEFT JOIN dim_tiempo t ON t.id_tiempo=f.id_tiempo   LEFT JOIN dim_cliente c ON c.id_cliente=f.id_cliente
          LEFT JOIN dim_producto p ON p.id_producto=f.id_producto LEFT JOIN dim_ubicacion u ON u.id_ubicacion=f.id_ubicacion
          LEFT JOIN dim_marketing m ON m.id_marketing=f.id_marketing LEFT JOIN dim_almacen a ON a.id_almacen=f.id_almacen
          LEFT JOIN dim_pedido d ON d.id_dim_pedido=f.id_dim_pedido LEFT JOIN fact_pedidos fp ON fp.order_id=f.order_id
          WHERE t.id_tiempo IS NULL OR c.id_cliente IS NULL OR p.id_producto IS NULL OR u.id_ubicacion IS NULL
             OR m.id_marketing IS NULL OR a.id_almacen IS NULL OR d.id_dim_pedido IS NULL OR fp.order_id IS NULL), 'eq'),
 (13,'B. fact_pedidos con alguna clave sin dimension',     '0',
        (SELECT count(*)::text FROM fact_pedidos f
          LEFT JOIN dim_tiempo t ON t.id_tiempo=f.id_tiempo   LEFT JOIN dim_cliente c ON c.id_cliente=f.id_cliente
          LEFT JOIN dim_ubicacion u ON u.id_ubicacion=f.id_ubicacion LEFT JOIN dim_marketing m ON m.id_marketing=f.id_marketing
          LEFT JOIN dim_almacen a ON a.id_almacen=f.id_almacen LEFT JOIN dim_pedido d ON d.id_dim_pedido=f.id_dim_pedido
          WHERE t.id_tiempo IS NULL OR c.id_cliente IS NULL OR u.id_ubicacion IS NULL
             OR m.id_marketing IS NULL OR a.id_almacen IS NULL OR d.id_dim_pedido IS NULL), 'eq'),
 (14,'B. pedidos sin ninguna linea de venta',              '0',
        (SELECT count(*)::text FROM fact_pedidos fp WHERE NOT EXISTS (SELECT 1 FROM fact_ventas f WHERE f.order_id=fp.order_id)), 'eq'),
 (15,'B. pedidos cuyo num_lineas no coincide con fact_ventas','0',
        (SELECT count(*)::text FROM fact_pedidos fp
          JOIN (SELECT order_id, count(*) n FROM fact_ventas GROUP BY order_id) v ON v.order_id=fp.order_id
          WHERE v.n <> fp.num_lineas), 'eq'),
 (16,'B. lineas con mismo (pedido, producto) conservadas', '87',
        (SELECT (count(*) - count(DISTINCT (order_id, id_producto)))::text FROM fact_ventas), 'eq'),
 (17,'B. fechas de hechos fuera del rango 2021-2025',      '0',
        (SELECT count(*)::text FROM fact_ventas f JOIN dim_tiempo t USING (id_tiempo) WHERE t.anio NOT BETWEEN 2021 AND 2025), 'eq'),
 -- (C) NULOS RELEVANTES
 (18,'C. fact_ventas con alguna medida nula',              '0',
        (SELECT count(*)::text FROM fact_ventas WHERE cantidad IS NULL OR ventas_netas IS NULL OR utilidad IS NULL
            OR ventas_brutas IS NULL OR monto_descuento IS NULL OR costo_producto IS NULL), 'eq'),
 (19,'C. pedidos Completed sin dias_entrega o sin calificacion','0',
        (SELECT count(*)::text FROM fact_pedidos fp JOIN dim_pedido d USING (id_dim_pedido)
          WHERE d.estado_pedido='Completed' AND (fp.dias_entrega IS NULL OR fp.calificacion IS NULL)), 'eq'),
 (20,'C. nulos de entrega/calificacion = pedidos no Completed (24,557)', '24557',
        (SELECT count(*)::text FROM fact_pedidos WHERE dias_entrega IS NULL), 'eq'),
 (21,'C. clientes sin compras (tipo_cliente = Sin compras)','89',
        (SELECT count(*)::text FROM dim_cliente WHERE tipo_cliente='Sin compras'), 'eq'),
 -- (D) TOTALES Y MEDIDAS
 (22,'D. SUM(ventas_netas) fact_ventas = SUM(net_sales) order_items',
        (SELECT round(sum(net_sales::numeric),2)::text FROM stg_order_items),
        (SELECT round(sum(ventas_netas),2)::text FROM fact_ventas), 'eq'),
 (23,'D. SUM(utilidad) fact_ventas = SUM(profit) order_items',
        (SELECT round(sum(profit::numeric),2)::text FROM stg_order_items),
        (SELECT round(sum(utilidad),2)::text FROM fact_ventas), 'eq'),
 (24,'D. ventas_netas <> brutas - descuento + impuesto + envio (filas)','0',
        (SELECT count(*)::text FROM fact_ventas
          WHERE abs(ventas_netas - (ventas_brutas - monto_descuento + impuesto + costo_envio)) > 0.05), 'eq'),
 (25,'D. utilidad <> ventas_netas - envio - costo (filas)','0',
        (SELECT count(*)::text FROM fact_ventas
          WHERE abs(utilidad - (ventas_netas - costo_envio - costo_producto)) > 0.05), 'eq'),
 (26,'D. ventas_netas Completed (modelo) = lineas Completed (origen)',
        (SELECT round(sum(i.net_sales::numeric),2)::text FROM stg_order_items i JOIN stg_pedidos p USING (order_id) WHERE p.order_status='Completed'),
        (SELECT round(sum(f.ventas_netas),2)::text FROM fact_ventas f JOIN dim_pedido d USING (id_dim_pedido) WHERE d.estado_pedido='Completed'), 'eq'),
 (27,'D. es_entrega_tardia inconsistente con dias_retraso > 0 (pedidos)','0',
        (SELECT count(*)::text FROM fact_pedidos WHERE es_entrega_tardia AND COALESCE(dias_retraso,0) = 0), 'eq'),
 (28,'D. [INFO] Ventas netas Completed: encabezado (E1) vs lineas (modelo)',
        (SELECT round(sum(net_sales::numeric),2)::text FROM stg_pedidos WHERE order_status='Completed'),
        (SELECT round(sum(f.ventas_netas),2)::text FROM fact_ventas f JOIN dim_pedido d USING (id_dim_pedido) WHERE d.estado_pedido='Completed'), 'info')
)
SELECT orden, nombre, esperado, obtenido,
       CASE WHEN tipo = 'info' THEN 'INFO'
            WHEN esperado = obtenido THEN 'OK' ELSE 'REVISAR' END AS resultado
FROM chk;

-- ---------------------------------------------------------------------
-- Consultas de detalle (evidencia visible; ejecutar una a una en DBeaver/psql)
-- ---------------------------------------------------------------------
-- A) Registros por tabla
-- SELECT 'dim_tiempo' AS tabla, count(*) FROM dim_tiempo UNION ALL SELECT 'dim_cliente', count(*) FROM dim_cliente
-- UNION ALL SELECT 'dim_producto', count(*) FROM dim_producto UNION ALL SELECT 'dim_ubicacion', count(*) FROM dim_ubicacion
-- UNION ALL SELECT 'dim_marketing', count(*) FROM dim_marketing UNION ALL SELECT 'dim_almacen', count(*) FROM dim_almacen
-- UNION ALL SELECT 'dim_pedido', count(*) FROM dim_pedido UNION ALL SELECT 'fact_pedidos', count(*) FROM fact_pedidos
-- UNION ALL SELECT 'fact_ventas', count(*) FROM fact_ventas;
-- B) Resumen general:  SELECT * FROM v_resultado_validaciones ORDER BY orden;
