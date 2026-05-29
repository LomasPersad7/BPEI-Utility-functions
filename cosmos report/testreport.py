import sys
from io import BytesIO
from PIL import Image as PILImage
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.utils import ImageReader
from reportlab.platypus import SimpleDocTemplate, Image, PageBreak

def long_screenshot_to_pdf(input_image_path: str, output_pdf_path: str,
                           page_size=letter, margin_inches=0.5,
                           scale_to_width: bool = True) -> None:
    """
    Convert a tall screenshot (scrolling screenshot) into a multi‑page PDF.
    Each PDF page shows a vertical slice of the original image, scaled to fit
    the page width.

    Args:
        input_image_path: Path to the input image (PNG, JPG, etc.).
        output_pdf_path: Path where the output PDF will be saved.
        page_size: Tuple (width, height) in points (default: letter).
        margin_inches: Margins on all sides in inches (default: 0.5).
        scale_to_width: If True, scale each slice to fit page width;
                        if False, use original image width (centered).
    """
    # 1. Load the image
    try:
        full_img = PILImage.open(input_image_path)
    except Exception as e:
        raise RuntimeError(f"Could not load image: {e}")

    img_width, img_height = full_img.size

    # 2. PDF page dimensions
    page_width, page_height = page_size
    margin_pts = margin_inches * inch
    usable_width = page_width - 2 * margin_pts
    usable_height = page_height - 2 * margin_pts

    # 3. Determine scaling factor and slice height in pixels
    if scale_to_width:
        scale = usable_width / img_width
    else:
        scale = 1.0
        # If original width is larger than usable width, we must still fit
        if img_width > usable_width:
            scale = usable_width / img_width

    # Height (in points) that a slice will occupy on the PDF page
    slice_display_height = usable_height
    # Corresponding height in pixels (the amount we crop from the original image)
    slice_pixel_height = int(slice_display_height / scale)

    # 4. Prepare PDF document
    doc = SimpleDocTemplate(
        output_pdf_path,
        pagesize=page_size,
        leftMargin=margin_pts,
        rightMargin=margin_pts,
        topMargin=margin_pts,
        bottomMargin=margin_pts
    )

    elements = []
    y = 0
    slice_index = 0

    # 5. Crop the image into vertical slices
    while y < img_height:
        # Define crop box (left, upper, right, lower)
        top = y
        bottom = min(y + slice_pixel_height, img_height)
        box = (0, top, img_width, bottom)

        # Crop the slice
        slice_img = full_img.crop(box)

        # Convert PIL image to a format ReportLab can embed without saving to disk
        img_buffer = BytesIO()
        slice_img.save(img_buffer, format='PNG')
        img_buffer.seek(0)
        img_reader = ImageReader(img_buffer)

        # The displayed width and height in points
        display_width = slice_img.width * scale
        display_height = slice_img.height * scale

        # Add the image (centered horizontally if scale_to_width is False)
        if scale_to_width:
            # Image will be placed at left margin (already set in doc)
            elements.append(Image(img_reader, width=display_width, height=display_height))
        else:
            # Center the image on the page
            x_offset = (page_width - display_width) / 2
            # ReportLab's Image does not support direct x/y positioning;
            # we use a workaround: create a sub‑document with a centered table or use a Flowable.
            # For simplicity, we keep left alignment with margins – most screenshots should scale.
            elements.append(Image(img_reader, width=display_width, height=display_height))

        # Move to next slice
        y += slice_pixel_height
        slice_index += 1

        # Add a page break after every slice except the last one
        if y < img_height:
            elements.append(PageBreak())

    # 6. Build the PDF
    doc.build(elements)
    print(f"PDF successfully created: {output_pdf_path} (total {slice_index} page(s))")

if __name__ == "__main__":
    # Example usage – adjust file names as needed
    # if len(sys.argv) != 3:
    #     print("Usage: python script.py input_image.png output_report.pdf")
    #     sys.exit(1)

    # input_path = sys.argv[1]
    # output_path = sys.argv[2]

    long_screenshot_to_pdf("sharex/DR_progression/new/Proj1V2.jpg", "Proj1_report.pdf")