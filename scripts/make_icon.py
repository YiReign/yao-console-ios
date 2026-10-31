#!/usr/bin/env python3
"""生成 1024x1024 App 图标：浅紫渐变 + 白色圆角面板 + 进度条元素"""
from PIL import Image, ImageDraw, ImageFilter
import os

S = 1024
img = Image.new("RGBA", (S, S), (245, 243, 255, 255))
d = ImageDraw.Draw(img)

# 对角渐变 浅紫 → 淡蓝紫
for y in range(S):
    t = y / S
    r = int(238 + (215 - 238) * t)
    g = int(232 + (224 - 232) * t)
    b = int(255 + (252 - 255) * t)
    d.line([(0, y), (S, y)], fill=(r, g, b, 255))

overlay = Image.new("RGBA", (S, S), (0, 0, 0, 0))
od = ImageDraw.Draw(overlay)

# 柔和光晕
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([140, 90, 880, 700], fill=(115, 102, 232, 55))
glow = glow.filter(ImageFilter.GaussianBlur(120))
img = Image.alpha_composite(img, glow)
od = ImageDraw.Draw(overlay)

# 中央白色圆角面板
pad = 200
od.rounded_rectangle([pad, pad, S - pad, S - pad], radius=120, fill=(255, 255, 255, 242))

ACCENT = (115, 102, 232, 255)
ACCENT_SOFT = (115, 102, 232, 105)
SOFT2 = (160, 150, 245, 150)

y0 = 372
# 第一条（满进度）
od.rounded_rectangle([310, y0, 714, y0 + 44], radius=22, fill=ACCENT_SOFT)
od.rounded_rectangle([310, y0, 660, y0 + 44], radius=22, fill=ACCENT)

# 第二条
y1 = y0 + 104
od.rounded_rectangle([310, y1, 714, y1 + 44], radius=22, fill=ACCENT_SOFT)
od.rounded_rectangle([310, y1, 560, y1 + 44], radius=22, fill=SOFT2)

# 第三条
y2 = y1 + 104
od.rounded_rectangle([310, y2, 714, y2 + 44], radius=22, fill=ACCENT_SOFT)

# 顶部三个圆点（窗口控制感）
for i in range(3):
    cx = 340 + i * 52
    od.ellipse([cx - 12, 296 - 12, cx + 12, 296 + 12], fill=ACCENT_SOFT)

img = Image.alpha_composite(img, overlay)

# 边缘轻微内阴影（不要 alpha，iOS 图标要求无透明）
img = img.convert("RGB")
out = "/home/ubuntu/yao-console-ios/ios/YaoConsole/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.save(out, "PNG")
print("saved", out, os.path.getsize(out), img.size)
