from PIL import Image

def stitch_images(image_paths, output_path="stitched.png"):
    images = [Image.open(p) for p in image_paths]

    width = max(img.width for img in images)
    height = sum(img.height for img in images)

    result = Image.new("RGB", (width, height))

    y_offset = 0
    for img in images:
        result.paste(img, (0, y_offset))
        y_offset += img.height

    result.save(output_path)
    print(f"✅ Stitched image saved to {output_path}")

    return output_path