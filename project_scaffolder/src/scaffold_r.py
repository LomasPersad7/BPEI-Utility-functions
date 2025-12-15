from pathlib import Path

def create_r_structure(project_path: Path):
    """
    Create standard R project folders.
    """
    for subdir in ["R", "data", "analysis", "sql"]:
        (project_path / subdir).mkdir(parents=True, exist_ok=True)

    rproj_file = project_path / f"{project_path.name}.Rproj"
    rproj_file.write_text("Version: 1.0\n")

