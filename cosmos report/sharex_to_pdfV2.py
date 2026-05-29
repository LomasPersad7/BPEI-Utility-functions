#temp solution for now, will be replaced by a more robust one later. manually cut out the figures and tables, then run this to stitch the rest together. it will try to break at good points (between sections) and avoid breaking in the middle of figures. not perfect but better than nothing.

def smart_pdf_ultra(
    folder_path,
    output_pdf="final_report.pdf",
    page_width_px=2480,
    margin_px=60,
    page_ratio=1.414,
    search_window=400,
    figure_prefix="Screenshot"   # files starting with this = figures
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

        return white, density

    # -----------------------------
    # HEADER DETECTION
    # -----------------------------
    def detect_headers(white, density):
        headers = []
        for i in range(10, len(white) - 10):
            if white[i-5:i].mean() > 0.95 and density[i:i+5].mean() > 0.3:
                headers.append(i)
        return headers

    # -----------------------------
    # BREAK SELECTION
    # -----------------------------
    def choose_break(white, density, headers, target_y):
        h = len(white)

        start = max(0, target_y - search_window)
        end = min(h, target_y + search_window)

        best_y = target_y
        best_score = -999

        for i in range(start, end):
            score = 0

            score += white[i] * 2.0
            score -= density[i] * 2.5

            if any(abs(i - h0) < 10 for h0 in headers):
                score += 1.5

            if 5 < i < h - 5:
                score += np.mean(white[i-5:i+5]) * 1.5

            score -= abs(i - target_y) / search_window

            if score > best_score:
                best_score = score
                best_y = i

        return best_y

    # -----------------------------
    # AVOID CUTTING FIGURES
    # -----------------------------
    def adjust_avoid_figures(density, y):
        threshold = 0.45
        h = len(density)

        if density[y] > threshold:
            for i in range(y, max(0, y - 300), -1):
                if density[i] < threshold:
                    return i
            for i in range(y, min(h, y + 300)):
                if density[i] < threshold:
                    return i

        return y

    # -----------------------------
    # LOAD FILES
    # -----------------------------
    all_files = [
        f for f in os.listdir(folder_path)
        if f.lower().endswith((".png", ".jpg", ".jpeg"))
    ]

    main_files = sorted([
        os.path.join(folder_path, f)
        for f in all_files if not f.startswith(figure_prefix)
    ])

    figure_files = sorted([
        os.path.join(folder_path, f)
        for f in all_files if f.startswith(figure_prefix)
    ])  # , reverse=True descending

    if not main_files:
        raise ValueError("No main images found")

    pages = []

    # -----------------------------
    # PROCESS MAIN IMAGES
    # -----------------------------
    for file in main_files:
        print(f"Processing main: {file}")

        img = Image.open(file).convert("RGB")

        w, h = img.size
        scale = page_width_px / w
        img = img.resize((page_width_px, int(h * scale)), Image.LANCZOS)

        white, density = analyze(img)
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

    # -----------------------------
    # PROCESS FIGURES (FULL PAGE)
    # -----------------------------
    figure_pages = []
    page_height = int(page_width_px * page_ratio)

    for file in figure_files:
        print(f"Processing figure: {file}")

        img = Image.open(file).convert("RGB")

        # SAME resize logic as main
        w, h = img.size
        scale = page_width_px / w
        img = img.resize((page_width_px, int(h * scale)), Image.LANCZOS)

        H = img.height

        # If figure is taller than one page, we still split (rare but safe)
        if H > page_height:
            y = 0
            while y < H:
                crop = img.crop((0, y, page_width_px, min(y + page_height, H)))
                y += page_height

                canvas = Image.new(
                    "RGB",
                    (page_width_px + 2*margin_px, crop.height + 2*margin_px),
                    "white"
                )
                canvas.paste(crop, (margin_px, margin_px))
                figure_pages.append(canvas)
        else:
            # Single page figure (most common)
            canvas = Image.new(
                "RGB",
                (page_width_px + 2*margin_px, img.height + 2*margin_px),
                "white"
            )
            canvas.paste(img, (margin_px, margin_px))
            figure_pages.append(canvas)

    # -----------------------------
    # INTERLEAVE FIGURES
    # -----------------------------
    # final_pages = []
    # fig_idx = 0

    # for p in pages:
    #     final_pages.append(p)

    #     if fig_idx < len(figure_pages):
    #         final_pages.append(figure_pages[fig_idx])
    #         fig_idx += 1
        # leftover figures
    # final_pages.extend(figure_pages[fig_idx:])
    
    final_pages = pages + figure_pages  # just append all figures at the end for simplicity
    


    # -----------------------------
    # SAVE PDF
    # -----------------------------
    final_pages[0].save(
        output_pdf,
        save_all=True,
        append_images=final_pages[1:],
        resolution=300
    )

    print(f"✅ ULTRA PDF saved: {output_pdf}")


if __name__ == "__main__":
    smart_pdf_ultra(
        folder_path="sharex/DR_progression/new",
        output_pdf="final_report.pdf"
    )

    
