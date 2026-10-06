# Entregable 2 - Data Mart E-commerce (PostgreSQL)

## Estructura
```
docker-compose.yml        PostgreSQL 17 (bi_database / bi_user / bi_password, puerto 5432)
cargar_datos.py           ejecuta TODO el pipeline (staging -> modelo -> ETL -> vistas -> validaciones)
data/                     coloca aqui los 4 CSV del dataset
sql/01_staging.sql        tablas stg_* (CSV crudo, todo TEXT)
sql/02_modelo_ddl.sql     dimensiones, tablas de hechos, PK, FK e indices
sql/03_etl_carga.sql      limpieza, transformacion y carga de dim_* y fact_*
sql/04_vistas_funciones.sql  vistas y funciones que alimentan el dashboard
sql/05_validaciones.sql   consultas de validacion (vista v_resultado_validaciones)
imagenes/                 diagrama estrella y mockup
```

## Como ejecutarlo
```
docker compose up -d
pip install psycopg2-binary
python cargar_datos.py
```
Al terminar imprime la tabla de validaciones (27 OK + 1 INFO). Tarda alrededor de un minuto.

Tambien puedes correr los .sql en orden desde DBeaver/pgAdmin; entre el 02 y el 03 hay que cargar
los CSV a las tablas stg_* (eso lo hace cargar_datos.py con COPY).

## Apagar
```
docker compose down        # conserva los datos (volumen postgres_data)
docker compose down -v     # borra tambien los datos
```
