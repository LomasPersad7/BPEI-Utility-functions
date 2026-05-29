from reportlab.platypus import SimpleDocTemplate, Image, PageBreak
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from PIL import Image as PILImage
import io


def smart_pdf_from_scroll(
    input_image_path,
    output_pdf="final_report.pdf",
    page_width_px=2480,
    margin_px=80,
    page_ratio=1.414,
    search_window=500
):
    import numpy as np
    from PIL import Image

    # -----------------------------
    # LOAD + NORMALIZE
    # -----------------------------
    img = Image.open(input_image_path).convert("RGB")

    w, h = img.size
    scale = page_width_px / w
    img = img.resize((page_width_px, int(h * scale)), Image.LANCZOS)

    # -----------------------------
    # ANALYSIS
    # -----------------------------
    gray = np.array(img.convert("L"))
    row_mean = np.mean(gray, axis=1)

    white = row_mean / 255.0
    density = 1 - white

    H = len(white)

    # -----------------------------
    # HEADER DETECTION (stronger)
    # -----------------------------
    headers = []
    for i in range(20, H - 20):
        if (
            np.mean(white[i-10:i]) > 0.97 and
            np.mean(density[i:i+10]) > 0.25
        ):
            headers.append(i)

    # -----------------------------
    # PAGE SETTINGS
    # -----------------------------
    page_height = int(page_width_px * page_ratio)

    pages = []
    y = 0

    # -----------------------------
    # MAIN SPLIT LOOP
    # -----------------------------
    while y < H:
        target = y + page_height

        if target >= H:
            crop = img.crop((0, y, page_width_px, H))
            y = H
        else:
            start = max(0, target - search_window)
            end = min(H, target + search_window)

            best_y = target
            best_score = -999

            for i in range(start, end):
                score = 0

                # Prefer whitespace
                score += white[i] * 3.0

                # Avoid dense regions (text blocks / figures)
                score -= density[i] * 3.5

                # Prefer areas surrounded by whitespace
                if 10 < i < H - 10:
                    score += np.mean(white[i-10:i+10]) * 2.0

                # Prefer near headers
                if any(abs(i - h0) < 15 for h0 in headers):
                    score += 2.0

                # Stay close to target
                score -= abs(i - target) / search_window

                if score > best_score:
                    best_score = score
                    best_y = i

            # -----------------------------
            # FIGURE PROTECTION (stronger)
            # -----------------------------
            if density[best_y] > 0.4:
                for i in range(best_y, max(y, best_y - 400), -1):
                    if density[i] < 0.3:
                        best_y = i
                        break

            # Fallback if weird cut
            if best_y <= y + 400 or abs(best_y - target) > 400:
                best_y = target

            crop = img.crop((0, y, page_width_px, best_y))
            y = best_y

        # -----------------------------
        # ADD MARGINS (PDF look)
        # -----------------------------
        canvas = Image.new(
            "RGB",
            (page_width_px + 2 * margin_px, crop.height + 2 * margin_px),
            "white"
        )
        canvas.paste(crop, (margin_px, margin_px))

        pages.append(canvas)

    # -----------------------------
    # SAVE PDF
    # -----------------------------
    pages[0].save(
        output_pdf,
        save_all=True,
        append_images=pages[1:],
        resolution=300
    )

    print(f"✅ PDF saved: {output_pdf}")


# import os
# from PIL import Image
# from reportlab.pdfgen import canvas
# from reportlab.lib.pagesizes import A4
# from reportlab.lib.units import inch



# def clean_temp_dir():
#     """Removes the temporary directory and its contents."""
#     if os.path.exists(TEMP_FOLDER):
#         for f in os.listdir(TEMP_FOLDER):
#             os.remove(os.path.join(TEMP_FOLDER, f))
#         os.rmdir(TEMP_FOLDER)
#     print(f"cleaned up temporary directory: '{TEMP_FOLDER}'")

