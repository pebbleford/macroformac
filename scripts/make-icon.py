# Regenerates Support/AppIcon.icns (needs Pillow):
#   python3 scripts/make-icon.py Support/AppIcon.icns /tmp/AppIcon.png
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
out_icns, out_png = sys.argv[1], sys.argv[2]

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

# Background squircle (macOS grid: 824px body, 100px margin)
body, margin, radius = 824, 100, 186
grad = Image.new("RGBA", (S, S))
top, bottom = (88, 86, 246, 255), (150, 56, 230, 255)
gd = ImageDraw.Draw(grad)
for y in range(S):
    gd.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([margin, margin, margin + body, margin + body], radius=radius, fill=255)

icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
# drop shadow of the body
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([margin, margin + 12, margin + body, margin + body + 12], radius=radius, fill=(0, 0, 0, 90))
icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
icon.paste(grad, (0, 0), mask)

# subtle top highlight
hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
for y in range(margin, margin + body // 2):
    a = int(40 * (1 - (y - margin) / (body / 2)))
    hd.line([(margin, y), (margin + body, y)], fill=(255, 255, 255, a))
hl_mask = Image.new("L", (S, S), 0)
hl_mask.paste(mask, (0, 0))
icon.alpha_composite(Image.composite(hl, Image.new("RGBA", (S, S), (0, 0, 0, 0)), hl_mask))

# Keycap
cap = 470
cx, cy = S // 2, S // 2 + 6
x0, y0 = cx - cap // 2, cy - cap // 2
capshadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(capshadow).rounded_rectangle([x0, y0 + 26, x0 + cap, y0 + cap + 26], radius=96, fill=(30, 10, 80, 120))
icon.alpha_composite(capshadow.filter(ImageFilter.GaussianBlur(22)))
d = ImageDraw.Draw(icon)
d.rounded_rectangle([x0, y0 + 16, x0 + cap, y0 + cap + 16], radius=96, fill=(206, 204, 236, 255))   # keycap side
d.rounded_rectangle([x0, y0, x0 + cap, y0 + cap], radius=96, fill=(250, 250, 255, 255))            # keycap top
d.rounded_rectangle([x0 + 38, y0 + 30, x0 + cap - 38, y0 + cap - 50], radius=70, fill=(240, 240, 252, 255))

# Lightning bolt on the cap
def bolt(scale, ox, oy):
    pts = [(0.58, 0.00), (0.12, 0.56), (0.44, 0.56), (0.34, 1.00), (0.86, 0.38), (0.53, 0.38), (0.66, 0.00)]
    return [(ox + x * scale, oy + y * scale) for x, y in pts]
bs = 300
bx, by = cx - bs * 0.49, y0 + 70
grad_b = Image.new("RGBA", (S, S))
gb = ImageDraw.Draw(grad_b)
for y in range(S):
    t = min(1, max(0, (y - by) / bs))
    gb.line([(0, y), (S, y)], fill=lerp((255, 196, 58, 255), (255, 112, 67, 255), t))
bmask = Image.new("L", (S, S), 0)
ImageDraw.Draw(bmask).polygon(bolt(bs, bx, by), fill=255)
bshadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(bshadow).polygon(bolt(bs, bx, by + 8), fill=(120, 50, 0, 80))
icon.alpha_composite(bshadow.filter(ImageFilter.GaussianBlur(6)))
icon.paste(grad_b, (0, 0), bmask)

icon.save(out_png)
icon.save(out_icns, sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
print("ok")
