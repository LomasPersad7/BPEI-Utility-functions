def smart_pdf_ultra(
    folder_path,
    output_pdf="final_report.pdf",
    page_width_px=2480,
    margin_px=60,
    page_ratio=1.414,
    search_window=400
):
    import os
    import numpy as np
    from PIL import Image

    # -----------------------------
    # ANALYSIS
    # -----------------------------
    def analyze(img):
        gray = np.array(img.convert("L"))
        row_means = np.mean(gray, axis=1)

        white = row_means / 255.0
        density = 1 - white

        return white, density, gray

    # -----------------------------
    # DETECT CONTINUOUS BANDS
    # -----------------------------
    def find_bands(signal, threshold, min_len=20, mode="above"):
        bands = []
        start = None

        for i, val in enumerate(signal):
            cond = val > threshold if mode == "above" else val < threshold

            if cond:
                if start is None:
                    start = i
            else:
                if start is not None:
                    if i - start >= min_len:
                        bands.append((start, i))
                    start = None

        if start is not None:
            bands.append((start, len(signal)))

        return bands

    # -----------------------------
    # HEADER DETECTION
    # -----------------------------
    def detect_headers(white, density):
        headers = []

        for i in range(10, len(white) - 10):
            # whitespace above + text below
            if white[i-5:i].mean() > 0.95 and density[i:i+5].mean() > 0.3:
                headers.append(i)

        return headers

    # -----------------------------
    # FIND BEST BREAK
    # -----------------------------
    def choose_break(white, density, headers, target_y):
        h = len(white)

        start = max(0, target_y - search_window)
        end = min(h, target_y + search_window)

        best_y = target_y
        best_score = -999

        for i in range(start, end):

            score = 0

            # whitespace preference
            score += white[i] * 2.0

            # avoid dense (figures)
            score -= density[i] * 2.5

            # prefer headers (break before sections)
            if any(abs(i - h0) < 10 for h0 in headers):
                score += 1.5

            # smooth band bonus
            if i > 5 and i < h - 5:
                local_white = white[i-5:i+5].mean()
                score += local_white * 1.5

            # distance penalty
            score -= abs(i - target_y) / search_window

            if score > best_score:
                best_score = score
                best_y = i

        return best_y

    # -----------------------------
    # FIGURE LOCKING
    # -----------------------------
    def adjust_avoid_figures(density, y):
        threshold = 0.45
        h = len(density)

        if density[y] > threshold:
            # move upward first
            for i in range(y, max(0, y - 300), -1):
                if density[i] < threshold:
                    return i

            # fallback downward
            for i in range(y, min(h, y + 300)):
                if density[i] < threshold:
                    return i

        return y

    # -----------------------------
    # MAIN
    # -----------------------------
    files = sorted([
        os.path.join(folder_path, f)
        for f in os.listdir(folder_path)
        if f.lower().endswith((".png", ".jpg", ".jpeg"))
    ])

    if not files:
        raise ValueError("No images found")

    pages = []

    for file in files:
        print(f"Processing: {file}")

        img = Image.open(file).convert("RGB")

        # resize
        w, h = img.size
        scale = page_width_px / w
        img = img.resize((page_width_px, int(h * scale)), Image.LANCZOS)

        white, density, gray = analyze(img)
        headers = detect_headers(white, density)

        page_height = int(page_width_px * page_ratio)

        y = 0
        H = img.height

        while y < H:
            target = y + page_height

            if target >= H:
                crop = img.crop((0, y, page_width_px, H))
                y = H
            else:
                break_y = choose_break(white, density, headers, target)
                break_y = adjust_avoid_figures(density, break_y)

                # safety guards
                if break_y <= y + 300:
                    break_y = target

                if abs(break_y - target) > 300:
                    break_y = target

                crop = img.crop((0, y, page_width_px, break_y))
                y = break_y

            canvas = Image.new(
                "RGB",
                (page_width_px + 2*margin_px, crop.height + 2*margin_px),
                "white"
            )
            canvas.paste(crop, (margin_px, margin_px))

            pages.append(canvas)

    # save PDF
    pages[0].save(
        output_pdf,
        save_all=True,
        append_images=pages[1:],
        resolution=300
    )

    print(f"✅ ULTRA PDF saved: {output_pdf}")

if __name__ == "__main__":
    smart_pdf_ultra(
        folder_path="sharex",
        output_pdf="final_report.pdf"
    )
    
