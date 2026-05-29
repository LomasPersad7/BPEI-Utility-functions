import os
import csv

def txt_to_csv(txt_file_path):
    """
    Converts a text file of patient IDs into a CSV file in the same location.
    for import into S3 for -> AWS redshift; IRIS database
    
    Args:
        txt_file_path (str): Path to the input .txt file
    """
    # Get directory and output file path
    directory = os.path.dirname(txt_file_path)
    base_name = os.path.splitext(os.path.basename(txt_file_path))[0]
    csv_file_path = os.path.join(directory, f"{base_name}.csv")

    # Read patient IDs from txt file
    with open(txt_file_path, 'r') as txt_file:
        content = txt_file.read()
        # Split by any whitespace (handles newlines, spaces, tabs)
        patient_ids = content.split()

    # Write to CSV
    with open(csv_file_path, 'w', newline='') as csv_file:
        writer = csv.writer(csv_file)
        
        # Optional: write header
        writer.writerow(['patient_id'])
        
        # Write each ID as a row
        for pid in patient_ids:
            writer.writerow([pid])

    print(f"CSV file created at: {csv_file_path}")
    
    
if __name__ == "__main__":
    txt_to_csv("C:\\Users\\lxp1655\\OneDrive - University of Miami\\Projects\\25 Lee IRIS Risk of Glaucoma Following Vitrectomy, Scleral Buckle, and Combined Surgery A Propensity-Matched Analysis Using the IRIS Registry\\patient_ids.txt")