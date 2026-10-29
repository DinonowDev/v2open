#!/usr/bin/env python3
"""Regenerate docs/screenshots/download-cta.png and download-cta-fa.png for README banners."""
from __future__ import annotations

from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError as exc:
    raise SystemExit(
        "Install Pillow first: python3 -m venv .venv-cta && .venv-cta/bin/pip install Pillow"
    ) from exc

ROOT = Path(__file__).resolve().parents[1]
SHOT = ROOT / "docs/screenshots/home.png"
OUT_EN = ROOT / "docs/screenshots/download-cta.png"
OUT_FA = ROOT / "docs/screenshots/download-cta-fa.png"
FONT = Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")
W, H = 920, 340


def _rounded_rect(draw: ImageDraw.ImageDraw, xy: tuple, radius: int, fill: str) -> None:
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def _make_banner(
    out_path: Path,
    *,
    subtitle: str,
    button: str,
    footer: str,
    rtl: bool,
) -> None:
    img = Image.new("RGB", (W, H), "#0a1628")
    draw = ImageDraw.Draw(img)

    accents = [(820, 70, 100, "#06b6d4", 22)] if rtl else [(820, 70, 100, "#06b6d4", 22)]
    for cx, cy, r, color, alpha in accents:
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        ld.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)
        layer.putalpha(alpha)
        img = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
        draw = ImageDraw.Draw(img)

    preview = Image.open(SHOT).convert("RGB")
    pw, ph = 200, 320
    preview = preview.resize((pw, ph), Image.Resampling.LANCZOS)
    frame_x, frame_y = 48, (H - ph) // 2
    frame = Image.new("RGBA", (pw + 16, ph + 16), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle((0, 0, pw + 15, ph + 15), radius=28, fill="#1e293b", outline="#334155", width=3)
    frame.paste(preview, (8, 8))
    img.paste(frame, (frame_x, frame_y), frame)

    f_title = ImageFont.truetype(str(FONT), 42)
    f_sub = ImageFont.truetype(str(FONT), 18)
    f_btn = ImageFont.truetype(str(FONT), 22)
    f_foot = ImageFont.truetype(str(FONT), 14)

    tx = W - 56 if rtl else 280
    anchor = "ra" if rtl else "la"
    draw.text((tx, 52), "V2OPEN", font=f_title, fill="#f1f5f9", anchor=anchor)
    draw.text((tx, 108), subtitle, font=f_sub, fill="#94a3b8", anchor=anchor)

    bbox = draw.textbbox((0, 0), button, font=f_btn)
    bw = bbox[2] - bbox[0] + 64
    bh = 56
    bx = tx - bw if rtl else 280
    by = 150
    _rounded_rect(draw, (bx, by, bx + bw, by + bh), 28, "#0891b2")
    draw.text((bx + bw // 2, by + bh // 2), button, font=f_btn, fill="#ffffff", anchor="mm")

    if rtl:
        ax0, ax1 = bx - 28, bx - 12
    else:
        ax0, ax1 = bx + bw + 12, bx + bw + 28
    draw.polygon([(ax0, by + 20), (ax1, by + 28), (ax0, by + 36)], fill="#22d3ee")

    draw.text((tx, H - 44), footer, font=f_foot, fill="#94a3b8", anchor=anchor)
    img.save(out_path, "PNG", optimize=True)
    print(f"wrote {out_path.relative_to(ROOT)} ({W}x{H})")


def main() -> None:
    if not SHOT.is_file():
        raise SystemExit(f"missing screenshot: {SHOT}")
    if not FONT.is_file():
        raise SystemExit(f"missing font: {FONT}")

    _make_banner(
        OUT_EN,
        subtitle="Local macOS VPN / proxy client",
        button="Download for macOS",
        footer="Apple Silicon (arm64) · Free & open source · GitHub Releases",
        rtl=False,
    )
    _make_banner(
        OUT_FA,
        subtitle="کلاینت VPN / پروکسی برای macOS",
        button="دانلود برای macOS",
        footer="Apple Silicon · رایگان و متن‌باز · GitHub Releases",
        rtl=True,
    )


if __name__ == "__main__":
    main()
