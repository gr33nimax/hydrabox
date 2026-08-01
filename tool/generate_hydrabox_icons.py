#!/usr/bin/env python3
"""Generate platform launcher icons from the canonical HydraBox logo.

The script does not redraw the mark. It only resizes the checked-in master PNG
and adds a white safety field for icon formats that apply their own mask.
Pillow is needed only when regenerating artwork.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
MASTER_ASSET = ROOT / "assets" / "branding" / "hydrabox-logo.png"


def resized(master: Image.Image, size: int, *, scale: float = 1.0) -> Image.Image:
    draw_size = round(size * scale)
    artwork = master.resize((draw_size, draw_size), Image.Resampling.LANCZOS)
    image = Image.new("RGB", (size, size), "white")
    offset = (size - draw_size) // 2
    image.paste(artwork, (offset, offset))
    return image


def write_png(
    master: Image.Image,
    destination: Path,
    size: int,
    *,
    scale: float = 1.0,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    resized(master, size, scale=scale).save(destination, format="PNG", optimize=True)


def asset_pixels(entry: dict[str, str]) -> int:
    logical_size = float(entry["size"].split("x", maxsplit=1)[0])
    scale = float(entry.get("scale", "1x").removesuffix("x"))
    return round(logical_size * scale)


def generate_asset_catalog(master: Image.Image, catalog: Path) -> None:
    manifest = json.loads((catalog / "Contents.json").read_text(encoding="utf-8"))
    sizes_by_name: dict[str, int] = {}
    for entry in manifest["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        pixels = asset_pixels(entry)
        previous = sizes_by_name.setdefault(filename, pixels)
        if previous != pixels:
            raise ValueError(f"conflicting dimensions for {catalog / filename}")
    for filename, pixels in sizes_by_name.items():
        write_png(master, catalog / filename, pixels)


def write_monochrome(master: Image.Image, destination: Path, size: int) -> None:
    source = master.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")
    alpha = [
        min(255, max(0, (green - max(red, blue)) * 4))
        for red, green, blue in source.getdata()
    ]
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    alpha_image = Image.new("L", (size, size))
    alpha_image.putdata(alpha)
    image.putalpha(alpha_image)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="PNG", optimize=True)


def main() -> None:
    master = Image.open(MASTER_ASSET).convert("RGB")

    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    for density, pixels in {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }.items():
        write_png(master, android_res / f"mipmap-{density}" / "ic_launcher.png", pixels)

    drawable = android_res / "drawable-nodpi"
    write_png(master, drawable / "hydrabox_launcher_foreground.png", 640)
    write_monochrome(master, drawable / "hydrabox_launcher_monochrome.png", 640)

    web = ROOT / "web"
    write_png(master, web / "favicon.png", 32)
    for size in (192, 512):
        write_png(master, web / "icons" / f"Icon-{size}.png", size)
        write_png(
            master,
            web / "icons" / f"Icon-maskable-{size}.png",
            size,
            scale=0.78,
        )

    generate_asset_catalog(
        master,
        ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset",
    )
    generate_asset_catalog(
        master,
        ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset",
    )

    windows_icon = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    resized(master, 256).save(
        windows_icon,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )


if __name__ == "__main__":
    main()
