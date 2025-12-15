import requests

url = "https://rxnav.nlm.nih.gov/REST/drugs.json?name=hydroxyurea"
resp = requests.get(url).json()

results = []
for drug in resp.get("drugGroup", {}).get("conceptGroup", []):
    if drug.get("tty") == "IN":  # ingredient
        for c in drug.get("conceptProperties", []):
            results.append(c["rxcui"])

print(results)