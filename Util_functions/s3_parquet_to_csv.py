# downloads parquet from s3 and converts to csv

# import duckdb

# # 1. Enable S3 support
# duckdb.sql("INSTALL httpfs;")
# duckdb.sql("LOAD httpfs;")

# # 2. (Optional but recommended) Set region explicitly
# duckdb.sql("SET s3_region='us-east-1';")

# # 3. Convert Parquet in S3 to local CSV
# duckdb.sql("""
# COPY (
#   SELECT *
#   FROM read_parquet('s3://lomaspersad/32_dmards/patient_cst/*.parquet')
# )
# TO 'patient_cst.csv'
# WITH (
#   HEADER,
#   DELIMITER ','
# );
# """)


import boto3
import os
from dotenv import load_dotenv
import re
import duckdb
import glob
from pathlib import Path




# ----------------------------
# S3 Client
# ----------------------------
def get_s3_client():
    load_dotenv()
    return boto3.client(
        "s3",
        region_name=os.getenv("AWS_REGION"),
        aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY"),
    )

# ----------------------------
# Discover tables + parquet files
# ----------------------------
def get_table_files(s3):
    """
    Returns:
        dict[str, list[str]] -> table_name -> list of S3 keys
    """
    paginator = s3.get_paginator("list_objects_v2")
    table_files = {}

    pattern = re.compile(r"(.+?)(\d*)\.parquet$")

    for page in paginator.paginate(Bucket=BUCKET, Prefix=BASE_PREFIX):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith(".parquet"):
                continue

            filename = os.path.basename(key)
            match = pattern.match(filename)
            if match:
                table_name = match.group(1)
                table_files.setdefault(table_name, []).append(key)

    return table_files

# ----------------------------
# Download parquet files
# ----------------------------
def download_table_parquets(s3, table_name, keys):
    table_dir = os.path.join(LOCAL_BASE, table_name)
    os.makedirs(table_dir, exist_ok=True)

    print(f"\nDownloading table: {table_name}")
    for key in keys:
        local_path = os.path.join(table_dir, os.path.basename(key))
        if not os.path.exists(local_path):
            print(f"  Downloading {key}")
            s3.download_file(BUCKET, key, local_path)




# ----------------------------
# Orchestrators
# ----------------------------
def download_all_tables( ):
    s3 = get_s3_client()

    table_files = get_table_files(s3)
    # print("Tables found:", list(table_files.keys()))
    for table_name, keys in table_files.items():
        download_table_parquets(s3, table_name, keys)




# ----------------------------
# Convert parquet → CSV
# ----------------------------

def convert_all_tables_to_csv_gz(local_base):
    base = Path(local_base)

    table_dirs = [d for d in base.iterdir() if d.is_dir()]
    print("Tables found:", [d.name for d in table_dirs])

    for table_dir in table_dirs:
        parquet_files = list(table_dir.glob("*.parquet"))
        if not parquet_files:
            continue

        output_csv = base / f"{table_dir.name}.csv.gz"

        print(f"Converting {table_dir.name} → {output_csv.as_posix()}")

        parquet_list = ", ".join(f"'{p.as_posix()}'" for p in parquet_files)
        
        # print(parquet_list)

        duckdb.sql(f"""
            COPY (
                SELECT *
                FROM read_parquet([{parquet_list}])
            )
            TO '{output_csv.as_posix()}'
            WITH (
                HEADER,
                DELIMITER ',',
                COMPRESSION 'gzip'
            );
        """)
# ----------------------------
# Main
# ----------------------------
if __name__ == "__main__":
    
    # ----------------------------
    # Configuration
    # ----------------------------
  
    BUCKET = "lomaspersad"
    BASE_PREFIX = "25_glaucoma_risk"  # folder in S3
    LOCAL_BASE = os.path.join("s3_downloads", BASE_PREFIX)

    os.makedirs(LOCAL_BASE, exist_ok=True)

    # Download once
    download_all_tables()

    # Convert anytime
    convert_all_tables_to_csv_gz(LOCAL_BASE)
    
    
    # testing
 