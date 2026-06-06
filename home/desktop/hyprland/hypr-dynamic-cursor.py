"""Dynamic cursor theme switcher for Hyprland.

Switches between Bibata-Modern-Ice (light cursor) and Bibata-Modern-Classic
(dark cursor) based on the luminance of the pixel directly under the cursor.
Uses hysteresis to prevent flickering.
"""

import json
import logging
import subprocess
import sys
import time

CURSOR_SIZE = 32
THEME_DARK = "Bibata-Modern-Classic"
THEME_LIGHT = "Bibata-Modern-Ice"

LUMINANCE_HIGH = 0.60
LUMINANCE_LOW = 0.40
POLL_INTERVAL = 0.125

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("hypr-dynamic-cursor")


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"Command {cmd} failed (rc={result.returncode}): {result.stderr.strip()}"
        )
    return result.stdout


def run_bytes(cmd: list[str]) -> bytes:
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        stderr = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Command {cmd} failed (rc={result.returncode}): {stderr}")
    return result.stdout


def get_cursor_pos() -> tuple[int, int]:
    out = run(["hyprctl", "cursorpos", "-j"])
    data = json.loads(out)
    return data["x"], data["y"]


def sample_pixel_luminance(x: int, y: int) -> tuple[float, tuple[int, int, int]]:
    ppm = run_bytes(["grim", "-g", f"{x},{y} 1x1", "-t", "ppm", "-"])
    # PPM binary: "P6\n1 1\n255\n" + 3 bytes RGB
    header_end = 0
    newlines = 0
    for i, b in enumerate(ppm):
        if b == ord("\n"):
            newlines += 1
            if newlines == 3:
                header_end = i + 1
                break
    rgb = ppm[header_end : header_end + 3]
    if len(rgb) != 3:
        raise ValueError(f"Invalid PPM pixel payload length: {len(rgb)}")
    r, g, b = rgb[0], rgb[1], rgb[2]
    # Relative luminance (Rec. 709)
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0, (r, g, b)


def set_cursor_theme(theme: str) -> None:
    run(["hyprctl", "setcursor", theme, str(CURSOR_SIZE)])
    try:
        run(["dconf", "write", "/org/gnome/desktop/interface/cursor-theme", f"'{theme}'"])
    except RuntimeError:
        run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", theme])
    log.info("Switched to %s", theme)


def main() -> None:
    current_theme = THEME_LIGHT
    prev_x, prev_y = -1, -1

    # Set initial theme
    set_cursor_theme(current_theme)

    while True:
        try:
            x, y = get_cursor_pos()
            if x == prev_x and y == prev_y:
                time.sleep(POLL_INTERVAL)
                continue

            prev_x, prev_y = x, y
            luminance, (r, g, b) = sample_pixel_luminance(x, y)

            if current_theme == THEME_LIGHT and luminance >= LUMINANCE_HIGH:
                log.info("RGB=(%d,%d,%d) lum=%.3f -> dark cursor", r, g, b, luminance)
                set_cursor_theme(THEME_DARK)
                current_theme = THEME_DARK
            elif current_theme == THEME_DARK and luminance <= LUMINANCE_LOW:
                log.info("RGB=(%d,%d,%d) lum=%.3f -> light cursor", r, g, b, luminance)
                set_cursor_theme(THEME_LIGHT)
                current_theme = THEME_LIGHT

        except RuntimeError as exc:
            log.warning("Runtime error: %s", exc)
        except (KeyError, json.JSONDecodeError) as exc:
            log.warning("Parse error: %s", exc)
        except (IndexError, ValueError) as exc:
            log.warning("Pixel sampling error: %s", exc)

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
