#!/usr/bin/env bash
# Build Resources/AppIcon.icns from Resources/icon-option-bars.jpg
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/icon-option-bars.jpg"
ICONSET="$ROOT/Resources/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC" >&2
  exit 1
fi

python3 - "$SRC" "$ROOT" <<'PY'
import sys, os
from PIL import Image, ImageDraw

src_path, root = sys.argv[1], sys.argv[2]
iconset = os.path.join(root, "Resources", "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)

img = Image.open(src_path).convert("RGBA")
bg = (36, 41, 46, 255)
px = img.getpixel((2, 2))
corner_luma = (px[0] + px[1] + px[2]) / 3
base = Image.new("RGBA", (1024, 1024), bg)
if corner_luma > 200 or px[3] < 200:
    pad = 40
    inner = img.resize((1024 - 2 * pad, 1024 - 2 * pad), Image.Resampling.LANCZOS)
    base.paste(inner, (pad, pad), inner)
else:
    flat = Image.new("RGBA", (1024, 1024), bg)
    flat.paste(img, (0, 0), img)
    base = flat

master = base.convert("RGBA")
master.save(os.path.join(root, "Resources", "AppIcon-1024.png"), "PNG")

sizes = [
    (16, "icon_16x16.png"), (32, "diana.k@example.org"),
    (32, "icon_32x32.png"), (64, "ivan.p@example.net"),
    (128, "icon_128x128.png"), (256, "wendy.h@example.net"),
    (256, "icon_256x256.png"), (512, "frank.g@example.org"),
    (512, "icon_512x512.png"), (1024, "walt.e@example.net"),
]
for px_size, name in sizes:
    master.resize((px_size, px_size), Image.Resampling.LANCZOS).save(os.path.join(iconset, name), "PNG")

mb = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(mb)
for b in [(14, 10, 24, 54), (28, 30, 38, 54), (42, 18, 52, 54)]:
    d.rounded_rectangle(b, radius=4, fill=(0, 0, 0, 255))
mb.save(os.path.join(root, "Resources", "MenuBarGlyph.png"), "PNG")
print("icons staged in", iconset)
PY

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Wrote $ICNS ($(wc -c < "$ICNS") bytes)"
