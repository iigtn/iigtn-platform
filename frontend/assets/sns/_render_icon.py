"""
Direct Pillow renderer for icon.svg -> 400x400 PNG.

Why direct draw instead of cairosvg/svglib? The cairo native DLL is
not present on this machine and pip can't install one without admin.
The icon is a deterministic set of rectangles + a rounded-square fill,
so reproducing it directly is reliable and dependency-light.

Source SVG (viewBox 64x64):
  - rounded square fill #2a6acc, x0..64 y0..64, rx=8
  - white left bracket  : M14,12 h10 v4 h-6 v32 h6 v4 h-10 Z
  - white right bracket : M50,12 h-10 v4 h6 v32 h-6 v4 h10 Z
  - white i dot         : rect 29,20 6x6
  - white i stem        : rect 29,30 6x18

We scale 64 -> 400 (factor 6.25) and use supersampling (2x) + LANCZOS
downscale for smooth edges on the rounded corners.
"""
from PIL import Image, ImageDraw

SUPER = 2          # supersample factor for AA on the rounded corners
SIZE = 400 * SUPER
SCALE = SIZE / 64.0  # SVG-units -> pixel scale
BLUE = (42, 106, 204, 255)   # #2a6acc
WHITE = (255, 255, 255, 255)


def s(v):
    return v * SCALE


img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# Rounded square background (rx=8 in 64-unit space)
d.rounded_rectangle(
    [(s(0), s(0)), (s(64), s(64))],
    radius=s(8),
    fill=BLUE,
)

# Left bracket [ : path "M14,12 h10 v4 h-6 v32 h6 v4 h-10 Z"
# = outer rect 14..24 / 12..52 minus inner notch 18..24 / 16..48
d.rectangle([(s(14), s(12)), (s(24), s(52))], fill=WHITE)
d.rectangle([(s(18), s(16)), (s(24), s(48))], fill=BLUE)

# Right bracket ] : "M50,12 h-10 v4 h6 v32 h-6 v4 h10 Z"
# = outer rect 40..50 / 12..52 minus inner notch 40..46 / 16..48
d.rectangle([(s(40), s(12)), (s(50), s(52))], fill=WHITE)
d.rectangle([(s(40), s(16)), (s(46), s(48))], fill=BLUE)

# i dot
d.rectangle([(s(29), s(20)), (s(35), s(26))], fill=WHITE)

# i stem
d.rectangle([(s(29), s(30)), (s(35), s(48))], fill=WHITE)

# Downscale to 400x400 with high-quality filter
out = img.resize((400, 400), Image.LANCZOS)
out.save(
    r"g:\マイドライブ\site_ポートフォリオ\frontend\assets\sns\icon-400.png",
    format="PNG",
    optimize=True,
)
print("OK 400x400")
