from project_scaffolder import form_parser
from pathlib import Path

def test_parse_form(tmp_path):
    file = tmp_path / "form.txt"
    file.write_text("Title: My Test Project\nPI: Dr. X\n")
    metadata = form_parser.parse_form(file)
    assert metadata["Title"] == "My Test Project"
    assert metadata["PI"] == "Dr. X"


