"""
cargar_datos.py - Ejecuta el pipeline completo del Data Mart en PostgreSQL.

Pasos:
  1. 01_staging.sql      -> crea tablas stg_* (texto crudo)
  2. 02_modelo_ddl.sql   -> crea dimensiones y tablas de hechos
  3. COPY de los 4 CSV   -> llena stg_* (carpeta ./data)
  4. 03_etl_carga.sql    -> limpia, transforma y llena dim_* y fact_*
  5. 04_vistas_funciones.sql -> vistas y funciones para el dashboard
  6. 05_validaciones.sql -> imprime el resultado de las validaciones

Requisitos:  pip install psycopg2-binary
Uso:         python cargar_datos.py
"""
import os
import time
from pathlib import Path

import psycopg2

CONN = dict(
    host=os.getenv("PGHOST", "localhost"),
    port=int(os.getenv("PGPORT", 5432)),
    dbname=os.getenv("PGDATABASE", "bi_database"),
    user=os.getenv("PGUSER", "bi_user"),
    password=os.getenv("PGPASSWORD", "bi_password"),
)
BASE = Path(__file__).parent
DATA = BASE / "data"
SQL = BASE / "sql"

# (archivo CSV, tabla de staging)
CARGAS = [
    ("customer_master.csv", "stg_clientes"),
    ("product_catalog.csv", "stg_productos"),
    ("ecommerce_sales_customer_analytics_150k.csv", "stg_pedidos"),
    ("order_items.csv", "stg_order_items"),
]


def correr_sql(cur, archivo):
    t = time.time()
    cur.execute((SQL / archivo).read_text(encoding="utf-8"))
    print(f"  OK  {archivo:<26} ({time.time() - t:5.1f} s)")


def cargar_csv(cur, csv_name, tabla):
    ruta = DATA / csv_name
    t = time.time()
    with open(ruta, encoding="utf-8") as f:
        columnas = f.readline().strip().split(",")
        f.seek(0)
        cur.copy_expert(
            f"COPY {tabla} ({', '.join(columnas)}) FROM STDIN WITH (FORMAT csv, HEADER true)", f
        )
    cur.execute(f"SELECT count(*) FROM {tabla}")
    print(f"  OK  {csv_name:<46} -> {tabla:<16} {cur.fetchone()[0]:>9,} filas ({time.time() - t:4.1f} s)")


def mostrar_validaciones(cur):
    cur.execute("SELECT * FROM v_resultado_validaciones ORDER BY orden")
    print(f"\n  {'#':>2}  {'Validacion':<58} {'Esperado':>16} {'Obtenido':>16}  Resultado")
    for orden, nombre, esperado, obtenido, resultado in cur.fetchall():
        print(f"  {orden:>2}  {nombre:<58} {esperado:>16} {obtenido:>16}  {resultado}")


def main():
    with psycopg2.connect(**CONN) as con:
        cur = con.cursor()
        print("1) Staging y modelo")
        correr_sql(cur, "01_staging.sql")
        correr_sql(cur, "02_modelo_ddl.sql")
        print("2) Carga de CSV a staging")
        for csv_name, tabla in CARGAS:
            cargar_csv(cur, csv_name, tabla)
        print("3) ETL: dimensiones y hechos")
        correr_sql(cur, "03_etl_carga.sql")
        print("4) Vistas y funciones")
        correr_sql(cur, "04_vistas_funciones.sql")
        print("5) Validaciones")
        correr_sql(cur, "05_validaciones.sql")
        mostrar_validaciones(cur)
        con.commit()


if __name__ == "__main__":
    main()
