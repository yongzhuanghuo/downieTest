"""视频工具：加水印 / 改 MD5 / 转 GIF（均为 ffmpeg 处理）。

文字水印用 Pillow 渲染成透明 PNG 再 overlay（本机 ffmpeg 精简版无 drawtext 滤镜）。
支持粗体/斜体/阴影/描边/平铺、旋转、多字体、自定义颜色。
"""
import hashlib
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from .. import config

# 中文字体列表（font_id 对应索引，探测存在的）
_FONTS = [
    ("黑体 Arial Unicode", "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"),
    ("冬青黑体 Hiragino Sans GB", "/System/Library/Fonts/Hiragino Sans GB.ttc"),
    ("华文黑体细 STHeiti Light", "/System/Library/Fonts/STHeiti Light.ttc"),
    ("华文黑体粗 STHeiti Medium", "/System/Library/Fonts/STHeiti Medium.ttc"),
]


def _run(cmd: list) -> None:
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def _video_size(video_path: Path) -> tuple[int, int]:
    from .delogo import get_video_info

    w, h, _ = get_video_info(video_path)
    return w, h


def list_fonts() -> list[dict]:
    """返回可用的字体列表。"""
    return [{"id": i, "name": name} for i, (name, path) in enumerate(_FONTS) if Path(path).exists()]


def _get_font(font_id: int) -> str:
    if 0 <= font_id < len(_FONTS) and Path(_FONTS[font_id][1]).exists():
        return _FONTS[font_id][1]
    return _FONTS[0][1]


def _hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _skew(img: Image.Image, factor: float = 0.2) -> Image.Image:
    """水平切变模拟斜体。"""
    w, h = img.size
    xshift = int(h * abs(factor))
    new_w = w + xshift
    offset = 0 if factor >= 0 else xshift
    return img.transform((new_w, h), Image.AFFINE, (1, factor, offset, 0, 1, 0), resample=Image.BICUBIC)


def _tile(single: Image.Image, canvas_w: int, canvas_h: int, tile_angle: float = -30) -> Image.Image:
    """斜向平铺：文字倾斜 tile_angle，网格铺满（防盗水印）。"""
    single = single.rotate(tile_angle, expand=True, resample=Image.BICUBIC)
    w, h = single.size
    gap_x = max(30, int(w * 1.4))
    gap_y = max(30, int(h * 1.8))
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    y = 0
    while y < canvas_h:
        x = 0
        while x < canvas_w:
            if x + w <= canvas_w and y + h <= canvas_h:
                canvas.alpha_composite(single, (x, y))
            x += gap_x
        y += gap_y
    return canvas


