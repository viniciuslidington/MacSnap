#!/usr/bin/env python3
"""Regenerate the checked-in Retina installer artwork on macOS (Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SCALE = 2
image = Image.new("RGB", (1440, 1120), "#f7f5ef")
draw = ImageDraw.Draw(image)


def text(value, y, size, font="Arial.ttf", color="#24231f"):
    face = ImageFont.truetype("/System/Library/Fonts/Supplemental/" + font, size * SCALE)
    draw.text((720, y * SCALE), value, font=face, fill=color, anchor="mt")


text("A little more room.", 47, 42, "Georgia.ttf")
text("Drag MacSnap to Applications to install.", 110, 17)
text("Arraste o MacSnap para Aplicativos para instalar.", 139, 13, color="#737067")

# Keep the app and folder as real Finder icons; the artwork only guides the drag.
draw.line([(325 * 2, 252 * 2), (395 * 2, 252 * 2)], fill="#948d7d", width=3)
draw.line([(383 * 2, 240 * 2), (395 * 2, 252 * 2), (383 * 2, 264 * 2)],
          fill="#948d7d", width=3, joint="curve")
draw.line([(56 * 2, 367 * 2), (664 * 2, 367 * 2)], fill="#ddd8cc", width=2)
text("Then open MacSnap from Applications.", 392, 14)
text("Depois, abra o MacSnap pela pasta Aplicativos.", 419, 12, color="#737067")
text("MACSNAP  /  YOUR WINDOWS, IN THE RIGHT PLACE", 454, 9, color="#817b6e")
destination = ROOT / "Resources/Installer/background.png"
destination.parent.mkdir(parents=True, exist_ok=True)
image.save(destination, dpi=(144, 144), optimize=True)
print(destination)