# def is_line_blank(img, y, threshold):
#     """Checks if a horizontal line in the image is considered blank (white)."""
#     img_w, _ = img.size
#     count = 0
    
#     # We examine the middle 80% of the line to avoid border issues.
#     start_x = int(img_w * 0.1)
#     end_x = int(img_w * 0.9)
#     check_w = end_x - start_x

#     for x in range(start_x, end_x):
#         # We assume the image is grayscale or RGB; if RGB, convert to luminosity
#         pixel = img.getpixel((x, y))
#         if isinstance(pixel, int): # Grayscale
#             luma = pixel
#         elif len(pixel) >= 3: # RGB or RGBA
#             luma = 0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]
#         else: # Uncommon pixel format, treat as white
#             luma = 255
            
#         if luma >= threshold:
#             count += 1
            
#     # If a line is over 95% white space, it's a blank line.
#     return (count / check_w) >= 0.95

# def find_page_gaps(img):
#     """Analyzes the image to find suitable y-coordinates for page cuts."""
#     print("Analyzing image structure for natural gaps...")
#     img_w, img_h = img.size
    
#     # Pre-calculate the ideal slice height based on the target aspect ratio
#     ideal_slice_h = int(img_w * PREFERRED_PAGE_H_RATIO)
#     print(f"Targeting a slice height around: {ideal_slice_h} pixels.")

#     cut_points = [0] # Starting point
#     current_gap_start = -1
#     last_cut = 0
    
#     # Convert to grayscale once for efficient processing
#     gs_img = img.convert('L')
    
#     # Analyze row by row
#     for y in range(img_h):
#         if is_line_blank(gs_img, y, WHITE_THRESHOLD):
#             if current_gap_start == -1:
#                 current_gap_start = y
#         else:
#             # End of a white gap
#             if current_gap_start != -1:
#                 gap_height = y - current_gap_start
#                 if gap_height >= MIN_GAP_HEIGHT:
                    
#                     # We have a candidate gap. Now we decide if we should cut.
#                     # We cut if we've exceeded the ideal slice height,
#                     # or if the gap is massive, or we are near the end.
                    
#                     distance_from_last_cut = current_gap_start - last_cut
                    
#                     # Cut near the ideal height, or if the current section is getting way too tall.
#                     if distance_from_last_cut >= ideal_slice_h * 0.8:
#                         # Cut in the middle of the gap
#                         cut_y = current_gap_start + (gap_height // 2)
#                         cut_points.append(cut_y)
#                         last_cut = cut_y
#                         print(f"  Found natural break at y={cut_y} (height: {distance_from_last_cut}px)")
                        
#                 current_gap_start = -1 # Reset gap start

#     # Add the final boundary
#     cut_points.append(img_h)
    
#     # Remove duplicates and sort (though they should be sorted)
#     cut_points = sorted(list(set(cut_points)))
    
#     # Remove very small slices at the end (e.g., less than 100px)
#     if len(cut_points) >= 2:
#         final_height = cut_points[-1] - cut_points[-2]
#         if final_height < 100:
#             cut_points.pop(-2)
#             print(f"  Merged very small final section. New final cut: y={cut_points[-1]}")

#     print(f"Found {len(cut_points)-1} page breaks.")
#     return cut_points

# def main():
#     if not os.path.exists(INPUT_IMAGE):
#         print(f"Error: Could not find input image '{INPUT_IMAGE}'.")
#         return

#     # 1. Clean up and setup
#     clean_temp_dir()
#     os.makedirs(TEMP_FOLDER, exist_ok=True)

#     # 2. Open the source image
#     print(f"Opening long screenshot: {INPUT_IMAGE}")
#     source_img = Image.open(INPUT_IMAGE)
#     orig_w, orig_h = source_img.size
#     print(f"Original Dimensions: {orig_w}x{orig_h} pixels.")
    
#     # 3. Analyze gaps and find smart cut points
#     cut_points = find_page_gaps(source_img)

