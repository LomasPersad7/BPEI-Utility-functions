from PIL import Image, ImageFilter
import numpy as np


def find_overlap(img1, img2, max_search=400):
    import numpy as np

    def preprocess(img):
        # center crop (ignore margins)
        w, h = img.size
        img = img.crop((int(0.2*w), 0, int(0.8*w), h))

        img = img.resize((img.width // 2, img.height // 2))
        return np.array(img.convert("L"), dtype=np.float32)

    arr1 = preprocess(img1)
    arr2 = preprocess(img2)

    h1 = arr1.shape[0]

    best_overlap = 0
    best_score = float("inf")

    for overlap in range(80, max_search):
        slice1 = arr1[h1 - overlap:h1, :]
        slice2 = arr2[0:overlap, :]

        if slice1.shape != slice2.shape:
            continue

        # normalized difference (important)
        diff = np.mean(np.abs(slice1 - slice2))

        if diff < best_score:
            best_score = diff
            best_overlap = overlap

    return best_overlap, best_score


def stitch_with_overlap(image_paths, output_path="stitched.png"):
    from PIL import Image

    images = [Image.open(p) for p in image_paths]

    final = images[0]

    for i in range(1, len(images)):
        prev = final
        curr = images[i]

        overlap, score = find_overlap(prev, curr)

        print(f"[{i}] overlap={overlap}, score={score:.2f}")

        # ✅ Stronger safety rule
        if overlap < 60 or score > 25:
            print(f"⚠️ Weak match → reducing overlap")
            overlap = int(overlap * 0.5)

        curr_cropped = curr.crop((0, overlap, curr.width, curr.height))

        new_img = Image.new(
            "RGB",
            (prev.width, prev.height + curr_cropped.height)
        )

        new_img.paste(prev, (0, 0))
        new_img.paste(curr_cropped, (0, prev.height))

        final = new_img

    final.save(output_path)
    print(f"✅ Saved: {output_path}")

    return output_path


# def preprocess_for_matching(img, scale=0.5, blur=True):
#     """Prepare image for robust comparison."""
#     if blur:
#         img = img.filter(ImageFilter.GaussianBlur(1))

#     w, h = img.size
#     img = img.resize((int(w * scale), int(h * scale)))

#     return np.array(img.convert("L"))  # grayscale


# def find_overlap(img1, img2, max_search=800):
#     """
#     Find best vertical overlap between two images.
#     Returns (overlap_px, score)
#     """
#     arr1 = preprocess_for_matching(img1)
#     arr2 = preprocess_for_matching(img2)

#     h1 = arr1.shape[0]
#     best_overlap = 0
#     best_score = float("inf")

#     for overlap in range(50, max_search):
#         slice1 = arr1[h1 - overlap:h1, :]
#         slice2 = arr2[0:overlap, :]

#         if slice1.shape != slice2.shape:
#             continue

#         score = np.mean((slice1 - slice2) ** 2)

#         if score < best_score:
#             best_score = score
#             best_overlap = overlap

#     return best_overlap, best_score


# def crop_margins(img, margin_ratio=0.02):
#     """Remove small borders (scrollbars, padding, etc.)"""
#     w, h = img.size
#     dx = int(w * margin_ratio)
#     dy = int(h * margin_ratio)

#     return img.crop((dx, dy, w - dx, h - dy))


# def stitch_with_overlap(
#     image_paths,
#     output_path="stitched_clean.png",
#     crop_edges=True,
#     debug=False
# ):
#     images = [Image.open(p) for p in image_paths]

#     if crop_edges:
#         images = [crop_margins(img) for img in images]

#     final = images[0]

#     for i in range(1, len(images)):
#         prev = final
#         curr = images[i]

#         overlap, score = find_overlap(prev, curr)

#         if debug:
#             print(f"[{i}] overlap={overlap}px | score={score:.2f}")

#         # Safety check: skip bad matches
#         if overlap < 30 or score > 50:
#             print(f"⚠️ Poor match at image {i}, using fallback (no trim)")
#             overlap = 0

#         curr_cropped = curr.crop((0, overlap, curr.width, curr.height))

#         new_height = prev.height + curr_cropped.height
#         combined = Image.new("RGB", (prev.width, new_height))

#         combined.paste(prev, (0, 0))
#         combined.paste(curr_cropped, (0, prev.height))

#         final = combined

#     final.save(output_path)
#     print(f"✅ Stitched image saved: {output_path}")

#     return output_path