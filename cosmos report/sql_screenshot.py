import os
import numpy as np
from PIL import Image


def process_scrolling_screenshots(
    image_paths,
    output_pdf="processed_sql_code.pdf",
    output_dir="ocr_ready_pages",
    page_width_px=2480,
    margin_px=80,
    page_ratio=1.414,  # Standard A4 aspect ratio
    search_window=400
):
    """
    Ingests multiple ordered screenshots, stitches them together,
    intelligently breaks them at blank code lines, and outputs OCR-friendly images + PDF.
    """
    print(f"🔄 Ingesting {len(image_paths)} screenshot(s)...")

    # -----------------------------
    # 1. LOAD, NORMALIZE & STITCH
    # -----------------------------
    resized_imgs = []
    for path in image_paths:
        img = Image.open(path).convert("RGB")
        w, h = img.size
        scale = page_width_px / w
        resized = img.resize((page_width_px, int(h * scale)), Image.LANCZOS)
        resized_imgs.append(resized)

    total_height = sum(img.height for img in resized_imgs)
    master_img = Image.new("RGB", (page_width_px, total_height))

    y_offset = 0
    for img in resized_imgs:
        master_img.paste(img, (0, y_offset))
        y_offset += img.height

    # -----------------------------
    # 2. ANALYSIS & THEME DETECTION
    # -----------------------------
    gray = np.array(master_img.convert("L"))
    row_mean = np.mean(gray, axis=1)

    # Auto-detect Dark Mode vs Light Mode
    overall_mean = np.mean(row_mean)
    is_dark_mode = overall_mean < 128

    if is_dark_mode:
        bg_color = (30, 30, 30)  # Dark border padding
        min_val = np.min(row_mean)
        text_density = np.clip((row_mean - min_val) / 255.0, 0, 1)
    else:
        bg_color = (255, 255, 255)  # Light border padding
        text_density = 1.0 - (row_mean / 255.0)

    whitespace_score = 1.0 - text_density
    H = len(row_mean)

    # -----------------------------
    # 3. CODE BLOCK HEADER DETECTION
    # -----------------------------
    headers = []
    for i in range(20, H - 20):
        if (
            np.mean(whitespace_score[i - 10 : i]) > 0.90
            and np.mean(text_density[i : i + 10]) > 0.20
        ):
            headers.append(i)

    # -----------------------------
    # 4. SMART PAGE SPLITTING LOOP
    # -----------------------------
    page_height = int(page_width_px * page_ratio)
    pages = []
    y = 0

    while y < H:
        target = y + page_height

        if target >= H:
            crop = master_img.crop((0, y, page_width_px, H))
            y = H
        else:
            start = max(y + 200, target - search_window)
            end = min(H - 100, target + search_window)

            best_y = target
            best_score = -9999

            for i in range(start, end):
                score = 0.0

                # Prefer whitespace / empty lines in code
                score += whitespace_score[i] * 4.0
                score -= text_density[i] * 5.0

                # Prefer cuts surrounded by empty lines
                if 10 < i < H - 10:
                    score += np.mean(whitespace_score[i - 10 : i + 10]) * 3.0

                # Favor cuts right above SQL query blocks/headers
                if any(abs(i - h0) < 15 for h0 in headers):
                    score += 3.0

                # Distance penalty from target height
                score -= (abs(i - target) / search_window) * 2.0

                if score > best_score:
                    best_score = score
                    best_y = i

            # Protect against cutting through dense code lines
            if text_density[best_y] > 0.3:
                for i in range(best_y, max(y + 200, best_y - 300), -1):
                    if text_density[i] < 0.2:
                        best_y = i
                        break

            if best_y <= y + 200:
                best_y = target

            crop = master_img.crop((0, y, page_width_px, best_y))
            y = best_y

        # Add canvas border margins
        canvas = Image.new(
            "RGB",
            (page_width_px + 2 * margin_px, crop.height + 2 * margin_px),
            bg_color,
        )
        canvas.paste(crop, (margin_px, margin_px))
        pages.append(canvas)

    # -----------------------------
    # 5. EXPORT RESULTS
    # -----------------------------
    os.makedirs(output_dir, exist_ok=True)
    saved_images = []

    # Export high-res PNG pages
    for idx, page_img in enumerate(pages):
        img_filename = os.path.join(output_dir, f"page_{idx+1:02d}.png")
        page_img.save(img_filename, quality=95)
        saved_images.append(img_filename)

    # Export combined PDF
    if pages:
        pages[0].save(
            output_pdf, save_all=True, append_images=pages[1:], resolution=300
        )

    print(
        f"✅ Success! Created {len(pages)} page(s).\n"
        f"📁 PNG directory: '{output_dir}/'\n"
        f"📄 Document PDF: '{output_pdf}'"
    )

    return saved_images


# -----------------------------
# RUNNER
# -----------------------------
if __name__ == "__main__":
    # Pass your 3 screenshot paths in exact top-to-bottom order
    screenshots = ["sharex\\sql\\Proj_10_part3.png"]
    
    

    # Process and crop
    processed_files = process_scrolling_screenshots(
        image_paths=screenshots,
        output_pdf="final_sql_report.pdf",
        output_dir="ocr_pages",
    )
    
    
