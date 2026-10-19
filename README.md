# DateTag

Adds a subtle date tag to the bottom-right corner of your photos — like the date stamps on old film / point-and-shoot photos, but clean and modern.

Built for Fujifilm shooters (X100VI, X-T5, etc.) but works with any JPEG / PNG / TIFF / HEIC folder.

Two ways to run it, same look and same options:
1. **CLI** (recommended) — Python, runs on macOS and Linux
2. **Native Mac app** — SwiftUI, in `DateTag/`

![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-black) ![Python](https://img.shields.io/badge/Python-3.10%2B-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## What it does

- Point it at a folder — it finds all images inside (including subfolders)
- Reads the real capture date from EXIF (`DateTimeOriginal`), falling back to file date if there's no EXIF
- Draws the date in the bottom-right corner:
  - **Subtle by default** — small monospaced text, white at 90% opacity, soft blurred shadow so it reads on any background
  - Or go classic: **film orange**, like a '90s point-and-shoot
- Two output modes:
  - **Copy to new folder** (default, safe) — creates `<YourFolder>_dated/` next to the original, originals untouched
  - **In place** — overwrites the originals (with a 3-second abort window in the CLI, a confirm dialog in the app)
- Bakes in EXIF orientation correctly (portrait shots stay portrait), preserves your other EXIF, JPEG quality 92

## Date formats

| `--format` | Example |
|---|---|
| `dotted` (default) | `2026.10.18` |
| `slash` | `10/18/2026` |
| `film` | `13 2 '99` |
| `short` | `Oct 18, 2026` |
| `iso` | `2026-10-18` |

Styles (`--style`): `white` (default), `orange`, `black`, and `retro`.

**Retro** emulates how analogue cameras actually did it — a data back exposing the date *onto the film with light*:

- **Fixed size** — glyphs are always 3.8% of frame height, on every photo. No dynamic sizing.
- **Fixed position** — inset 9.5% of frame width from the right, 4.5% of frame height from the bottom (measured from a real 1999 print; data backs imprint well inside the edge, not in the corner).
- **Fixed light** — pale warm yellow dot-matrix (5×7), one colour, one intensity, a soft bloom pass under a sharp core (light scatter in film).
- **It's added light, not ink** — blended with screen math (`1-(1-photo)(1-light)`), so the stamp glows over dark asphalt and *disappears over bright sky or a white lane line*, because there's nothing left to expose there. No shadow, no halo-for-readability, no contrast adjustment — if it washes out, it washes out. That's the point.
- `--size` and `--opacity` **do not apply** to retro. A data back had no such knobs.

```bash
python3 datetag.py ~/Photos/Fuji --style retro --format film
# -> imprints e.g.  18 10 '26  exactly the same way on every frame
```

Note the `film` format has *no leading zeros* — `13 2 '99`, not `13 02 '99` — exactly like the cameras did it.

---

## CLI — quick start

Requires Python 3.10+ and Pillow. That's the only dependency.

```bash
git clone https://github.com/nkomirisetti/datetag.git
cd datetag
pip install -r requirements.txt
# optional, for HEIC: pip install pillow-heif

# Stamp a whole folder -> creates ~/Photos/Fuji_dated/
python3 datetag.py ~/Photos/Fuji

# The 1999 point-and-shoot look (dot-matrix, pale yellow)
python3 datetag.py ~/Photos/Fuji --style retro --format film

# Classic film look
python3 datetag.py ~/Photos/Fuji --style orange --format film

# Preview without writing anything
python3 datetag.py ~/Photos/Fuji --dry-run

# A single file, custom output folder
python3 datetag.py DSCF0001.jpg --out ./stamped

# Overwrite originals (careful)
python3 datetag.py ~/Photos/Fuji --in-place
```

Or install it as a command:

```bash
pip install .
datetag ~/Photos/Fuji --style orange
```

### All options

```
usage: datetag [-h] [--in-place] [--out OUT]
               [--format {dotted,slash,film,short,iso}]
               [--style {white,orange,black}] [--size SIZE]
               [--opacity OPACITY] [--quality QUALITY] [--font FONT]
               [--no-recursive] [--dry-run]
               path

  path                  Folder of photos, or a single image file
  --in-place            Overwrite originals (default: copy to <folder>_dated/)
  --out OUT             Output folder
  --format              Date format (default: dotted)
  --style               white / orange / black (default: white)
  --size                Text size, fraction of short side (default: 0.028)
  --opacity             0-1 (default: 0.9)
  --quality             JPEG quality (default: 92)
  --font                Path to a .ttf/.ttc — default is Menlo on Mac, DejaVu Mono on Linux
  --no-recursive        Don't descend into subfolders
  --dry-run             Show dates that would be stamped, write nothing
```

Verified working on Linux with synthetic Fujifilm-style JPEGs: EXIF date parsed correctly, tag pixels render in the bottom-right, and a portrait file stored sideways with EXIF orientation 6 comes out correctly rotated (e.g. 800×1200 → 1200×800).

RAF / other RAW files are skipped — shoot RAW+JPEG or export JPEGs first. HEIC works with the optional `pillow-heif` package.

---

## Mac app

Same engine, native SwiftUI interface with a live preview, sliders, and drag-and-drop.

Requires macOS 14+ and Xcode 15+.

```bash
open DateTag/DateTag.xcodeproj
```

Then hit Run (⌘R) in Xcode. No signing team needed for local use (if Xcode asks, set it to your personal team in Signing & Capabilities).

> First launch of a locally-built app: right-click → Open if macOS says "unidentified developer".

---

## How it works

**CLI (`datetag.py`)** — Pillow only:
- `ImageOps.exif_transpose` to bake orientation in, `img.getexif()` / `get_ifd(0x8769)` for `DateTimeOriginal` (36867)
- Tag is drawn on an RGBA overlay: shadow layer blurred with `GaussianBlur`, then the text layer, composited over the photo
- Font discovery: Menlo on macOS, DejaVu Sans Mono on Linux, `--font` to override
- In-place writes go to a temp file then swap, so the source is never truncated mid-write

**Mac app (`DateTag/DateTagger.swift`)** — SwiftUI + AppKit + ImageIO, no dependencies, same idea: `CGImageSourceCreateThumbnailAtIndex` with transform, bitmap context, `CGImageDestination` with the original EXIF carried over.

## Ideas / TODO

- [ ] Custom presets ("Film", "Minimal", "Wedding")
- [ ] RAW (RAF) support via embedded JPEG preview
- [ ] Filename-based date fallback (e.g. `IMG_20261018_...`)

Pull requests welcome.

## License

MIT — see [LICENSE](LICENSE).