#     # 4. Generate the PDF
#     print(f"Generating PDF: {OUTPUT_PDF}...")
#     c = canvas.Canvas(OUTPUT_PDF, pagesize=A4)
#     c.setAuthor("Automated Quarto Export")
#     c.setTitle("Quarto Report Analysis")

#     # Define standard page width and height in points
#     a4_w_pt = A4_WIDTH_PT
#     a4_h_pt = A4_HEIGHT_PT
    
#     # Maintain a small margin (e.g., 0.2 inch) on left/right for aesthetics
#     side_margin_pt = 0.2 * inch
#     usable_width_pt = a4_w_pt - (2 * side_margin_pt)

#     slice_filenames = []
    
#     # Loop through the cut points and slice
#     for i in range(len(cut_points) - 1):
#         top = cut_points[i]
#         bottom = cut_points[i+1]
        
#         slice_box = (0, top, orig_w, bottom)
#         img_slice = source_img.crop(slice_box)
        
#         # Save a high-quality temporary PNG
#         slice_filename = os.path.join(TEMP_FOLDER, f"page_{i+1:03d}.png")
#         img_slice.save(slice_filename, format="PNG", optimize=True)
#         slice_filenames.append(slice_filename)
        
#         # Determine how to draw this slice on the PDF page
#         slice_w, slice_h = img_slice.size
        
#         # Calculate the scale factor needed to make the image fit the usable width
#         width_scale_factor = usable_width_pt / slice_w
        
#         # Calculate resulting dimensions on the PDF page
#         output_width_pt = usable_width_pt
#         output_height_pt = slice_h * width_scale_factor
        
#         # Start a new page, but first set standard page dimensions if it's not the first one
#         if i > 0:
#             c.showPage()
            
#         # Add the image, aligning it at the left margin and top edge of the page.
#         # ReportLab (0,0) is bottom-left. To draw from the top-left margin:
#         # X: side_margin_pt
#         # Y: Page_Height - margin_top - content_height. We have no top margin defined, so:
#         # Y: Page_Height - content_height
#         x_pt = side_margin_pt
#         y_pt = a4_h_pt - output_height_pt
        
#         c.drawImage(slice_filename, x_pt, y_pt, width=output_width_pt, height=output_height_pt, mask='auto', preserveAspectRatio=True)
        
#         # Optionally add a small footer (page number) at bottom right
#         c.setFont("Helvetica-Oblique", 9)
#         c.drawRightString(a4_w_pt - side_margin_pt, 0.3 * inch, f"Page {i+1}")

#     # 5. Finalize the PDF
#     c.save()
#     print(f"Successfully created PDF report: {os.path.abspath(OUTPUT_PDF)}")
    
#     # 6. Final Clean up
#     clean_temp_dir()


if __name__ == "__main__":
# Example usage
    smart_pdf_from_scroll("sharex/DR_progression/new/Proj1V2.jpg", "Proj1_report.pdf")
    
    
    # --- Configuration ---
    # INPUT_IMAGE = "sharex/DR_progression/Proj1V2.jpg"       # Name of your input image file
    # OUTPUT_PDF = "report.pdf"       # Desired output PDF filename
    # TEMP_FOLDER = "temp_slices"        # Temporary folder for slices

    # # White space detection settings
    # # We will define a potential page break if a row is overwhelmingly white.
    # WHITE_THRESHOLD = 250   # (0-255) A pixel must be whiter than this to count as blank.
    # MIN_GAP_HEIGHT = 15     # Minimum number of consecutive blank rows to be considered a 'gap'.
    # PREFERRED_PAGE_H_RATIO = 1.3 # Target aspect ratio for a standard page (Height/Width). 
    #                             # 1.3 is close to A4.

    # # Standard A4 size in points for reference
    # A4_WIDTH_PT, A4_HEIGHT_PT = A4 # 595.28, 841.89
    
    # main()