# code to copy donwnloaded s3 files to R location

from pathlib import Path
import shutil


def copy_all_parquet_files(src_root: str, dest_dir: str) -> None:
    """
    Copy all .parquet files from src_root and its subfolders
    into dest_dir (single flat folder).

    If filename collisions occur, files are renamed safely.
    """
    src_root = Path(src_root)
    dest_dir = Path(dest_dir)

    dest_dir.mkdir(parents=True, exist_ok=True)

    for parquet_file in src_root.rglob("*.parquet"):
        target = dest_dir / parquet_file.name

        # Handle duplicate filenames
        if target.exists():
            stem = parquet_file.stem
            suffix = parquet_file.suffix
            counter = 1
            while True:
                new_name = f"{stem}_{counter}{suffix}"
                target = dest_dir / new_name
                if not target.exists():
                    break
                counter += 1

        shutil.copy2(parquet_file, target)

def move_all_parquet_files(src_root: str, dest_dir: str) -> None:
    """
    Move all .parquet files from src_root and its subfolders
    into dest_dir (single flat folder).

    If filename collisions occur, files are renamed safely.
    """
    src_root = Path(src_root)
    dest_dir = Path(dest_dir)

    dest_dir.mkdir(parents=True, exist_ok=True)

    for parquet_file in src_root.rglob("*.parquet"):
        target = dest_dir / parquet_file.name

        # Handle duplicate filenames
        if target.exists():
            stem = parquet_file.stem
            suffix = parquet_file.suffix
            counter = 1
            while True:
                new_name = f"{stem}_{counter}{suffix}"
                target = dest_dir / new_name
                if not target.exists():
                    break
                counter += 1

        shutil.move(str(parquet_file), str(target))

if __name__ == "__main__":
    copy_all_parquet_files("s3://your-bucket/path/to/files", "/path/to/destination")