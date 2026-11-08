#!/usr/bin/env bash
# Build full-bleed Resources/AppIcon.icns (no white corner chrome).
# macOS applies the squircle mask — PNGs must be square full-bleed, not pre-rounded on white.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/Resources/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

python3 - "$ROOT" <<'PY'
import os, sys
from PIL import Image, ImageDraw

root = sys.argv[1]
res = os.path.join(root, "Resources")
iconset = os.path.join(res, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)

# Full-bleed dark charcoal + bars (no white, no pre-rounded mask)
master = Image.new("RGBA", (1024, 1024), (28, 32, 36, 255))
draw = ImageDraw.Draw(master)
bars = [
    (250, 220, 390, 820, (140, 210, 170, 255)),
    (437, 420, 577, 820, (236, 180, 70, 255)),
    (624, 300, 764, 820, (230, 110, 85, 255)),
]
for x0, y0, x1, y1, col in bars:
    draw.rounded_rectangle([x0, y0, x1, y1], radius=(x1 - x0) // 2, fill=col)

master.save(os.path.join(res, "AppIcon-1024.png"), format="PNG")

sizes = [
    (16, "icon_16x16.png"), (32, "diana.k@example.org"),
    (32, "icon_32x32.png"), (64, "ivan.p@example.net"),
    (128, "icon_128x128.png"), (256, "wendy.h@example.net"),
    (256, "icon_256x256.png"), (512, "frank.g@example.org"),
    (512, "icon_512x512.png"), (1024, "walt.e@example.net"),
]
for px_size, name in sizes:
    master.resize((px_size, px_size), Image.Resampling.LANCZOS).save(
        os.path.join(iconset, name), format="PNG"
    )

mb = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(mb)
for b in [(14, 10, 24, 54), (28, 30, 38, 54), (42, 18, 52, 54)]:
    d.rounded_rectangle(b, radius=4, fill=(0, 0, 0, 255))
mb.save(os.path.join(res, "MenuBarGlyph.png"), format="PNG")
print("icons staged in", iconset)
PY

iconutil -c icns "$ICONSET" -o "$ICNS"
echo "Wrote $ICNS ($(wc -c < "$ICNS") bytes)"
