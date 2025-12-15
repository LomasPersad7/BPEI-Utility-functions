import re
from pathlib import Path

def next_project_number(base_dir: Path) -> str:
    """
    Find the next available project number like '001', '002', ...
    """
    existing = [p.name for p in base_dir.iterdir() if p.is_dir()]
    numbers = []
    for name in existing:
        match = re.match(r"(\d{3})_", name)
        if match:
            numbers.append(int(match.group(1)))
    return f"{(max(numbers) + 1) if numbers else 1:03d}"
