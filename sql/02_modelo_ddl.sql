-- =====================================================================
-- 02_modelo_ddl.sql  |  MODELO DIMENSIONAL (esquema en estrella)
--
-- GRANULARIDAD
--   fact_ventas  : una fila = un PRODUCTO dentro de un PEDIDO (linea de pedido).
--   fact_pedidos : una fila = un PEDIDO.
-- Ambas comparten las mismas dimensiones (dimensiones conformadas).
-- =====================================================================

DROP VIEW  IF EXISTS vw_detalle_ventas, vw_ventas_mensuales, vw_margen_categoria,
                     vw_perdidas_por_estado, vw_entregas_envio, vw_clv_cac_segmento,
                     vw_marketing_canal, vw_filtros CASCADE;
DROP TABLE IF EXISTS fact_ventas, fact_pedidos, dim_tiempo, dim_cliente, dim_producto,
                     dim_ubicacion, dim_marketing, dim_almacen, dim_pedido CASCADE;

-- ---------- DIMENSIONES ----------------------------------------------

CREATE TABLE dim_tiempo (
    id_tiempo         INTEGER      PRIMARY KEY,          -- AAAAMMDD
    fecha             DATE         NOT NULL UNIQUE,
    anio              SMALLINT     NOT NULL,
    trimestre         SMALLINT     NOT NULL,
    mes               SMALLINT     NOT NULL,
    nombre_mes        VARCHAR(12)  NOT NULL,
    anio_mes          CHAR(7)      NOT NULL,             -- 'AAAA-MM'
    dia               SMALLINT     NOT NULL,
    dia_semana        SMALLINT     NOT NULL,             -- 1=lunes ... 7=domingo
    nombre_dia        VARCHAR(12)  NOT NULL,
    es_fin_de_semana  BOOLEAN      NOT NULL
);

CREATE TABLE dim_cliente (
    id_cliente             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id_origen      VARCHAR(20)   NOT NULL UNIQUE,   -- CUST-000001
    edad                   SMALLINT      NOT NULL,
    rango_edad             VARCHAR(10)   NOT NULL,
    genero                 VARCHAR(20)   NOT NULL,
    segmento               VARCHAR(20)   NOT NULL,
    tipo_cliente           VARCHAR(20)   NOT NULL,          -- 'Sin compras' si no tiene pedidos
    es_cliente_recurrente  BOOLEAN       NOT NULL,
    num_pedidos_historico  INTEGER,
    valor_vida_cliente     NUMERIC(14,2),                   -- CLV (NULL si no tiene compras)
    costo_adquisicion      NUMERIC(10,2) NOT NULL           -- CAC
);

CREATE TABLE dim_producto (
    id_producto         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    producto_id_origen  VARCHAR(20)   NOT NULL UNIQUE,      -- PROD-000001
    nombre_producto     VARCHAR(150)  NOT NULL,
    categoria           VARCHAR(50)   NOT NULL,
    subcategoria        VARCHAR(60)   NOT NULL,
    marca               VARCHAR(60)   NOT NULL,
    proveedor           VARCHAR(60)   NOT NULL,
    precio_catalogo     NUMERIC(12,2) NOT NULL,
    costo_catalogo      NUMERIC(12,2) NOT NULL,
    calificacion_producto NUMERIC(3,1)
);

CREATE TABLE dim_ubicacion (
    id_ubicacion  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ciudad        VARCHAR(80) NOT NULL,
    estado        VARCHAR(80) NOT NULL,
    pais          VARCHAR(40) NOT NULL,
    region        VARCHAR(20) NOT NULL,   -- ojo: no es coherente con el pais (ver Entregable 1)
    moneda        VARCHAR(5)  NOT NULL,
    UNIQUE (ciudad, estado, pais, region)
);

CREATE TABLE dim_marketing (
    id_marketing  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    canal         VARCHAR(40) NOT NULL,
    campana       VARCHAR(50) NOT NULL,   -- 'Sin campaña' cuando era nulo
    cupon         VARCHAR(20) NOT NULL,   -- 'Sin cupón'   cuando era nulo
    UNIQUE (canal, campana, cupon)
);

CREATE TABLE dim_almacen (
    id_almacen      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_almacen  VARCHAR(10) NOT NULL UNIQUE
);

-- Dimension "junk": agrupa los estados y metodos de baja cardinalidad del pedido
CREATE TABLE dim_pedido (
    id_dim_pedido      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    estado_pedido      VARCHAR(20) NOT NULL,   -- Completed / Returned / Cancelled / Pending
    canal_venta        VARCHAR(30) NOT NULL,
    metodo_pago        VARCHAR(30) NOT NULL,
    estado_pago        VARCHAR(20) NOT NULL,
    metodo_envio       VARCHAR(20) NOT NULL,
    estado_entrega     VARCHAR(20) NOT NULL,   -- derivado: solo los Completed tienen entrega
    motivo_devolucion  VARCHAR(40) NOT NULL,   -- 'Sin devolución' cuando no aplica
    UNIQUE (estado_pedido, canal_venta, metodo_pago, estado_pago, metodo_envio,
            estado_entrega, motivo_devolucion)
);

