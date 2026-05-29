
import os
from dotenv import load_dotenv
import boto3
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


def download_s3_file(s3, bucket: str, key: str, local_path: str):
    """
    Download a single S3 object to a local file path.

    Args:
        s3: boto3 S3 client
        bucket: S3 bucket name
        key: Full S3 key (path inside bucket)
        local_path: Absolute or relative path on your laptop
    """
    # Ensure local directory exists
    os.makedirs(os.path.dirname(local_path), exist_ok=True)

    print(f"Downloading s3://{bucket}/{key}")
    s3.download_file(bucket, key, local_path)
    print(f"Saved to {local_path}")


def download_s3_prefix(s3, bucket: str, prefix: str, local_base: str):
    """
    Download all objects under a prefix to a local directory,
    preserving folder structure.
    """
    paginator = s3.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]

            # Skip "directory" placeholders
            if key.endswith("/"):
                continue

            # Preserve folder structure
            relative_path = os.path.relpath(key, prefix)
            local_path = os.path.join(local_base, relative_path)

            os.makedirs(os.path.dirname(local_path), exist_ok=True)

            print(f"Downloading {key}")
            s3.download_file(bucket, key, local_path)

if __name__ == "__main__":
    
    s3 = get_s3_client()
    BUCKET = "lomaspersad"
    localDir = Path(r"C:\Users\lxp1655\OneDrive - University of Miami\Projects\24 Yannuuzi IRIS Timing and Age as Determinants of Visual Outcomes and Complications in Pediatric Macular Hole Repair\R\data")


    # single file download
    # download_s3_file(
    #     s3,
    #     bucket=BUCKET,
    #     key="31_T2DM_CEIOL/analytic_cohort000.parquet",
    #     local_path=os.path.join(localDir, "analytic_cohort000.parquet"),
    # )
    

    # download all in folder 
    
    download_s3_prefix(
    s3,
    bucket=BUCKET,
    prefix="24_PMH2/",
    local_base=localDir
    )
    