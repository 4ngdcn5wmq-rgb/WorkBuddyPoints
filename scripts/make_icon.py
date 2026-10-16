#!/usr/bin/env python3
"""生成 App 图标：WorkBuddyPoints/Assets.xcassets/AppIcon.appiconset/icon_1024.png

设计：红 → 金 纵向渐变底（红金 = 收益）+ 白色积分币 + 币内红色「积」字 + 下方「+100/天」。
运行：python3 scripts/make_icon.py
依赖：Pillow
"""
from __future__ import annotations

import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:  # pragma: no cover
    sys.exit("缺少 Pillow，请先执行：python3 -m pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "WorkBuddyPoints", "Assets.xcassets", "AppIcon.appiconset")
OUT_PATH = os.path.join(OUT_DIR, "icon_1024.png")

SIZE = 1024

# 中文字体候选（macOS / Linux / Windows 三平台）
FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "C:/Windows/Fonts/msyhbd.ttc",
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/simhei.ttf",
]


def find_font() -> str:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return path
    raise SystemExit("未找到可用中文字体")


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel((0, y), (
            int(lerp(top[0], bottom[0], t)),
            int(lerp(top[1], bottom[1], t)),
            int(lerp(top[2], bottom[2], t)),
        ))
    return grad.resize((size, size))


def main() -> None:
    font_path = find_font()
    os.makedirs(OUT_DIR, exist_ok=True)

    # 1) 背景：红 → 金
    background = vertical_gradient(SIZE, (232, 39, 45), (255, 152, 0)).convert("RGBA")

    # 2) 顶部高光，避免纯平
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [-SIZE * 0.35, -SIZE * 0.72, SIZE * 0.72, SIZE * 0.30],
        fill=(255, 255, 255, 46),
    )
    background = Image.alpha_composite(background, glow.filter(ImageFilter.GaussianBlur(60)))

    draw = ImageDraw.Draw(background)
    cx, cy = SIZE // 2, int(SIZE * 0.445)
    r = int(SIZE * 0.305)

    # 3) 币的柔光投影
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        [cx - r, cy - r + 34, cx + r, cy + r + 34], fill=(120, 20, 10, 110)
    )
    background = Image.alpha_composite(background, shadow.filter(ImageFilter.GaussianBlur(34)))
    draw = ImageDraw.Draw(background)

    # 4) 白色积分币 + 内圈
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))
    inner = int(r * 0.80)
    draw.ellipse(
        [cx - inner, cy - inner, cx + inner, cy + inner],
        outline=(255, 205, 160, 255), width=int(SIZE * 0.011),
    )

    # 5) 币内红色「积」字
    font = ImageFont.truetype(font_path, int(r * 1.22))
    box = draw.textbbox((0, 0), "积", font=font)
    draw.text(
        (cx - (box[2] - box[0]) / 2 - box[0], cy - (box[3] - box[1]) / 2 - box[1]),
        "积", font=font, fill=(226, 32, 40, 255),
    )

    # 6) 底部说明文字
    font_small = ImageFont.truetype(font_path, int(SIZE * 0.088))
    label = "+100 / 天"
    box = draw.textbbox((0, 0), label, font=font_small)
    draw.text(
        (cx - (box[2] - box[0]) / 2 - box[0], int(SIZE * 0.80)),
        label, font=font_small, fill=(255, 255, 255, 250),
    )

    background.convert("RGB").save(OUT_PATH, "PNG")
    print(f"已生成图标：{OUT_PATH} ({SIZE}x{SIZE})，字体：{font_path}")


if __name__ == "__main__":
    main()
