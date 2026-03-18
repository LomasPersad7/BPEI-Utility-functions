# downloads parquet from s3 and converts to csv - for request of raw data

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
import gzip
import shutil

from copy_parquet import move_all_parquet_files



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


def download_tables_by_prefix(table_prefixes):
    # os.makedirs(LOCAL_FILTERED_BASE, exist_ok=True)
    os.makedirs(LOCAL_BASE, exist_ok=True)
    
    s3 = get_s3_client()
    table_files = get_table_files(s3)

    prefixes = tuple(table_prefixes)  # for str.startswith

    for table_name, keys in table_files.items():
        if table_name.startswith(prefixes):
            # table_local_path = os.path.join(LOCAL_FILTERED_BASE, table_name)
            # os.makedirs(table_local_path, exist_ok=True)

            download_table_parquets(
                s3,
                table_name,
                keys
            )


# ----------------------------
# Orchestrators
# ----------------------------
def download_all_tables( ):
    os.makedirs(LOCAL_BASE, exist_ok=True)
    s3 = get_s3_client()

    table_files = get_table_files(s3)
    # print("Tables found:", list(table_files.keys()))
    for table_name, keys in table_files.items():
        download_table_parquets(s3, table_name, keys)




# ----------------------------
# Convert parquet → CSV
# ----------------------------


# def convert_all_tables_to_csv_gz(local_base):
#     base = Path(local_base)

#     # FORCE SINGLE OUTPUT FILE (DuckDB 1.4.3)
#     duckdb.sql("PRAGMA threads=1;")

#     table_dirs = [d for d in base.iterdir() if d.is_dir()]
#     print("Tables found:", [d.name for d in table_dirs])

#     for table_dir in table_dirs:
#         parquet_files = sorted(table_dir.glob("*.parquet"))
#         if not parquet_files:
#             continue

#         output_csv = base / f"{table_dir.name}.csv.gz"
#         print(f"Converting {table_dir.name} → {output_csv}")

#         parquet_list = ", ".join(f"'{p.as_posix()}'" for p in parquet_files)

#         duckdb.sql(f"""
#             COPY (
#                 SELECT *
#                 FROM read_parquet([{parquet_list}])
#             )
#             TO '{output_csv.as_posix()}'
#             WITH (
#                 FORMAT CSV,
#                 HEADER TRUE,
#                 DELIMITER ',',
#                 COMPRESSION GZIP
#             );
#         """)  

# def convert_all_tables_to_csv_gz(local_base):
#     base = Path(local_base)

#     table_dirs = [d for d in base.iterdir() if d.is_dir()]
#     print("Tables found:", [d.name for d in table_dirs])

#     for table_dir in table_dirs:
#         parquet_files = sorted(table_dir.glob("*.parquet"))
#         if not parquet_files:
#             continue

#         tmp_csv = base / f"{table_dir.name}.csv"
#         output_gz = base / f"{table_dir.name}.csv.gz"

#         print(f"Converting {table_dir.name} → {output_gz.as_posix()}")

#         parquet_list = ", ".join(f"'{p.as_posix()}'" for p in parquet_files)

#         # 1. Write uncompressed CSV
#         duckdb.sql(f"""
#             COPY (
#                 SELECT *
#                 FROM read_parquet([{parquet_list}])
#             )
#             TO '{tmp_csv.as_posix()}'
#             WITH (
#                 FORMAT CSV,
#                 HEADER TRUE,
#                 DELIMITER ',',
#                 SINGLE TRUE
#             );
#         """)

#         # 2. Compress to .gz
#         with open(tmp_csv, "rb") as f_in, gzip.open(output_gz, "wb") as f_out:
#             shutil.copyfileobj(f_in, f_out)

#         # 3. Remove temporary CSV
#         tmp_csv.unlink()

#         print(f"✔ Finished {output_gz.name}")        
        

from pathlib import Path
import gzip
import pyarrow as pa
import pyarrow.parquet as pq
import pyarrow.csv as pc

def parquet_dir_to_csv_gz(parquet_dir, output_csv_gz):
    parquet_dir = Path(parquet_dir)
    parquet_files = sorted(parquet_dir.glob("*.parquet"))
    if not parquet_files:
        return

    with gzip.open(output_csv_gz, "wb") as gz_out:
        write_header = True

        for pf in parquet_files:
            parquet_file = pq.ParquetFile(pf)

            for batch in parquet_file.iter_batches(batch_size=500_000):
                table = pa.Table.from_batches([batch])

                pc.write_csv(
                    table,
                    gz_out,
                    write_options=pc.WriteOptions(
                        include_header=write_header
                    )
                )

                write_header = False
                
def convert_all_tables_to_csv_gz(local_base):
    base = Path(local_base)

    for table_dir in base.iterdir():
        if not table_dir.is_dir():
            continue

        output_csv_gz = base / f"{table_dir.name}.csv.gz"
        print(f"Converting {table_dir.name} → {output_csv_gz}")

        parquet_dir_to_csv_gz(table_dir, output_csv_gz)

        print(f"✔ Finished {output_csv_gz.name}")
# ----------------------------
# Main
# ----------------------------
if __name__ == "__main__":
    
    # ---------------------------- 
    # Configuration
    # ----------------------------
  
    BUCKET = "lomaspersad"
    BASE_PREFIX = "32_dmards"  # folder in S3
    LOCAL_BASE = os.path.join("s3_downloads", BASE_PREFIX)

    

    #1) Download once
    # download_all_tables()
    
    #2) copy to R
    # move_all_parquet_files(LOCAL_BASE,r"C:\Users\lxp1655\OneDrive - University of Miami\Projects\15 Yannuuzi IRIS Outcomes of Optic Pit Maculopathy Managed with Surgery\R\data")

    #3) Convert anytime
    # convert_all_tables_to_csv_gz(LOCAL_BASE)
    
    #------------- download specific tables by prefix -------------
    # Download by prefix
    LOCAL_BASE = os.path.join("s3_downloads", BASE_PREFIX,'Updated')
    
    # download_tables_by_prefix(["patient_closed", "patient_concept_date", "patient_device",\
    #                             "patient_tobacco_history","practice_ehr"])
    
        # copy to R
    # move_all_parquet_files(LOCAL_BASE,r"C:\Users\lxp1655\OneDrive - University of Miami\Projects\15 Yannuuzi IRIS Outcomes of Optic Pit Maculopathy Managed with Surgery\R\data")

    # Convert anytime
    convert_all_tables_to_csv_gz(LOCAL_BASE)
    
    
    
    
    

    
    # testing
    
    # import gzip
    # with gzip.open("practice_location.csv.gz", "rt") as f:
    #     for _ in range(5):
    #         print(f.readline())

 