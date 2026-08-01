#!/usr/bin/env python3
"""Generate platform app icons from the repository-native HydraBox geometry.

The checked-in SVG is the human-readable vector source.  This script mirrors
the same normalized coordinates to produce the PNG and ICO assets expected by
Flutter's platform projects.  Pillow is needed only when regenerating artwork.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
MASTER_SIZE = 2048
BACKGROUND = "#f6fafc"
MARK = "#0f5c7a"
FOREGROUND = "#ffffff"


def point(x: float, y: float, scale: float) -> tuple[float, float]:
    return x * scale, y * scale


def cubic(
    start: tuple[float, float],
    control_a: tuple[float, float],
    control_b: tuple[float, float],
    end: tuple[float, float],
    *,
    steps: int = 96,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for index in range(steps + 1):
        t = index / steps
        inverse = 1.0 - t
        points.append(
            (
                inverse**3 * start[0]
                + 3 * inverse**2 * t * control_a[0]
                + 3 * inverse * t**2 * control_b[0]
                + t**3 * end[0],
                inverse**3 * start[1]
                + 3 * inverse**2 * t * control_a[1]
                + 3 * inverse * t**2 * control_b[1]
                + t**3 * end[1],
            )
        )
    return points


def render_master() -> Image.Image:
    image = Image.new("RGB", (MASTER_SIZE, MASTER_SIZE), BACKGROUND)
    draw = ImageDraw.Draw(image)
    scale = MASTER_SIZE / 108.0

    draw.polygon(
        [
            point(54, 8, scale),
            point(90, 27, scale),
            point(90, 77, scale),
            point(54, 99, scale),
            point(18, 77, scale),
            point(18, 27, scale),
        ],
        fill=MARK,
    )

    width = round(7 * scale)
    def rounded_line(points: list[tuple[float, float]]) -> None:
        raster_points = [(round(x), round(y)) for x, y in points]
        draw.line(
            raster_points,
            fill=FOREGROUND,
            width=width,
            joint="curve",
        )
        radius = width / 2
        for center_x, center_y in (raster_points[0], raster_points[-1]):
            draw.ellipse(
                (
                    center_x - radius,
                    center_y - radius,
                    center_x + radius,
                    center_y + radius,
                ),
                fill=FOREGROUND,
            )

    rounded_line([point(54, 82, scale), point(54, 38, scale)])
    rounded_line(
        cubic(
            point(54, 59, scale),
            point(48, 51, scale),
            point(39, 49, scale),
            point(32, 36, scale),
        )
    )
    rounded_line(
        cubic(
            point(54, 59, scale),
            point(60, 51, scale),
            point(69, 49, scale),
            point(76, 36, scale),
        )
    )

    radius = 8 * scale
    for x, y in ((32, 27), (54, 24), (76, 27)):
        center_x, center_y = point(x, y, scale)
        draw.ellipse(
            (
                center_x - radius,
                center_y - radius,
                center_x + radius,
                center_y + radius,
            ),
            fill=FOREGROUND,
        )
    return image


def resized(master: Image.Image, size: int) -> Image.Image:
    return master.resize((size, size), Image.Resampling.LANCZOS)


def write_png(master: Image.Image, destination: Path, size: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    resized(master, size).save(destination, format="PNG", optimize=True)


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


def main() -> None:
    master = render_master()

    android_res = ROOT / "android" / "app" / "src" / "main" / "res"
    android_launcher_sizes = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    for density, pixels in android_launcher_sizes.items():
        write_png(
            master,
            android_res / f"mipmap-{density}" / "ic_launcher.png",
            pixels,
        )

    web = ROOT / "web"
    write_png(master, web / "favicon.png", 16)
    for size in (192, 512):
        write_png(master, web / "icons" / f"Icon-{size}.png", size)
        write_png(master, web / "icons" / f"Icon-maskable-{size}.png", size)

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
