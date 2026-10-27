
import requests
import pandas as pd

from pathlib import Path

# ============================================================
# RxNorm -> NDC11 lookup
# ============================================================

BASE_URL = "https://rxnav.nlm.nih.gov/REST"
OUTPUT_FILE = "rxnorm_ndc11_results.csv"

session = requests.Session()
session.headers.update({"Accept": "application/json"})


def rxnorm_get(endpoint, params=None):
    """Make an RxNorm API request with basic error handling."""
    url = f"{BASE_URL}/{endpoint.lstrip('/')}"

    response = session.get(
        url,
        params=params,
        timeout=30
    )
    response.raise_for_status()
    return response.json()


def search_rxcuis(drug_name):
    """
    Search for a drug by generic name or brand name.
    Returns all exact-match RXCUIs returned by RxNorm.
    """
    data = rxnorm_get(
        "rxcui.json",
        params={"name": drug_name}
    )

    ids = data.get("idGroup", {}).get("rxnormId", [])
    return ids if ids else []


def get_drug_details(rxcui):
    """Get the name and term type for an RXCUI."""
    data = rxnorm_get(f"rxcui/{rxcui}/properties.json")

    props = data.get("properties") or {}

    return {
        "RXCUI": rxcui,
        "RxNorm_Name": props.get("name"),
        "Term_Type": props.get("tty")
    }


def get_ndc11(rxcui):
    """
    Retrieve active NDC11 codes associated with an RXCUI.
    RxNorm returns these in 11-digit CMS format.
    """
    data = rxnorm_get(f"rxcui/{rxcui}/ndcs.json")

    ndcs = (
        data.get("ndcGroup", {})
            .get("ndcList", {})
            .get("ndc", [])
    )

    # Normalize response shape in case of a single result.
    if isinstance(ndcs, str):
        ndcs = [ndcs]

    return ndcs


def search_drug_ndc11(drug_name):
    """
    Search a generic or brand drug name and return
    a DataFrame of associated active NDC11 codes.
    """
    rxcuis = search_rxcuis(drug_name)

    if not rxcuis:
        print(f"No exact RxNorm match found for: {drug_name}")
        print("Try a generic name, brand name, or drug strength.")
        return pd.DataFrame()

    rows = []

    for rxcui in rxcuis:
        try:
            details = get_drug_details(rxcui)
            ndcs = get_ndc11(rxcui)

            if not ndcs:
                # Preserve the RXCUI even when no NDC is available.
                rows.append({
                    "Search_Term": drug_name,
                    **details,
                    "NDC11": None
                })
                continue

            for ndc in ndcs:
                rows.append({
                    "Search_Term": drug_name,
                    **details,
                    "NDC11": ndc
                })

        except requests.RequestException as exc:
            print(f"API error for RXCUI {rxcui}: {exc}")

    return pd.DataFrame(rows)


# ============================================================
# Run a search
# ============================================================

if __name__ == "__main__":

    # Use either a generic or brand name.
    drug_name = input(
        "Enter a generic or brand drug name: "
    ).strip()

    if not drug_name:
        raise ValueError("Please enter a drug name.")

    df = search_drug_ndc11(drug_name)

    if not df.empty:
        df = df.drop_duplicates()

        print("\nSearch results:")
        print(df.to_string(index=False))

        df.to_csv(OUTPUT_FILE, index=False)

        print(f"\nSaved {len(df)} rows to {OUTPUT_FILE}")
