import time
import pyautogui
from PIL import Image

def scrolling_screenshot(
    output_file="scroll_capture.png",
    scroll_amount=-800,   # negative = scroll down
    scroll_delay=0.8,     # time between scrolls
    max_scrolls=20,       # how many scroll steps
    overlap_crop=100      # crop top pixels to remove overlap
):
    print("⏳ You have 3 seconds to click into your VM...")
    time.sleep(3)

    screenshots = []

    for i in range(max_scrolls):
        print(f"Capturing {i+1}/{max_scrolls}")

        img = pyautogui.screenshot()
        screenshots.append(img)

        pyautogui.scroll(scroll_amount)
        time.sleep(scroll_delay)

    # -----------------------------
    # STITCH IMAGES
    # -----------------------------
    widths, heights = zip(*(img.size for img in screenshots))

    total_height = heights[0]
    for h in heights[1:]:
        total_height += (h - overlap_crop)

    final_img = Image.new("RGB", (widths[0], total_height))

    y_offset = 0

    for i, img in enumerate(screenshots):
        if i == 0:
            final_img.paste(img, (0, y_offset))
            y_offset += img.height
        else:
            cropped = img.crop((0, overlap_crop, img.width, img.height))
            final_img.paste(cropped, (0, y_offset))
            y_offset += cropped.height

    final_img.save(output_file)
    print(f"✅ Saved: {output_file}")


if __name__ == "__main__":
    scrolling_screenshot(
        output_file="long_screenshot.png",
        max_scrolls=15
    )