-- ---------- TABLAS DE HECHOS -----------------------------------------

-- Una fila por PEDIDO: medidas de entrega, calificacion y lealtad.
CREATE TABLE fact_pedidos (
    order_id           VARCHAR(20) PRIMARY KEY,                  -- dimension degenerada
    id_tiempo          INTEGER  NOT NULL REFERENCES dim_tiempo(id_tiempo),
    id_cliente         INTEGER  NOT NULL REFERENCES dim_cliente(id_cliente),
    id_ubicacion       INTEGER  NOT NULL REFERENCES dim_ubicacion(id_ubicacion),
    id_marketing       INTEGER  NOT NULL REFERENCES dim_marketing(id_marketing),
    id_almacen         INTEGER  NOT NULL REFERENCES dim_almacen(id_almacen),
    id_dim_pedido      INTEGER  NOT NULL REFERENCES dim_pedido(id_dim_pedido),
    -- medidas (NULL = no aplica: pedido sin entrega o sin calificacion)
    dias_entrega       SMALLINT,
    dias_estimados     SMALLINT,
    dias_retraso       SMALLINT,                                 -- max(entrega - estimado, 0)
    calificacion       NUMERIC(3,1),
    puntos_ganados     INTEGER  NOT NULL,
    puntos_canjeados   INTEGER  NOT NULL,
    num_lineas         SMALLINT NOT NULL,
    es_devuelto        BOOLEAN  NOT NULL,
    es_cancelado       BOOLEAN  NOT NULL,
    es_entrega_tardia  BOOLEAN  NOT NULL
);

-- Una fila por PRODUCTO DENTRO DE UN PEDIDO. Todas las medidas monetarias salen de las lineas.
CREATE TABLE fact_ventas (
    id_venta         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id         VARCHAR(20) NOT NULL REFERENCES fact_pedidos(order_id),  -- dim. degenerada
    num_linea        SMALLINT    NOT NULL,
    id_tiempo        INTEGER     NOT NULL REFERENCES dim_tiempo(id_tiempo),
    id_cliente       INTEGER     NOT NULL REFERENCES dim_cliente(id_cliente),
    id_producto      INTEGER     NOT NULL REFERENCES dim_producto(id_producto),
    id_ubicacion     INTEGER     NOT NULL REFERENCES dim_ubicacion(id_ubicacion),
    id_marketing     INTEGER     NOT NULL REFERENCES dim_marketing(id_marketing),
    id_almacen       INTEGER     NOT NULL REFERENCES dim_almacen(id_almacen),
    id_dim_pedido    INTEGER     NOT NULL REFERENCES dim_pedido(id_dim_pedido),
    -- medidas
    cantidad         INTEGER       NOT NULL,
    precio_unitario  NUMERIC(12,2) NOT NULL,
    pct_descuento    NUMERIC(8,6)  NOT NULL,    -- fraccion 0-1 (0.34 = 34 %)
    ventas_brutas    NUMERIC(14,2) NOT NULL,
    monto_descuento  NUMERIC(14,2) NOT NULL,
    impuesto         NUMERIC(14,2) NOT NULL,
    costo_envio      NUMERIC(14,2) NOT NULL,
    ventas_netas     NUMERIC(14,2) NOT NULL,    -- = brutas - descuento + impuesto + envio (def. del dataset)
    costo_producto   NUMERIC(14,2) NOT NULL,
    utilidad         NUMERIC(14,2) NOT NULL,    -- = ventas_netas - envio - costo_producto
    ingreso_producto NUMERIC(14,2) GENERATED ALWAYS AS (ventas_brutas - monto_descuento) STORED,
    UNIQUE (order_id, num_linea)
);

-- Indices sobre las claves foraneas (aceleran los filtros del dashboard)
CREATE INDEX ix_fv_tiempo    ON fact_ventas(id_tiempo);
CREATE INDEX ix_fv_cliente   ON fact_ventas(id_cliente);
CREATE INDEX ix_fv_producto  ON fact_ventas(id_producto);
CREATE INDEX ix_fv_ubicacion ON fact_ventas(id_ubicacion);
CREATE INDEX ix_fv_marketing ON fact_ventas(id_marketing);
CREATE INDEX ix_fv_dimpedido ON fact_ventas(id_dim_pedido);
CREATE INDEX ix_fp_tiempo    ON fact_pedidos(id_tiempo);
CREATE INDEX ix_fp_cliente   ON fact_pedidos(id_cliente);
CREATE INDEX ix_fp_ubicacion ON fact_pedidos(id_ubicacion);
CREATE INDEX ix_fp_dimpedido ON fact_pedidos(id_dim_pedido);
