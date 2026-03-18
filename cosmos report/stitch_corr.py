import os
import cv2
import numpy as np
from PIL import Image


def find_vertical_shift_multi(img1, img2):

    def preprocess(img):
        w, h = img.size
        img = img.crop((int(0.2*w), 0, int(0.8*w), h))
        return cv2.cvtColor(np.array(img), cv2.COLOR_RGB2GRAY)

    img1 = preprocess(img1)
    img2 = preprocess(img2)

    h = img1.shape[0]

    slices = [
        (0.5, 0.7),
        (0.6, 0.8),
        (0.7, 0.9)
    ]

    best = None

    for start_ratio, end_ratio in slices:
        y1 = int(h * start_ratio)
        y2 = int(h * end_ratio)

        template = img1[y1:y2, :]
        template_h = y2 - y1

        result = cv2.matchTemplate(img2, template, cv2.TM_CCOEFF_NORMED)
        _, score, _, loc = cv2.minMaxLoc(result)

        if best is None or score > best["score"]:
            best = {
                "shift": loc[1],
                "score": score,
                "template_h": template_h
            }

    return best

def blend_vertical(img1, img2, overlap):
    """Blend overlapping region instead of cutting"""
    if overlap <= 0:
        return img2

    blend_height = min(overlap, 50)  # smooth region

    top = np.array(img1[-blend_height:])
    bottom = np.array(img2[:blend_height])

    blended = np.zeros_like(top)

    for i in range(blend_height):
        alpha = i / blend_height
        blended[i] = (1 - alpha) * top[i] + alpha * bottom[i]

    return Image.fromarray(blended.astype(np.uint8))

def stitch_from_folder(
    folder_path,
    output_image="stitched.png",
    output_pdf=None
):
    """
    Stitch screenshots from a folder using robust correlation method.
    """

    # Load + sort files
    files = sorted([
        os.path.join(folder_path, f)
        for f in os.listdir(folder_path)
        if f.lower().endswith((".png", ".jpg", ".jpeg"))
    ])

    if not files:
        raise ValueError("No images found in folder")

    print(f"Found {len(files)} images")

    images = [Image.open(f) for f in files]

    final = images[0]

    for i in range(1, len(images)):
        prev = images[i - 1]
        curr = images[i]

        match = find_vertical_shift_multi(prev, curr)
        shift = match["shift"]
        template_h = match["template_h"]
        score = match["score"]

        print(f"[{i}] shift={shift}, template_h={template_h}, score={score:.3f}")


        # Confidence fallback
        if shift is None:
            print("⚠️ No match → minimal cut")
            shift = 10   # tiny overlap only

        # Clamp
        shift = max(0, min(shift, int(curr.height * 0.9)))

        # TRUE overlap boundary
        cut_point = shift + template_h

        # small safety buffer
        BUFFER = 10
        safe_cut = max(0, cut_point - BUFFER)

        # clamp
        safe_cut = min(safe_cut, curr.height)

        bottom_part = curr.crop((0, safe_cut, curr.width, curr.height))

        # Blend overlap region
        # blend = blend_vertical(
        #     np.array(final)[-50:], 
        #     np.array(curr)[:50], 
        #     overlap
        # )
        
        # Stitch
        # Combine
        new_img = Image.new(
            "RGB",
            (final.width, final.height + bottom_part.height)
        )

        # paste main parts
        new_img.paste(final, (0, 0))
        new_img.paste(bottom_part, (0, final.height))

        # overwrite seam with blended region
        # new_img.paste(Image.fromarray(blended), (0, final.height - blend_height))

        final = new_img

    # Save image
    final.save(output_image)
    print(f"✅ Stitched image saved: {output_image}")

    # Optional PDF export
    if output_pdf:
        from reportlab.pdfgen import canvas
        from reportlab.lib.utils import ImageReader

        width, height = final.size
        c = canvas.Canvas(output_pdf, pagesize=(width, height))
        c.drawImage(ImageReader(final), 0, 0, width=width, height=height)
        c.showPage()
        c.save()

        print(f"✅ PDF saved: {output_pdf}")

    return output_image