from capture import capture_screenshots
# from stitch import stitch_images
# from smart_stitch import stitch_with_overlap
from export_pdf import export_paginated_pdf, export_single_page_pdf #export_single_page_pdf  # or paginated version
from smart_stitch_cv import stitch_images_corr
from stitch_corr import stitch_from_folder

def main():
    REGION = (687, 8, 1070, 1412) # 125% zoom

    files = capture_screenshots(
        region=REGION,
        output_dir="screenshots",
        max_shots=100,
        delay=1.5,
        pagedown_presses=1,
        stop_threshold=2.0,
        required_no_change=1
    )

    print(f"Captured {len(files)} images")

    if files:
        # stitch_images(files, output_path="final_report.png")
        # stitched = stitch_with_overlap(files, "clean_report.png")
        # image_to_single_page_pdf(stitched, "final_report.pdf")
        
        # stitched = stitch_with_overlap(
        # files,
        # output_path="clean_report.png"
        # # crop_edges=True,
        # # debug=True
        # )
        
        # stitched =stitch_images_cv(files, output_path="final_report_cv.png")
        stitched =stitch_images_corr(files, output_path="final_report_opencv.png")
        # BEST OPTION
        export_single_page_pdf(stitched, "final_report.pdf")

        # OPTIONAL:
        # export_paginated_pdf(stitched, "final_report_paginated.pdf")
 

if __name__ == "__main__":
    # main()
    stitch_from_folder(
    folder_path="screenshots",
    output_image="final_report.png",
    output_pdf="final_report.pdf"   # optional
)