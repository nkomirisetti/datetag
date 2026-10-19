#!/usr/bin/env python3
"""
DateTag CLI — adds a subtle date tag to the bottom-right corner of photos.

Cross-platform (macOS + Linux). Reads the capture date from EXIF
DateTimeOriginal, falling back to the file's date. Works on a folder
(recursive by default) or a single file.

Examples:
    python3 datetag.py ~/Photos/Fuji
    python3 datetag.py ~/Photos/Fuji --style retro --format film
    python3 datetag.py ~/Photos/Fuji --style orange --format film
    python3 datetag.py ~/Photos/Fuji --in-place
    python3 datetag.py IMG_0001.jpg --out ./stamped

Only dependency: Pillow  (pip install Pillow)
Optional HEIC support:    pip install pillow-heif
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required:  pip install Pillow")

# Optional HEIC/HEIF support (Fujifilm can shoot HEIF) — used if installed.
try:
    from pillow_heif import register_heif_opener

    register_heif_opener()
    HEIC_OK = True
except Exception:
    HEIC_OK = False

SUPPORTED = {".jpg", ".jpeg", ".png", ".tiff", ".tif", ".heic", ".heif", ".webp"}

# --------------------------------------------------------------------------
# Date handling
# --------------------------------------------------------------------------

FORMATS = {
    "dotted": "%Y.%m.%d",      # 2026.10.18  (default, subtle/modern)
    "slash": "%m/%d/%Y",       # 10/18/2026
    "film": "film",            # 13 2 '99 — handled below (no leading zeros)
    "short": "%b %d, %Y",      # Oct 18, 2026 — %d gives zero-padded; fixed below
    "iso": "%Y-%m-%d",         # 2026-10-18
}


def format_date(dt: datetime, style: str) -> str:
    if style == "film":
        # Exactly like the reference photo: "13 2 '99"
        # Day and month with NO leading zero, then ' + 2-digit year.
        return f"{dt.day} {dt.month} '{dt.year % 100:02d}"
    if style == "short":
        # "Oct 18, 2026" without a leading zero on the day, platform-safe.
        return f"{dt.strftime('%b')} {dt.day}, {dt.year}"
    return dt.strftime(FORMATS[style])


def capture_date(path: Path, img: Image.Image) -> datetime:
    """EXIF DateTimeOriginal -> DateTimeDigitized -> TIFF DateTime -> file mtime."""
    try:
        exif = img.getexif()
        if exif:
            candidates: list[str] = []
            # EXIF IFD: 36867 DateTimeOriginal, 36868 DateTimeDigitized
            try:
                exif_ifd = exif.get_ifd(0x8769)
                for tag in (36867, 36868):
                    if exif_ifd.get(tag):
                        candidates.append(str(exif_ifd[tag]))
            except Exception:
                pass
            # IFD0: 306 DateTime
            if exif.get(306):
                candidates.append(str(exif[306]))
            # Some writers flatten the tags onto the base IFD
            for tag in (36867, 36868):
                if exif.get(tag):
                    candidates.append(str(exif[tag]))

            for raw in candidates:
                raw = raw.strip().strip("\x00")
                for fmt in ("%Y:%m:%d %H:%M:%S", "%Y:%m:%d %H:%M", "%Y-%m-%d %H:%M:%S"):
                    try:
                        return datetime.strptime(raw, fmt)
                    except ValueError:
                        continue
    except Exception:
        pass
    return datetime.fromtimestamp(path.stat().st_mtime)


# --------------------------------------------------------------------------
# Font discovery — a clean monospaced face on each OS, no bundled files
# --------------------------------------------------------------------------

FONT_CANDIDATES = [
    # macOS
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Supplemental/Courier New.ttf",
    "/Library/Fonts/Courier New.ttf",
    # Linux
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
    "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
    # Windows (bonus)
    "C:\\Windows\\Fonts\\consola.ttf",
]


def load_font(size: int, font_path: str | None = None) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [font_path] if font_path else FONT_CANDIDATES
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            try:
                return ImageFont.truetype(candidate, size=size)
            except Exception:
                continue
    # Pillow >= 9.2 can scale its built-in font when given a size.
    try:
        return ImageFont.load_default(size=size)  # type: ignore[arg-type]
    except TypeError:
        return ImageFont.load_default()


# --------------------------------------------------------------------------
# Retro dot-matrix rendering — the '90s point-and-shoot imprint look.
# In the reference photo ("13 2 '99", Feb 13 1999) each character is made
# of pale-yellow dots on a 5x7 grid, widely spaced, no shadow, slightly
# soft — like it was burned into the film by an LED in the camera back.
# --------------------------------------------------------------------------

# 5 columns x 7 rows per glyph, '1' = dot on.
DOT_MATRIX: dict[str, tuple[str, ...]] = {
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("01110", "10001", "00001", "00110", "00001", "10001", "01110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
    "'": ("00100", "00100", "01000", "00000", "00000", "00000", "00000"),
    ".": ("00000", "00000", "00000", "00000", "00000", "01100", "01100"),
    ",": ("00000", "00000", "00000", "00000", "00100", "00100", "01000"),
    "-": ("00000", "00000", "00000", "01110", "00000", "00000", "00000"),
    "/": ("00001", "00010", "00010", "00100", "01000", "01000", "10000"),
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11100", "10010", "10001", "10001", "10001", "10010", "11100"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("01110", "00100", "00100", "00100", "00100", "00100", "01110"),
    "J": ("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "10101", "01010"),
    "X": ("10001", "01010", "00100", "00100", "00100", "01010", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
}

# How many grid units each character advances the pen.
# Spaces advance extra — in the reference the groups are far apart.
def _char_units(ch: str) -> int:
    if ch == " ":
        return 5
    if ch == "'":
        return 4
    return 7  # 5 wide + 2 tracking


def retro_text_size(text: str, pitch: float) -> tuple[float, float]:
    units = sum(_char_units(c) for c in text.upper()) - 2  # no trailing tracking
    return units * pitch, 7 * pitch


# ---------------------------------------------------------------------------
# The analogue spec — FIXED, like a real data back. Nothing here adapts to
# the photo: same physical imprint size relative to the frame, same inset
# from the frame edges, same light colour and intensity on every shot.
# That's why real stamps glow on dark asphalt and vanish on bright sky.
#
# Geometry measured from the 1999 reference photo (dot-cloud + bbox
# analysis of "13 2 '99" on the 1179x780 frame: stamp width 182-201px for
# 47 dot-units -> pitch ~4.0-4.3px -> glyph height ~28-30px):
#   glyph height  ~3.8% of frame height
#   right inset   ~9.5% of frame width (data backs imprint well inside the edge)
#   bottom inset  ~4.5% of frame height
# ---------------------------------------------------------------------------
RETRO_GLYPH_H = 0.038   # fraction of frame height
RETRO_RIGHT = 0.095     # fraction of frame width
RETRO_BOTTOM = 0.045    # fraction of frame height
RETRO_LIGHT = (243, 240, 125)  # imprint lamp colour, calibrated so dot cores on the
#                                 reference asphalt (87,107,129) render ~(186,195,170),
#                                 matching the reference's measured (183,195,166). The old
#                                 (255,233,168) @ core .92 rendered (240,232,210) — too pale/white.
RETRO_CORE = 0.58       # fixed exposure intensity of a dot's core
RETRO_BLOOM = 0.25      # fixed intensity of the soft halo (light scatter in film)


def _screen(base: Image.Image, light_layer: Image.Image) -> Image.Image:
    """Screen blend: result = 1 - (1-base)(1-light). This is adding light —
    black stays black where there's no imprint, white stays white (the
    imprint adds nothing visible there), exactly like exposing film."""
    from PIL import ImageChops

    return ImageChops.screen(base.convert("RGB"), light_layer.convert("RGB")).convert("RGBA")


def draw_retro_text(base: Image.Image, text: str) -> Image.Image:
    """Emulate a data-back imprint: fixed-size dot-matrix characters exposed
    onto the 'film' with light. No size, opacity or contrast adjustments —
    the --size/--opacity flags do not apply to this style."""
    width, height = base.size

    glyph_height = height * RETRO_GLYPH_H
    pitch = glyph_height / 7.0
    dot_radius = pitch * 0.34

    text_w, text_h = retro_text_size(text, pitch)
    origin_x = width - width * RETRO_RIGHT - text_w
    origin_y = height - height * RETRO_BOTTOM - text_h

    # Dot mask (white dots on black), at the fixed geometry.
    mask = Image.new("L", base.size, 0)
    draw = ImageDraw.Draw(mask)
    cursor = origin_x
    for ch in text.upper():
        glyph = DOT_MATRIX.get(ch)
        if glyph is not None:
            for row_i, row in enumerate(glyph):
                for col_i, bit in enumerate(row):
                    if bit == "1":
                        cx = cursor + col_i * pitch + pitch / 2
                        cy = origin_y + row_i * pitch + pitch / 2
                        draw.ellipse(
                            [cx - dot_radius, cy - dot_radius, cx + dot_radius, cy + dot_radius],
                            fill=255,
                        )
        cursor += _char_units(ch) * pitch

    # Build the 'light' the imprint adds: a soft bloom pass (scatter) under
    # a sharper core pass, both in the lamp's fixed colour at fixed levels.
    light = Image.new("RGB", base.size, (0, 0, 0))
    bloom_mask = mask.filter(ImageFilter.GaussianBlur(radius=max(1.0, pitch * 0.35)))
    core_mask = mask.filter(ImageFilter.GaussianBlur(radius=max(0.6, pitch * 0.10)))
    for m, level in ((bloom_mask, RETRO_BLOOM), (core_mask, RETRO_CORE)):
        tint = Image.new("RGB", base.size, tuple(int(c * level) for c in RETRO_LIGHT))
        light = _apply_light(light, tint, m)
    return _screen(base, light)


def _apply_light(base_light: Image.Image, tint: Image.Image, mask: Image.Image) -> Image.Image:
    """Screen `tint` into the accumulated light, scaled by `mask` strength:
    out = 1-(1-a)(1-b*mask)."""
    from PIL import ImageChops

    masked_tint = ImageChops.multiply(tint, mask.convert("RGB"))
    return ImageChops.screen(base_light, masked_tint)


# --------------------------------------------------------------------------
# Stamping
# --------------------------------------------------------------------------

STYLES = {
    "white": (255, 255, 255),
    "orange": (255, 158, 38),   # classic film-stamp orange
    "black": (20, 20, 20),
    "retro": (221, 227, 182),   # pale dot-matrix yellow, see draw_retro_text
}


def stamp_image(input_path: Path, output_path: Path, *, fmt: str, style: str,
                rel_size: float, opacity: float, quality: int,
                font_path: str | None = None) -> tuple[datetime, str]:
    with Image.open(input_path) as raw:
        raw.load()
        date = capture_date(input_path, raw)
        date_str = format_date(date, fmt)

        # Bake EXIF orientation into the pixels (portrait Fuji shots!)
        img = ImageOps.exif_transpose(raw)

        # Remember metadata we want to carry over
        icc = img.info.get("icc_profile")
        try:
            exif = img.getexif()
            if 274 in exif:  # Orientation — now baked in, so reset to 1
                exif[274] = 1
            exif_bytes = exif.tobytes() if len(exif) else None
        except Exception:
            exif_bytes = None

        base = img.convert("RGBA")
        width, height = base.size
        short_side = min(width, height)

        if style == "retro":
            # Analogue data-back imprint: fixed geometry and fixed light.
            # --size / --opacity intentionally do not apply here.
            base = draw_retro_text(base, date_str)
        else:
            font_size = max(11, int(short_side * rel_size))
            padding = int(short_side * 0.025)
            font = load_font(font_size, font_path)

            # Measure
            probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
            bbox = probe.textbbox((0, 0), date_str, font=font)
            text_w, text_h = bbox[2] - bbox[0], bbox[3] - bbox[1]
            x = width - padding - text_w - bbox[0]
            y = height - padding - text_h - bbox[1]

            # Soft shadow on its own layer, blurred, then the text on top
            shadow_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
            shadow_draw = ImageDraw.Draw(shadow_layer)
            shadow_color = (255, 255, 255, 115) if style == "black" else (0, 0, 0, 115)
            shadow_draw.text((x, y + max(1, font_size // 24)), date_str, font=font, fill=shadow_color)
            shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=max(1, font_size * 0.06)))
            base = Image.alpha_composite(base, shadow_layer)

            text_layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
            text_draw = ImageDraw.Draw(text_layer)
            r, g, b = STYLES[style]
            text_draw.text((x, y), date_str, font=font, fill=(r, g, b, int(255 * opacity)))
            base = Image.alpha_composite(base, text_layer)

        output_path.parent.mkdir(parents=True, exist_ok=True)

        ext = output_path.suffix.lower()
        save_kwargs: dict = {}
        if ext in (".jpg", ".jpeg"):
            out = base.convert("RGB")
            save_kwargs.update(quality=quality, subsampling=1)
            if exif_bytes:
                save_kwargs["exif"] = exif_bytes
            if icc:
                save_kwargs["icc_profile"] = icc
        elif ext == ".png":
            out = base
            if exif_bytes:
                save_kwargs["exif"] = exif_bytes
        elif ext in (".tiff", ".tif"):
            out = base.convert("RGB")
            if exif_bytes:
                save_kwargs["exif"] = exif_bytes
        elif ext in (".heic", ".heif"):
            if not HEIC_OK:
                raise RuntimeError("HEIC needs: pip install pillow-heif")
            out = base.convert("RGB")
            if exif_bytes:
                save_kwargs["exif"] = exif_bytes
        else:  # webp etc.
            out = base
            if exif_bytes:
                save_kwargs["exif"] = exif_bytes

        out.save(output_path, **save_kwargs)
        return date, date_str


# --------------------------------------------------------------------------
# File collection / output mapping
# --------------------------------------------------------------------------

def collect(target: Path, recursive: bool) -> list[Path]:
    if target.is_file():
        return [target] if target.suffix.lower() in SUPPORTED else []
    pattern = "**/*" if recursive else "*"
    return sorted(
        p for p in target.glob(pattern)
        if p.is_file() and p.suffix.lower() in SUPPORTED and not p.name.startswith(".")
    )


def output_for(src: Path, target: Path, out_dir: Path | None, in_place: bool) -> Path:
    if in_place:
        return src
    assert out_dir is not None
    if target.is_file():
        return out_dir / src.name
    return out_dir / src.relative_to(target)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="datetag",
        description="Add a subtle date tag to the bottom-right corner of your photos (from EXIF).",
    )
    ap.add_argument("path", type=Path, help="Folder of photos, or a single image file")
    ap.add_argument("--in-place", action="store_true",
                    help="Overwrite originals in place (default: copy to a new folder)")
    ap.add_argument("--out", type=Path, default=None,
                    help="Output folder (default: '<folder>_dated' next to the source)")
    ap.add_argument("--format", choices=list(FORMATS), default="dotted",
                    help="Date format (default: dotted, e.g. 2026.10.18)")
    ap.add_argument("--style", choices=list(STYLES), default="white",
                    help="Tag style: white (subtle, default), orange, black, or retro "
                         "(analogue data-back imprint: fixed size/position, exposed with light, "
                         "dot-matrix — pair with --format film; --size/--opacity don't apply to retro)")
    ap.add_argument("--size", type=float, default=0.028,
                    help="Text size as a fraction of the image's short side (default: 0.028)")
    ap.add_argument("--opacity", type=float, default=0.9,
                    help="Text opacity 0-1 (default: 0.9)")
    ap.add_argument("--quality", type=int, default=92,
                    help="JPEG quality (default: 92)")
    ap.add_argument("--font", default=None, help="Path to a .ttf/.ttc font (default: Menlo on Mac, DejaVu Mono on Linux)")
    ap.add_argument("--no-recursive", action="store_true", help="Don't descend into subfolders")
    ap.add_argument("--dry-run", action="store_true", help="Show what would be stamped, write nothing")
    args = ap.parse_args(argv)

    target: Path = args.path.expanduser()
    if not target.exists():
        print(f"error: no such file or folder: {target}", file=sys.stderr)
        return 2
    if not (0 < args.opacity <= 1):
        print("error: --opacity must be between 0 and 1", file=sys.stderr)
        return 2
    if not (0.005 <= args.size <= 0.15):
        print("error: --size should be roughly 0.01-0.08 (fraction of the short side)", file=sys.stderr)
        return 2

    files = collect(target, recursive=not args.no_recursive)
    if not files:
        print(f"No supported images found in {target} (JPG, PNG, TIFF, HEIC, WebP).")
        return 1

    if args.in_place:
        out_dir = None
    elif args.out:
        out_dir = args.out.expanduser()
    elif target.is_file():
        out_dir = target.parent / f"{target.stem}_dated"
    else:
        out_dir = target.parent / f"{target.name}_dated"

    if args.in_place and not args.dry_run:
        print(f"⚠  In-place: overwriting {len(files)} original(s). Ctrl-C in 3s to abort…", end="", flush=True)
        try:
            import time; time.sleep(3)
        except KeyboardInterrupt:
            print("\naborted")
            return 130
        print()

    print(f"{'Would stamp' if args.dry_run else 'Stamping'} {len(files)} image(s)"
          + (f" → {out_dir}" if out_dir else " in place"))

    ok = failed = 0
    for src in files:
        dst = output_for(src, target, out_dir, args.in_place)
        if args.dry_run:
            try:
                with Image.open(src) as probe:
                    date_str = format_date(capture_date(src, probe), args.format)
                print(f"  – {src.name} → {date_str}")
                ok += 1
            except Exception as e:
                print(f"  ✗ {src.name} — {e}")
                failed += 1
            continue

        try:
            # In-place: stamp via a temp file, then swap — never truncate the source.
            effective_dst = dst
            tmp_path: Path | None = None
            if args.in_place:
                tmp_path = src.with_name(f".datetag-tmp-{src.name}")
                effective_dst = tmp_path
            elif dst.exists():
                dst.unlink()

            _, date_str = stamp_image(
                src, effective_dst, fmt=args.format, style=args.style,
                rel_size=args.size, opacity=args.opacity,
                quality=args.quality, font_path=args.font,
            )
            if tmp_path is not None:
                tmp_path.replace(src)
            print(f"  ✓ {src.name} → {date_str}")
            ok += 1
        except Exception as e:
            print(f"  ✗ {src.name} — {e}")
            failed += 1

    print(f"Done. {ok} succeeded, {failed} failed.")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
