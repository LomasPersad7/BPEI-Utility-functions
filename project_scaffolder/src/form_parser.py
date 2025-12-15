from pathlib import Path

def parse_form(form_file: Path) -> dict:
    """
    Parse a simple key:value text form into a dictionary.
    """
    metadata = {}
    with open(form_file, "r") as f:
        for line in f:
            if ":" in line:
                key, value = line.strip().split(":", 1)
                metadata[key.strip()] = value.strip()
    return metadata
