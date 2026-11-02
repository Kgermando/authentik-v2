#!/usr/bin/env python3
"""Génère les icônes Windows/macOS/Linux à partir de assets/branding/icon_source.png."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "branding" / "icon_source.png"

MACOS = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WINDOWS_ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
LINUX_ICON = ROOT / "linux" / "runner" / "resources" / "app_icon.png"

MAC_SIZES = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}

ICO_SIZES = [16, 32, 48, 64, 128, 256]


def load_source() -> Image.Image:
    if not SOURCE.is_file():
        print(f"Fichier source introuvable : {SOURCE}", file=sys.stderr)
        sys.exit(1)
    img = Image.open(SOURCE).convert("RGBA")
    side = min(img.size)
    if img.size[0] != img.size[1]:
        left = (img.width - side) // 2
        top = (img.height - side) // 2
        img = img.crop((left, top, left + side, top + side))
    return img.resize((1024, 1024), Image.Resampling.LANCZOS)


def save_png(img: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = img.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(path, format="PNG", optimize=True)


def save_ico(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Pillow n'inclut qu'une frame 16px si append_images est mal utilisé — sizes sur 256px.
    master = img.resize((256, 256), Image.Resampling.LANCZOS)
    master.save(
        path,
        format="ICO",
        sizes=[(s, s) for s in ICO_SIZES],
    )


def main() -> None:
    base = load_source()
    for name, size in MAC_SIZES.items():
        save_png(base, MACOS / name, size)
        print(f"macOS  {name} ({size}px)")
    save_ico(base, WINDOWS_ICO)
    print(f"Windows {WINDOWS_ICO.name}")
    save_png(base, LINUX_ICON, 256)
    print(f"Linux  app_icon.png (256px)")
    print("Terminé.")


if __name__ == "__main__":
    main()
