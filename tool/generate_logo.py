"""Draws the My Tour logo and writes every app icon size.

The logo is an original drawing: the silhouette of a traveller looking
through a spyglass. Run from the project root:

    python tool/generate_logo.py

Requires Pillow (pip install pillow).
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
INK = (17, 17, 17)
PAPER = (255, 255, 255)

# The drawing is laid out on a 1000 x 1000 grid.
GRID = 1000
# The figure rises from the bottom-left corner, as a bust running off the
# frame, and is shrunk towards that corner so the spyglass stays clear of the
# circle and rounded-square masks that launchers apply.
CONTENT_SCALE = 0.90
SUPERSAMPLE = 4

EYE = (418, 268)
SPYGLASS_TILT_DEGREES = -5  # rising towards the far end


def rotate_about(point, pivot, degrees):
    angle = math.radians(degrees)
    dx, dy = point[0] - pivot[0], point[1] - pivot[1]
    return (
        pivot[0] + dx * math.cos(angle) - dy * math.sin(angle),
        pivot[1] + dx * math.sin(angle) + dy * math.cos(angle),
    )


def tube(x_from, x_to, half_height):
    """A horizontal section of the spyglass at eye level, then tilted."""
    y = EYE[1]
    corners = [
        (x_from, y - half_height),
        (x_to, y - half_height),
        (x_to, y + half_height),
        (x_from, y + half_height),
    ]
    return [rotate_about(corner, EYE, SPYGLASS_TILT_DEGREES) for corner in corners]


def silhouette_polygons():
    """The parts of the figure that are plain polygons."""
    return [
        # Chest, running off the bottom edge.
        [(-60, 1060), (-60, 760), (200, 505), (385, 505), (520, 610), (630, 1060)],
        # Neck.
        [(215, 395), (355, 425), (372, 525), (195, 525)],
        # Nose.
        [(398, 300), (452, 338), (402, 352)],
        # Mouth and chin.
        [(330, 370), (415, 352), (428, 392), (410, 400), (420, 420), (385, 452), (318, 446)],
        # Forearm raised to hold the spyglass.
        [(432, 720), (562, 285), (640, 295), (560, 780)],
        # Spyglass: eyepiece, draw tube, joint, barrel, rim.
        tube(418, 478, 22),
        tube(470, 705, 31),
        tube(695, 722, 46),
        tube(715, 945, 43),
        tube(930, 958, 52),
    ]


def silhouette_ellipses():
    """The round parts: head, hand and shoulder, as (centre, x radius, y radius)."""
    hand = rotate_about((600, 268), EYE, SPYGLASS_TILT_DEGREES)
    return [((300, 300), 118, 138), (hand, 62, 58), ((150, 760), 260, 250)]


def to_canvas(point, size):
    """Grid coordinates to pixels, shrunk towards the bottom-left corner."""
    x = point[0] * CONTENT_SCALE
    y = GRID - (GRID - point[1]) * CONTENT_SCALE
    return (x * size / GRID, y * size / GRID)


def draw_logo(size):
    """The logo as an opaque square image, `size` pixels on each side."""
    big = size * SUPERSAMPLE
    image = Image.new("RGB", (big, big), PAPER)
    draw = ImageDraw.Draw(image)

    for polygon in silhouette_polygons():
        draw.polygon([to_canvas(point, big) for point in polygon], fill=INK)
    for centre, rx, ry in silhouette_ellipses():
        left_top = to_canvas((centre[0] - rx, centre[1] - ry), big)
        right_bottom = to_canvas((centre[0] + rx, centre[1] + ry), big)
        draw.ellipse([left_top, right_bottom], fill=INK)

    return image.resize((size, size), Image.LANCZOS)


ANDROID_SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# iOS file name -> pixels.
IOS_SIZES = {
    "Icon-App-20x20@1x": 20, "Icon-App-20x20@2x": 40, "Icon-App-20x20@3x": 60,
    "Icon-App-29x29@1x": 29, "Icon-App-29x29@2x": 58, "Icon-App-29x29@3x": 87,
    "Icon-App-40x40@1x": 40, "Icon-App-40x40@2x": 80, "Icon-App-40x40@3x": 120,
    "Icon-App-60x60@2x": 120, "Icon-App-60x60@3x": 180,
    "Icon-App-76x76@1x": 76, "Icon-App-76x76@2x": 152,
    "Icon-App-83.5x83.5@2x": 167,
    "Icon-App-1024x1024@1x": 1024,
}


def icon_targets():
    """Every file to write, as (path, pixels)."""
    android = ROOT / "android/app/src/main/res"
    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    targets = [(ROOT / "assets/logo.png", 512)]
    targets += [(android / f"mipmap-{d}/ic_launcher.png", px) for d, px in ANDROID_SIZES.items()]
    targets += [(ios / f"{name}.png", px) for name, px in IOS_SIZES.items()]
    return targets


def main():
    for path, pixels in icon_targets():
        path.parent.mkdir(parents=True, exist_ok=True)
        draw_logo(pixels).save(path)
        print(f"{pixels:>5}px  {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
