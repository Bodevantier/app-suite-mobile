from PIL import Image, ImageDraw
import os

# -------------------------------------------------------------------
# Shape coordinates extracted from the Lottie startup animation JSON
# (sdolve_welcome.json) — shape-local space, y-axis points downward.
# These are the final-state shapes: the octagonal border and the S.
# -------------------------------------------------------------------

# Border octagon (layer "Border", ind 6)
BORDER = [
    (131.55, 76.13), (444.87, 76.13), (500.82, 132.13), (500.82, 443.35),
    (444.87, 499.34), (131.55, 499.34), (75.60, 443.35),  (75.60, 132.13),
]

# S upper half (layer "S_top", ind 13)
S_TOP = [
    (134.69, 199.08), (134.69, 274.58), (259.91, 352.81), (357.16, 352.81),
    (186.25, 246.04), (186.25, 213.85), (203.18, 186.75), (378.32, 186.75),
    (363.11, 211.05), (406.79, 238.37), (439.06, 186.75), (439.06, 135.19),
    (174.56, 135.19),
]

# S lower half (layer "S_bottom", ind 14)
S_BOTTOM = [
    (439.06, 300.89), (439.06, 376.39), (399.11, 440.28), (134.69, 440.28),
    (134.69, 388.73), (166.96, 337.10), (210.64, 364.42), (195.43, 388.73),
    (370.57, 388.73), (387.50, 361.62), (387.50, 329.43), (216.59, 222.67),
    (313.84, 222.67),
]

# Bounding box of all content (driven by the border)
MIN_X, MAX_X = 75.60, 500.82
MIN_Y, MAX_Y = 76.13, 499.34
CONTENT_W = MAX_X - MIN_X   # ~425
CONTENT_H = MAX_Y - MIN_Y   # ~423


def render_icon(size: int) -> Image.Image:
    padding = size * 0.15
    drawable = size - 2 * padding
    scale = min(drawable / CONTENT_W, drawable / CONTENT_H)

    offset_x = padding + (drawable - CONTENT_W * scale) / 2
    offset_y = padding + (drawable - CONTENT_H * scale) / 2

    def t(pts):
        return [((x - MIN_X) * scale + offset_x,
                 (y - MIN_Y) * scale + offset_y) for x, y in pts]

    img = Image.new("RGB", (size, size), (255, 255, 255))
    draw = ImageDraw.Draw(img)

    # Border stroke width matches the Lottie value (38 / 425 ≈ 8.9 % of content)
    stroke_w = max(1, round(drawable * 0.09))

    # Draw border (outline only, no fill)
    draw.polygon(t(BORDER), fill=None, outline=(0, 0, 0), width=stroke_w)

    # Draw S (both halves filled solid black)
    draw.polygon(t(S_TOP),    fill=(0, 0, 0))
    draw.polygon(t(S_BOTTOM), fill=(0, 0, 0))

    return img


base = r"C:\Users\Simon\Documents\App\APP\APP\ble_application"

android_sizes = {
    "mipmap-mdpi":    48,
    "mipmap-hdpi":    72,
    "mipmap-xhdpi":   96,
    "mipmap-xxhdpi":  144,
    "mipmap-xxxhdpi": 192,
}

for folder, size in android_sizes.items():
    path = os.path.join(base, "android", "app", "src", "main", "res", folder, "ic_launcher.png")
    render_icon(size).save(path, "PNG")
    print(f"Saved {path} ({size}x{size})")

print("Done!")
