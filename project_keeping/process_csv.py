import pandas as pd
from pathlib import Path
import re

# -------------------------------------------------------------------
# CONFIG
# -------------------------------------------------------------------

# Replace with your actual file paths
iris_csv = "C:\\Users\\lxp1655\\OneDrive - University of Miami\\GithubUM\\project_keeping\\Project Time Report - IRIS.csv"
cosmos_csv = "C:\\Users\\lxp1655\\OneDrive - University of Miami\\GithubUM\\project_keeping\\Project Time Report - COSMOS.csv"

# Output file
output_csv = "combined_project_summary.csv"

# -------------------------------------------------------------------
# HELPERS
# -------------------------------------------------------------------

def process_time_report(csv_path, source_name=None):
    """
    Build combined project summary from IRIS + Cosmos reports.

    Parameters
    ----------
    iris_csv : str
        Path to IRIS CSV

    cosmos_csv : str
        Path to Cosmos CSV

    submission_csv : str, optional
        CSV containing:
            - project_number
            - first_submission_date

    output_csv : str
        Output file path
    """

    df = pd.read_csv(csv_path)

    # ---------------------------------------------------------------
    # CLEAN COLUMN NAMES
    # ---------------------------------------------------------------
    df.columns = (
        df.columns
        .str.strip()
        .str.replace("\n", " ", regex=False)
    )

    print(f"\nColumns in {csv_path}:")
    print(df.columns.tolist())

    # ---------------------------------------------------------------
    # FIND DECIMAL HOURS COLUMN
    # ---------------------------------------------------------------
    decimal_col = None

    for col in df.columns:
        if "decimal" in col.lower():
            decimal_col = col
            break

    if decimal_col is None:
        raise ValueError("Could not find decimal hours column")

    print(f"Using hours column: {decimal_col}")

    # ---------------------------------------------------------------
    # PARSE DATES
    # ---------------------------------------------------------------
    df["Date/time"] = pd.to_datetime(
        df["Date/time"],
        errors="coerce"
    )

    df["End date/time"] = pd.to_datetime(
        df["End date/time"],
        errors="coerce"
    )

    # ---------------------------------------------------------------
    # EXTRACT PROJECT NUMBER + CLEAN PROJECT NAME
    #
    # Example:
    # "31 Palioura T2DM CEIOL"
    #
    # project_number = 31
    # project_name = Palioura T2DM CEIOL
    # ---------------------------------------------------------------
    def extract_project_info(task_list):

        if pd.isna(task_list):
            return pd.Series([None, None])

        task_list = str(task_list).strip()

        match = re.match(r"^(\d+)\s+(.*)$", task_list)

        if match:
            project_number = match.group(1)
            project_name = match.group(2)
        else:
            project_number = None
            project_name = task_list

        return pd.Series([project_number, project_name])

    df[["project_number", "project_name"]] = (
        df["Task list"]
        .apply(extract_project_info)
    )

    # ---------------------------------------------------------------
    # PARSE TAGS
    #
    # Rules:
    # - contains IRIS -> IRIS
    # - contains Cosmos -> Cosmos
    # - contains both -> Both
    # - contains Extraction -> extraction column
    # ---------------------------------------------------------------
    def parse_tags(tag_value):

        if pd.isna(tag_value):
            return pd.Series([None, None, None])

        tag_text = str(tag_value)

        # Split tags
        parts = [
            p.strip()
            for p in tag_text.split(",")
            if p.strip()
        ]

        tag_lower = tag_text.lower()

        # ---------------------------------------------------------------
        # DETERMINE DATABASE
        # ---------------------------------------------------------------
        has_iris = "iris" in tag_lower
        has_cosmos = "cosmos" in tag_lower

        if has_iris and has_cosmos:
            project_db = "Both"
        elif has_iris:
            project_db = "IRIS"
        elif has_cosmos:
            project_db = "Cosmos"
        else:
            project_db = None

        # ---------------------------------------------------------------
        # EXTRACTION FLAG
        # ---------------------------------------------------------------
        extraction = ""

        if "extraction" in tag_lower:
            extraction = "Data Extraction/Filtering"

        # ---------------------------------------------------------------
        # PI NAME = LAST TAG
        # ---------------------------------------------------------------
        pi_name = None

        if len(parts) > 0:
            pi_name = parts[-1]

        return pd.Series([
            project_db,
            extraction,
            pi_name
        ])

    df[["project_db", "extraction_work", "pi_name"]] = (
        df["Task tags"]
        .apply(parse_tags)
    )

    # ---------------------------------------------------------------
    # NUMERIC HOURS
    # ---------------------------------------------------------------
    df[decimal_col] = pd.to_numeric(
        df[decimal_col],
        errors="coerce"
    ).fillna(0)

    # ---------------------------------------------------------------
    # GROUP BY PROJECT NAME
    # ---------------------------------------------------------------
    grouped = (
        df.groupby(
            ["project_number", "project_name"],
            dropna=False
        )
        .agg(
            start_date=("Date/time", "min"),
            last_recorded_date=("End date/time", "max"),
            project_db=("project_db", "first"),
            extraction_work=("extraction_work", "first"),
            total_hours=(decimal_col, "sum"),
            # total_entries=("project_name", "size"),
            pi_name=("pi_name", "first")
        )
        .reset_index()
    )
    
    
    manual_rows = pd.DataFrame([
    {
        "project_number": "28",
        "project_name": "Medeiros IRIS Impact of topical anti-inflammatory treatment on the outcomes of selective laser trabeculoplasty",
        "start_date": pd.to_datetime("09/08/2025"),
        "last_recorded_date": pd.to_datetime("09/12/2025"),
        "project_db": "IRIS",
        "extraction_work": "Data Extraction/Filtering",
        "total_hours": 20,
        # "total_entries": 1,
        "pi_name": "Medeiros"
    },

    # Add more rows below if needed
    # {
    #     "project_number": "",
    #     "project_name": "",
    #     "start_date": pd.to_datetime("2026-01-01"),
    #     "last_recorded_date": pd.to_datetime("2026-01-01"),
    #     "project_db": "",
    #     "extraction_work": "",
    #     "total_hours": 0,
    #     "total_entries": 1,
    #     "pi_name": ""
    # },
    ])

    # Append manual rows
    grouped = pd.concat(
        [grouped, manual_rows],
        ignore_index=True
    )
    
    # ---------------------------------------------------------------
    # FORMAT DATES
    # ---------------------------------------------------------------
    grouped["start_date"] = (
        grouped["start_date"]
        .dt.strftime("%m/%d/%Y")
    )

    grouped["last_recorded_date"] = (
        grouped["last_recorded_date"]
        .dt.strftime("%m/%d/%Y")
    )

    # ---------------------------------------------------------------
    # ROUND HOURS
    # ---------------------------------------------------------------
    grouped["total_hours"] = (
        grouped["total_hours"]
        .round(2)
    )

    # ---------------------------------------------------------------
    # SOURCE COLUMN
    # ---------------------------------------------------------------
    # grouped["source"] = source_name

    return grouped


# -------------------------------------------------------------------
# PROCESS FILES
# -------------------------------------------------------------------

iris_summary = process_time_report(
    iris_csv,
    source_name="IRIS"
)

cosmos_summary = process_time_report(
    cosmos_csv,
    source_name="COSMOS"
)

# -------------------------------------------------------------------
# COMBINE
# -------------------------------------------------------------------

super_list = pd.concat(
    [iris_summary, cosmos_summary],
    ignore_index=True
)

# -------------------------------------------------------------------
# SORT
# -------------------------------------------------------------------

super_list = super_list.sort_values(
    by=["project_number", "start_date"]
)

# -------------------------------------------------------------------
# SAVE
# -------------------------------------------------------------------

super_list.to_csv(output_csv, index=False)

print("\nDone.")
print(f"Saved to: {output_csv}")

print("\nPreview:")
print(super_list.head())