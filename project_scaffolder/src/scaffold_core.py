from pathlib import Path
from .project_numbering import next_project_number
from .scaffold_r import create_r_structure

def create_project(metadata: dict, base_dir: Path) -> Path:
    """
    Create a new project folder with numbering and R scaffolding.
    """
    project_num = next_project_number(base_dir)
    title = metadata.get("Title", "Untitled").replace(" ", "_")
    project_name = f"{project_num}_{title}"
    project_path = base_dir / project_name
    project_path.mkdir(parents=True, exist_ok=True)

    # Create R scaffolding
    create_r_structure(project_path)

    return project_path
