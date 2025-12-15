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

# ----------------------------
# Configuration
# ----------------------------
bucket = "lomaspersad"
base_prefix = "32_dmards"  # folder in S3
local_base = "s3_downloads/32_dmards"

os.makedirs(local_base, exist_ok=True)

# Load environment variables from .env
load_dotenv()

# Use default profile from awscli
session = boto3.Session(profile_name="lomas", region_name="us-east-1")
# s3 = session.client("s3")
s3 = boto3.client(
    "s3",
    region_name=os.getenv("AWS_REGION"),
    aws_access_key_id=os.getenv("AWS_ACCESS_KEY_ID"),
    aws_secret_access_key=os.getenv("AWS_SECRET_ACCESS_KEY")
)

def test_list_tables():
    #NB list cleaned up to avoid duplicates, not actual file names with xxx.parquet
    # List all objects under the base prefix
    paginator = s3.get_paginator("list_objects_v2")
    tables = set()

    paginator = s3.get_paginator("list_objects_v2")
    tables = set()

    pattern = re.compile(r"(.+?)(\d*)\.parquet$")  # captures table name before numbers

    for page in paginator.paginate(Bucket=bucket, Prefix=base_prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"].split("/")[-1]  # get filename only
            match = pattern.match(key)
            if match:
                table_name = match.group(1)  # e.g., 'patient_cst'
                tables.add(table_name)

    tables = sorted(list(tables))
    print("Tables found in S3:")
    print(tables)


# ----------------------------
# Step 1: List all parquet files under base_prefix and group by table name
# ----------------------------
paginator = s3.get_paginator("list_objects_v2")

# Regex to extract table name before numeric suffix and .parquet
pattern = re.compile(r"(.+?)(\d*)\.parquet$")

# Dict to hold table_name -> list of keys
table_files = {}

for page in paginator.paginate(Bucket=bucket, Prefix=base_prefix):
    for obj in page.get("Contents", []):
        key = obj["Key"]
        if key.endswith(".parquet"):
            filename = key.split("/")[-1]
            match = pattern.match(filename)
            if match:
                table_name = match.group(1)
                table_files.setdefault(table_name, []).append(key)

# Get all table names
tables = sorted(table_files.keys())

# ----------------------------
# Function to download all parquet files for a table
# ----------------------------
def download_table_parquets(table_name):
    # local_dir = os.path.join(local_base, table_name)
    # os.makedirs(local_dir, exist_ok=True)
    
    print(f"Downloading all parquet files into '{local_base}'")
    for table, keys in table_files.items():
        for key in keys:
            local_path = os.path.join(local_base, os.path.basename(key))
            if not os.path.exists(local_path):
                print(f"Downloading {key}")
                s3.download_file(bucket, key, local_path)
    print("Finished downloading all parquet files.")

# ----------------------------
# Function to convert downloaded parquet files of a table to CSV
# ----------------------------
def convert_table_to_csv(table_name):
    parquet_path = os.path.join(local_base, table_name, "*.parquet")
    csv_output = f"{table_name}.csv"
    print(f"Converting {table_name} to CSV...")
    
    duckdb.sql(f"""
        COPY (
            SELECT *
            FROM read_parquet('{parquet_path}')
        )
        TO '{csv_output}'
        WITH (HEADER, DELIMITER ',');
    """)
    print(f"{csv_output} created.")

# ----------------------------
# Helper functions to download or convert all tables
# ----------------------------
def download_all_tables():
    for table in tables:
        download_table_parquets(table)

def convert_all_tables():
    for table in tables:
        convert_table_to_csv(table)

# ----------------------------
# Example usage
# ----------------------------
if __name__ == "__main__":
    # Download all parquet files (only once)
    download_all_tables()
    
    # Convert all tables to CSV (can be run multiple times)
    # convert_all_tables()