from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
from PIL import Image
import numpy as np



def export_single_page_pdf(image_path, output_pdf="report.pdf"):
    img = Image.open(image_path)
    width, height = img.size

    c = canvas.Canvas(output_pdf, pagesize=(width, height))

    c.drawImage(
        ImageReader(img),
        0,
        0,
        width=width,
        height=height,
        preserveAspectRatio=True,
        mask='auto'
    )

    c.showPage()
    c.save()

    print(f"✅ High-quality single-page PDF saved: {output_pdf}")





def find_whitespace_rows(img, threshold=245):
    """Detect horizontal whitespace bands."""
    gray = np.array(img.convert("L"))
    row_means = gray.mean(axis=1)

    return row_means > threshold


def split_at_whitespace(img, min_gap=20):
    """Split image into chunks at whitespace regions."""
    whitespace = find_whitespace_rows(img)

    splits = []
    start = 0
    gap = 0

    for i, is_white in enumerate(whitespace):
        if is_white:
            gap += 1
        else:
            if gap >= min_gap:
                splits.append((start, i - gap))
                start = i
            gap = 0

    splits.append((start, img.height))

    return [img.crop((0, s, img.width, e)) for s, e in splits if e > s]


def export_paginated_pdf(image_path, output_pdf="report.pdf"):
    img = Image.open(image_path)

    chunks = split_at_whitespace(img)

    c = canvas.Canvas(output_pdf)

    for chunk in chunks:
        w, h = chunk.size
        c.setPageSize((w, h))

        c.drawImage(ImageReader(chunk), 0, 0, width=w, height=h)
        c.showPage()

    c.save()

    print(f"✅ Smart paginated PDF saved: {output_pdf}")



# from PIL import Image

# def image_to_pdf(image_path, output_pdf="report.pdf", page_height=1200):
#     img = Image.open(image_path)

#     width, height = img.size

#     pages = []

#     for y in range(0, height, page_height):
#         crop = img.crop((0, y, width, min(y + page_height, height)))
#         pages.append(crop.convert("RGB"))

#     pages[0].save(
#         output_pdf,
#         save_all=True,
#         append_images=pages[1:]
#     )

#     print(f"✅ PDF saved: {output_pdf}")
    
# # remove pages
# def image_to_single_page_pdf(image_path, output_pdf="report.pdf"):
#     img = Image.open(image_path).convert("RGB")

#     width, height = img.size

#     # Convert pixels → points (1 pt = 1/72 inch)
#     # Assume 96 DPI
#     pdf_width = width * 72 / 96
#     pdf_height = height * 72 / 96

#     img.save(
#         output_pdf,
#         "PDF",
#         resolution=600.0,
#         save_all=True
#     )

#     print(f"✅ Single-page PDF saved: {output_pdf}")