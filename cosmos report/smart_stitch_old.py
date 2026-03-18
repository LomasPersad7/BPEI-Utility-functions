from PIL import Image
import numpy as np

# def find_overlap(img1, img2, search_height=300):
#     """
#     Find vertical overlap between bottom of img1 and top of img2.
#     Returns number of overlapping pixels.
#     """
#     img1_gray = np.array(img1.convert("L"))
#     img2_gray = np.array(img2.convert("L"))

#     h1 = img1_gray.shape[0]
#     h2 = img2_gray.shape[0]

#     best_overlap = 0
#     best_score = float("inf")

#     # Only search near edges (faster + more accurate)
#     for overlap in range(50, search_height):
#         slice1 = img1_gray[h1 - overlap:h1, :]
#         slice2 = img2_gray[0:overlap, :]

#         # Resize if needed (safety)
#         if slice1.shape != slice2.shape:
#             continue

#         diff = np.mean((slice1 - slice2) ** 2)

#         if diff < best_score:
#             best_score = diff
#             best_overlap = overlap

#     return best_overlap



# def stitch_with_overlap(image_paths, output_path="stitched_clean.png"):
#     images = [Image.open(p) for p in image_paths]

#     final = images[0]

#     for i in range(1, len(images)):
#         prev = final
#         curr = images[i]

#         overlap = find_overlap(prev, curr)

#         print(f"[{i}] Overlap detected: {overlap}px")

#         # Remove overlap from current image
#         curr_cropped = curr.crop((0, overlap, curr.width, curr.height))

#         # Combine
#         new_height = prev.height + curr_cropped.height
#         combined = Image.new("RGB", (prev.width, new_height))

#         combined.paste(prev, (0, 0))
#         combined.paste(curr_cropped, (0, prev.height))

#         final = combined

#     final.save(output_path)
#     print(f"✅ Clean stitched image saved: {output_path}")

#     return output_path




def find_overlap(img1, img2, max_search=400):

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