def _text_to_image(
    text: str,
    fontsize: int,
    color_hex: str,
    opacity: float,
    font_path: str,
    bold: bool,
    italic: bool,
    shadow: bool,
    outline: bool,
    angle: float,
    out_path: Path,
    tile: bool = False,
    canvas_w: int = 0,
    canvas_h: int = 0,
) -> None:
    """用 Pillow 把文字渲染成透明 PNG，支持样式/旋转/平铺。"""
    font = ImageFont.truetype(font_path, fontsize)
    r, g, b = _hex_to_rgb(color_hex)
    a = int(max(0.0, min(opacity, 1.0)) * 255)
    lines = text.split("\n")

    tmp = Image.new("RGBA", (1, 1))
    d = ImageDraw.Draw(tmp)
    spacing = int(fontsize * 0.25)
    max_w = 0
    heights = []
    for line in lines:
        bbox = d.textbbox((0, 0), line, font=font)
        max_w = max(max_w, bbox[2] - bbox[0])
        heights.append(bbox[3] - bbox[1])

    stroke_w = int(fontsize * 0.08) if outline else 0
    shadow_off = int(fontsize * 0.12) if shadow else 0
    pad = stroke_w + shadow_off + 12
    img_w = max_w + pad * 2 + shadow_off
    total_h = sum(heights) + spacing * (len(lines) - 1) + pad * 2 + shadow_off

    img = Image.new("RGBA", (img_w, total_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    y = pad
    for line, h in zip(lines, heights):
        if shadow:
            draw.text((pad + shadow_off, y + shadow_off), line, font=font, fill=(0, 0, 0, a // 2))
        if outline:
            draw.text((pad, y), line, font=font, fill=(r, g, b, a),
                      stroke_width=stroke_w, stroke_fill=(0, 0, 0, a))
        elif bold:
            draw.text((pad, y), line, font=font, fill=(r, g, b, a),
                      stroke_width=max(1, fontsize // 20), stroke_fill=(r, g, b, a))
        else:
            draw.text((pad, y), line, font=font, fill=(r, g, b, a))
        y += h + spacing

    if italic:
        img = _skew(img, 0.25)
    if tile and canvas_w > 0 and canvas_h > 0:
        # 平铺：文字斜向（默认 -30°），网格铺满整页
        tile_angle = angle if angle != 0 else -30
        img = _tile(img, canvas_w, canvas_h, tile_angle)
    elif angle:
        img = img.rotate(angle, expand=True, resample=Image.BICUBIC)

    img.save(out_path)


def _preprocess_image(image_path: Path, target_width: int, angle: float, opacity: float, out_path: Path) -> None:
    """图片水印预处理：缩放到目标宽度 + 旋转 + 透明度。"""
    img = Image.open(image_path).convert("RGBA")
    w, h = img.size
    new_w = max(1, int(target_width))
    new_h = max(1, int(h * new_w / w))
    img = img.resize((new_w, new_h), Image.LANCZOS)
    if angle:
        img = img.rotate(angle, expand=True, resample=Image.BICUBIC)
    if opacity < 1.0:
        r, g, b, a = img.split()
        a = a.point(lambda x: int(x * opacity))
        img = Image.merge("RGBA", (r, g, b, a))
    img.save(out_path)


def add_watermark(video_path: Path, output_path: Path, elements: list) -> Path:
    """给视频加多个水印元素（文字/图片），一次 ffmpeg 串多个 overlay。"""
    width, height = _video_size(video_path)
    if not elements:
        raise ValueError("水印元素不能为空")

    images: list[Path] = []
    positions: list[tuple[int, int]] = []

    for el in elements:
        if el.type == "text":
            key = f"{el.text}{el.size}{el.color}{el.opacity}{el.font_id}{el.bold}{el.italic}{el.shadow}{el.outline}{el.tile}{el.angle}"
            tmp = config.TEMP_DIR / f"wm_{hashlib.md5(key.encode()).hexdigest()[:12]}.png"
            _text_to_image(el.text, el.size, el.color, el.opacity, _get_font(el.font_id),
                           el.bold, el.italic, el.shadow, el.outline, el.angle, tmp,
                           tile=el.tile, canvas_w=width, canvas_h=height)
            px, py = (0, 0) if el.tile else (int(el.x * width), int(el.y * height))
        elif el.type == "image":
            if not el.image_path:
                continue
            key = f"img_{el.image_path}{el.image_scale}{el.angle}{el.opacity}"
            tmp = config.TEMP_DIR / f"wmimg_{hashlib.md5(key.encode()).hexdigest()[:12]}.png"
            _preprocess_image(Path(el.image_path), width * el.image_scale * 0.4, el.angle, el.opacity, tmp)
            px, py = int(el.x * width), int(el.y * height)
        else:
            continue
        images.append(tmp)
        positions.append((px, py))

    if not images:
        raise ValueError("没有有效水印元素")

    cmd = ["ffmpeg", "-y", "-i", str(video_path)]
    for img in images:
        cmd += ["-i", str(img)]

    if len(images) == 1:
        fc = f"[0:v][1:v]overlay={positions[0][0]}:{positions[0][1]}[out]"
    else:
        parts = []
        prev = "[0:v]"
        for i, (px, py) in enumerate(positions):
            out_label = "[out]" if i == len(positions) - 1 else f"[w{i}]"
            parts.append(f"{prev}[{i + 1}:v]overlay={px}:{py}{out_label}")
            prev = out_label
        fc = ";".join(parts)

    cmd += ["-filter_complex", fc, "-map", "[out]", "-map", "0:a?", "-c:a", "copy", str(output_path)]
    _run(cmd)
    return output_path


def change_md5(video_path: Path, output_path: Path) -> tuple[str, str]:
    """remux 重新封装改 MD5（无损），返回 (原 MD5, 新 MD5)。"""
    before = _md5(video_path)
    _run(["ffmpeg", "-y", "-i", str(video_path), "-c", "copy", str(output_path)])
    after = _md5(output_path)
    return before, after


def to_gif(
    video_path: Path,
    output_path: Path,
    start: float,
    end: float,
    fps: int = 10,
    width: int = 480,
) -> Path:
    """视频片段转 GIF。"""
    vf = f"fps={fps},scale={width}:-1"
    cmd = [
        "ffmpeg", "-y", "-ss", str(start), "-to", str(end), "-i", str(video_path),
        "-vf", vf, "-loop", "0", str(output_path),
    ]
    _run(cmd)
    return output_path


def _md5(path: Path) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()
