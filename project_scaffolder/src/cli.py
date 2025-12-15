import typer
from pathlib import Path
from . import scaffold_core, form_parser

app = typer.Typer(help="Project scaffolding CLI")

@app.command()
def create(form_file: Path, base_dir: Path):
    """
    Create a new project using a form text file and base directory.
    """
    metadata = form_parser.parse_form(form_file)
    project_path = scaffold_core.create_project(metadata, base_dir)
    typer.echo(f"✅ Project created at {project_path}")
