# this function batch renames csv files from reshift
# when saved as csvxxx.gz renames to xxxcsv.gz so can recongise as standard csv file after extracting

import os

# Folder containing the .gz files
folder_path = "C:/Users/lxp1655/Downloads/test"

for filename in os.listdir(folder_path):
    if filename.endswith(".gz") and "csv000" in filename:
        old_path = os.path.join(folder_path, filename)
        new_filename = filename.replace("csv000", "csv")
        new_path = os.path.join(folder_path, new_filename)
        os.rename(old_path, new_path)
        print(f"Renamed: {filename} -> {new_filename}")