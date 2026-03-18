import pyautogui
import time
import os
from PIL import Image
from detect import is_same

def capture_screenshots(
    region,
    output_dir="screenshots",
    max_shots=100,
    delay=1.5,
    pagedown_presses=1,
    stop_threshold=2.0, #If it stops too early:Increase threshold
    required_no_change=1,
    initial_delay=5
):
    os.makedirs(output_dir, exist_ok=True)

    print(f"Starting in {initial_delay} seconds...")
    print("➡️  Click into your VM window NOW")
    time.sleep(initial_delay)

    # Focus VM
    focus_x = region[0] + 100
    focus_y = region[1] + 100
    pyautogui.click(focus_x, focus_y)
    time.sleep(1)

    prev_img = None
    no_change_count = 0

    saved_files = []

    # for i in range(max_shots):
    #     raw = pyautogui.screenshot(region=region)

    #     # Crop edges to remove UI noise
    #     w, h = raw.size
    #     img = raw.crop((int(0.05*w), int(0.05*h), int(0.95*w), int(0.95*h)))

    #     filename = os.path.join(output_dir, f"screenshot_{i:03d}.png")
    #     raw.save(filename)
    #     saved_files.append(filename)


    #     print(f"[{i}] Captured")

    #     if prev_img is not None:
    #         if is_same(prev_img, img, threshold=stop_threshold):
    #             no_change_count += 1
    #             print(f"  No change detected ({no_change_count})")
    #         else:
    #             no_change_count = 0
                

    #         if no_change_count >= required_no_change:
    #             print("🛑 End of scroll detected.")
    #             break

    #     prev_img = img

    #     # Scroll
    #     for _ in range(pagedown_presses):
    #         pyautogui.press("pagedown")
    #         time.sleep(0.2)

    #     time.sleep(delay)

    # return saved_files

    for i in range(max_shots):
            raw = pyautogui.screenshot(region=region)

            # crop edges for comparison only
            w, h = raw.size
            img = raw.crop((int(0.1*w), int(0.1*h), int(0.9*w), int(0.9*h)))

            if prev_img is not None:
                from detect import is_same

                if is_same(prev_img, img, threshold=stop_threshold):
                    no_change_count += 1
                    print(f"[{i}] No change ({no_change_count})")

                    if no_change_count >= required_no_change:
                        print("🛑 End detected BEFORE saving duplicate.")
                        break
                else:
                    no_change_count = 0

            # ✅ ONLY save if it's new
            filename = os.path.join(output_dir, f"screenshot_{i:03d}.png")
            raw.save(filename)
            saved_files.append(filename)

            print(f"[{i}] Saved")

            prev_img = img

            # Scroll
            for _ in range(pagedown_presses):
                pyautogui.press("pagedown")
                time.sleep(0.2)

            time.sleep(delay)

    return saved_files