-- =====================================================================
-- 01_staging.sql  |  Capa de STAGING (datos crudos tal como vienen en los CSV)
-- Todas las columnas se cargan como TEXT: la conversion de tipos y la limpieza
-- se hacen despues, de forma controlada, en 03_etl_carga.sql
-- stg_row_id conserva el orden original del archivo (se usa para numerar lineas).
-- =====================================================================

DROP TABLE IF EXISTS stg_pedidos CASCADE;
CREATE TABLE stg_pedidos (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY,
    order_id TEXT,
    order_date TEXT,
    order_time TEXT,
    order_status TEXT,
    sales_channel TEXT,
    customer_id TEXT,
    customer_name TEXT,
    customer_age TEXT,
    gender TEXT,
    customer_segment TEXT,
    customer_type TEXT,
    customer_city TEXT,
    customer_state TEXT,
    customer_country TEXT,
    region TEXT,
    customer_postal_code TEXT,
    payment_method TEXT,
    payment_status TEXT,
    currency TEXT,
    shipping_method TEXT,
    warehouse TEXT,
    delivery_days TEXT,
    estimated_delivery_days TEXT,
    delivery_status TEXT,
    return_status TEXT,
    return_reason TEXT,
    customer_rating TEXT,
    review_sentiment TEXT,
    customer_review TEXT,
    marketing_channel TEXT,
    campaign_name TEXT,
    coupon_code TEXT,
    loyalty_points_earned TEXT,
    loyalty_points_redeemed TEXT,
    quantity TEXT,
    gross_sales TEXT,
    discount_amount TEXT,
    tax_amount TEXT,
    shipping_cost TEXT,
    net_sales TEXT,
    product_cost TEXT,
    profit TEXT,
    profit_margin_percentage TEXT,
    customer_lifetime_value TEXT,
    is_repeat_customer TEXT,
    customer_order_count TEXT
);

DROP TABLE IF EXISTS stg_order_items CASCADE;
CREATE TABLE stg_order_items (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY,
    order_id TEXT,
    product_id TEXT,
    quantity TEXT,
    unit_price TEXT,
    discount_percentage TEXT,
    discount_amount TEXT,
    gross_sales TEXT,
    tax_amount TEXT,
    shipping_cost TEXT,
    net_sales TEXT,
    product_cost TEXT,
    profit TEXT
);

DROP TABLE IF EXISTS stg_clientes CASCADE;
CREATE TABLE stg_clientes (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_id TEXT,
    customer_name TEXT,
    customer_age TEXT,
    gender TEXT,
    customer_segment TEXT,
    customer_city TEXT,
    customer_state TEXT,
    customer_country TEXT,
    region TEXT,
    customer_postal_code TEXT,
    customer_acquisition_cost TEXT
);

DROP TABLE IF EXISTS stg_productos CASCADE;
CREATE TABLE stg_productos (
    stg_row_id BIGINT GENERATED ALWAYS AS IDENTITY,
    product_id TEXT,
    product_name TEXT,
    product_category TEXT,
    product_subcategory TEXT,
    brand TEXT,
    supplier TEXT,
    unit_price TEXT,
    product_cost TEXT,
    product_rating TEXT
);
