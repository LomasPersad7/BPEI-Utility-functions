import os
import time
import pyautogui
from PIL import Image
import numpy as np
import cv2
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

# -----------------------------
# 1️⃣ Capture screenshots
# -----------------------------
def capture_screenshots(region, output_dir="screenshots",
                        delay=1.5, pagedown_presses=1,
                        stop_threshold=1.0, required_no_change=1,
                        initial_delay=3):
    """
    Captures consecutive screenshots of a scrolling report.
    Stops automatically when content stops changing.
    """
    os.makedirs(output_dir, exist_ok=True)

    print(f"Starting in {initial_delay} seconds...")
    time.sleep(initial_delay)

    prev_img = None
    no_change_count = 0
    saved_files = []

    for i in range(1000):  # max screenshots
        raw = pyautogui.screenshot(region=region)

        # Crop edges for comparison only
        w, h = raw.size
        img = raw.crop((int(0.1*w), int(0.1*h), int(0.9*w), int(0.9*h)))

        # Check if same as previous
        if prev_img is not None:
            diff = np.mean(np.abs(np.array(prev_img) - np.array(img)))
            if diff < stop_threshold:
                no_change_count += 1
                print(f"[{i}] No change ({no_change_count})")
                if no_change_count >= required_no_change:
                    print("🛑 End detected BEFORE saving duplicate.")
                    break
            else:
                no_change_count = 0

        # Save screenshot
        filename = os.path.join(output_dir, f"screenshot_{i:03d}.png")
        raw.save(filename)
        saved_files.append(filename)
        prev_img = img
        print(f"[{i}] Saved {filename}")

        # Scroll
        for _ in range(pagedown_presses):
            pyautogui.press("pagedown")
            time.sleep(0.2)

        time.sleep(delay)

    return saved_files

# -----------------------------
# 2️⃣ Feature-based stitching
# -----------------------------
def pil_to_cv_gray(img):
    # center crop to ignore margins
    w, h = img.size
    img_cropped = img.crop((int(0.2*w), 0, int(0.8*w), h))
    return cv2.cvtColor(np.array(img_cropped), cv2.COLOR_RGB2GRAY)

def find_vertical_shift(img1, img2):
    gray1 = pil_to_cv_gray(img1)
    gray2 = pil_to_cv_gray(img2)

    orb = cv2.ORB_create(5000)
    kp1, des1 = orb.detectAndCompute(gray1, None)
    kp2, des2 = orb.detectAndCompute(gray2, None)

    if des1 is None or des2 is None:
        return None

    bf = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
    matches = bf.match(des1, des2)

    if len(matches) < 20:
        return None

    # vertical differences
    shifts = [kp1[m.queryIdx].pt[1] - kp2[m.trainIdx].pt[1] for m in matches]
    return int(np.median(shifts))

def stitch_images_feature_based(image_paths, output_path="stitched.png"):
    images = [Image.open(p) for p in image_paths]
    final = images[0]

    for i in range(1, len(images)):
        prev = final
        curr = images[i]
        shift = find_vertical_shift(prev, curr)
        print(f"[{i}] vertical shift: {shift}")

        if shift is None or shift < 0 or shift > curr.height:
            shift = 0  # fallback

        # crop overlap
        curr_cropped = curr.crop((0, shift, curr.width, curr.height))
        new_img = Image.new("RGB", (prev.width, prev.height + curr_cropped.height))
        new_img.paste(prev, (0, 0))
        new_img.paste(curr_cropped, (0, prev.height))
        final = new_img

    final.save(output_path)
    print(f"✅ Stitched image saved: {output_path}")
    return output_path

# -----------------------------
# 3️⃣ Export high-res PDF
# -----------------------------
def export_single_page_pdf(image_path, output_pdf="final_report.pdf"):
    img = Image.open(image_path)
    width, height = img.size
    c = canvas.Canvas(output_pdf, pagesize=(width, height))
    c.drawImage(ImageReader(img), 0, 0, width=width, height=height, preserveAspectRatio=True, mask='auto')
    c.showPage()
    c.save()
    print(f"✅ PDF saved: {output_pdf}")

# -----------------------------
# 4️⃣ Full pipeline
# -----------------------------
def main():
    # Coordinates of the report area in your VM
    REGION = (687, 17, 1070, 1412)   # adjust as needed

    # Capture screenshots
    files = capture_screenshots(region=REGION)

    if not files:
        print("❌ No screenshots captured. Exiting.")
        return

    # Stitch all screenshots
    stitched = stitch_images_feature_based(files, output_path="final_report.png")

    if stitched is None:
        print("❌ Stitching failed. Exiting.")
        return

    # Export to single-page high-quality PDF
    export_single_page_pdf(stitched, output_pdf="final_report.pdf")

if __name__ == "__main__":
    main()