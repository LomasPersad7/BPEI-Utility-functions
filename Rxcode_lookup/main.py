import requests
import pandas as pd

# main code to look up RxNorm codes medication

#############################
# https://lhncbc.nlm.nih.gov/RxNav/APIs/RxNormAPIs.html?_gl=1*1408t02*_ga*MzI5NTIwMDQuMTc2NTIwNTcxNQ..*_ga_P1FPTH9PL4*czE3NjUyMDU3MTUkbzEkZzAkdDE3NjUyMDU3MTUkajYwJGwwJGgw*_ga_7147EPK006*czE3NjUyMDU3MTUkbzEkZzAkdDE3NjUyMDU3MTUkajYwJGwwJGgw
# https://www.nlm.nih.gov/research/umls/rxnorm/faq.html
# https://www.nlm.nih.gov/research/umls/rxnorm/docs/techdoc.html#s8_0
# 1. GET RXCUI FOR HYDROXYUREA
#############################

drug_name = "hydroxyurea"

resp = requests.get(f"https://rxnav.nlm.nih.gov/REST/rxcui.json?name={drug_name}")
rxcui = resp.json()["idGroup"]["rxnormId"][0]
print("Hydroxyurea RXCUI:", rxcui)

#############################
# 2. GET ALL HYDROXYUREA-RELATED RXNORM CONCEPTS
#############################

related = requests.get(
    f"https://rxnav.nlm.nih.gov/REST/rxcui/{rxcui}/allrelated.json"
).json()

hydroxyurea_rxnorm = set()

for group in related.get("allRelatedGroup", {}).get("conceptGroup", []):
    for cp in group.get("conceptProperties", []):
        hydroxyurea_rxnorm.add(cp["rxcui"])

print("Total hydroxyurea-related RXCUIs:", len(hydroxyurea_rxnorm))

#############################
# 3. GET ALL THERAPEUTIC CLASSES FOR HYDROXYUREA
#############################

classes = requests.get(
    f"https://rxnav.nlm.nih.gov/REST/rxclass/class/byDrug.json?rxcui={rxcui}"
).json()

sickle_cell_class_id = None

for c in classes.get("rxclassDrugInfoList", {}).get("rxclassDrugInfo", []):
    name = c["rxclassMinConcept"]["className"]
    if "sickle cell" in name.lower():
        sickle_cell_class_id = c["rxclassMinConcept"]["classId"]
        print("Found sickle-cell class:", name, "Class ID:", sickle_cell_class_id)

if sickle_cell_class_id is None:
    raise ValueError("❌ No Sickle Cell Anemia class found in RxClass for hydroxyurea.")

#############################
# 4. GET ALL DRUGS IN THE “SICKLE CELL ANEMIA AGENTS” CLASS
#############################

members = requests.get(
    f"https://rxnav.nlm.nih.gov/REST/rxclass/classMembers.json?classId={sickle_cell_class_id}"
).json()

sickle_cell_rxnorm = {
    m["minConcept"]["rxcui"]
    for m in members.get("drugMemberList", {}).get("drugMember", [])
}

print("Drugs in sickle cell therapeutic class:", len(sickle_cell_rxnorm))

#############################
# 5. INTERSECT HYDROXYUREA CONCEPTS WITH SICKLE CELL CLASS
#############################

relevant_rxnorm = hydroxyurea_rxnorm.intersection(sickle_cell_rxnorm)

print("Hydroxyurea RXCUIs used for sickle cell:", relevant_rxnorm)

#############################
# 6. GET NDCs FOR THESE RXCUIs
#############################

rows = []

for rx in relevant_rxnorm:
    ndc_resp = requests.get(f"https://rxnav.nlm.nih.gov/REST/rxcui/{rx}/ndcs.json").json()
    ndc_list = ndc_resp.get("ndcGroup", {}).get("ndcList", {}).get("ndc", [])
    
    for ndc in ndc_list:
        rows.append({"RXCUI": rx, "NDC": ndc})

df = pd.DataFrame(rows)
print(df)

#############################
# 7. EXPORT TO CSV
#############################

df.to_csv("hydroxyurea_sickle_cell_codes.csv", index=False)
print("\n📁 Saved as hydoxyurea_sickle_cell_codes.csv")
