import cv2
import numpy as np
from PIL import Image


def find_vertical_shift_corr(img1, img2):
    """
    Find vertical shift using cross-correlation (robust for text/tables)
    """
    img1 = cv2.cvtColor(np.array(img1), cv2.COLOR_RGB2GRAY)
    img2 = cv2.cvtColor(np.array(img2), cv2.COLOR_RGB2GRAY)

    # Use bottom of img1 as template
    h = img1.shape[0]
    template = img1[int(h*0.5):h, :]

    # Match inside img2
    result = cv2.matchTemplate(img2, template, cv2.TM_CCOEFF_NORMED)

    _, _, _, max_loc = cv2.minMaxLoc(result)

    return max_loc[1]  # y shift



def stitch_images_corr(image_paths, output_path="stitched.png"):
    images = [Image.open(p) for p in image_paths]

    final = images[0]

    for i in range(1, len(images)):
        prev = images[i - 1]
        curr = images[i]

        shift = find_vertical_shift_corr(prev, curr)

        print(f"[{i}] shift={shift}")

        # Clamp
        shift = max(0, min(shift, int(curr.height * 0.9)))

        curr_cropped = curr.crop((0, shift, curr.width, curr.height))

        new_img = Image.new(
            "RGB",
            (final.width, final.height + curr_cropped.height)
        )

        new_img.paste(final, (0, 0))
        new_img.paste(curr_cropped, (0, final.height))

        final = new_img

    final.save(output_path)
    return output_path