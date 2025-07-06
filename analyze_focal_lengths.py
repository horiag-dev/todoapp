#!/usr/bin/env python3
"""
Build focal-length stats with camera & native-mm columns.

Outputs
  • focal_length_histogram.csv   – 35-mm-eq histogram
  • camera_focal_usage.csv       – camera, native-mm, 35-mm-eq, count
  • focal_length_histogram.png   – ready-made bar chart
"""

import csv, sys, pathlib, collections, subprocess, shutil, re
from datetime import datetime
import matplotlib.pyplot as plt

IMG_EXTS  = {".jpg", ".jpeg", ".heic", ".heif"}
CROP_APSC = 1.5          # Fuji APS-C crop factor

# ── EXIF helpers ─────────────────────────────────────────────────────────────
def exif_vals(path: pathlib.Path):
    tags = "-Make -Model -FocalLength -FocalLengthIn35mmFormat -Composite:FocalLength35mm".split()
    out  = subprocess.run(["exiftool", "-s3", *tags, str(path)],
                          text=True, capture_output=True, check=True).stdout
    keys = ["Make", "Model", "FL", "FL35", "FL35Comp"]
    return dict(zip(keys, out.strip().splitlines() + [None]*5))

num = re.compile(r"([\d.]+)")
def to_float(s):             # '35 mm' → 35.0
    m = num.match(s or "")
    return float(m.group(1)) if m else None

def camera(meta):
    make  = (meta.get("Make")  or "").upper()
    model = (meta.get("Model") or "")
    if "APPLE"    in make:  return "iPhone"
    if "FUJIFILM" in make:  return "XT5" if "X-T5" in model.upper() else model
    return model or make or "Unknown"

def ff_equiv(meta, native):
    """Return 35-mm-equivalent focal length."""
    for tag in ("FL35Comp", "FL35"):
        mm = to_float(meta.get(tag))
        if mm: return mm
    if native is None: return None
    return native * CROP_APSC if "FUJIFILM" in (meta.get("Make","").upper()) else native

def show_progress(i, total):
    width = shutil.get_terminal_size().columns
    sys.stdout.write(f"\r[ {i:{len(str(total))}} / {total} ] scanning…".ljust(width))
    sys.stdout.flush()

# ── main ────────────────────────────────────────────────────────────────────
def main(folder):
    root = pathlib.Path(folder).expanduser()
    if not root.is_dir():
        sys.exit(f"Folder not found: {root}")

    files = [f for f in root.rglob("*") if f.suffix.lower() in IMG_EXTS]
    if not files:
        sys.exit("No supported images found.")

    hist  = collections.Counter()            # 35-mm-eq histogram
    camfx = collections.Counter()            # (camera, native, ff) → count

    for i, f in enumerate(files, 1):
        show_progress(i, len(files))
        meta    = exif_vals(f)
        native  = to_float(meta.get("FL"))
        ff_mm   = ff_equiv(meta, native)
        cam     = camera(meta)

        if ff_mm:
            hist[round(ff_mm)] += 1
        if native and ff_mm:
            camfx[(cam, round(native), round(ff_mm))] += 1

    sys.stdout.write("\r" + " "*shutil.get_terminal_size().columns + "\r")

    if not hist:
        sys.exit("No focal-length data found (tags missing).")

    # ── write CSVs ──────────────────────────────────────────────────────────
    with (root / "focal_length_histogram.csv").open("w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["focal_mm_35eq", "count"])
        for mm,c in sorted(hist.items()): w.writerow([mm, c])

    with (root / "camera_focal_usage.csv").open("w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["camera", "native_mm", "focal_mm_35eq", "count"])
        for (cam,nmm,ffmm),c in sorted(camfx.items()):
            w.writerow([cam, nmm, ffmm, c])

    # ── plot histogram ─────────────────────────────────────────────────────
    mm, cnt = zip(*sorted(hist.items()))
    plt.figure(figsize=(10,6))
    plt.bar(mm, cnt, width=1, edgecolor="black")
    plt.title(f"Focal-length usage (full-frame eq.) – {datetime.now():%Y-%m-%d}")
    plt.xlabel("Focal length (mm, FF eq.)"); plt.ylabel("Frames")
    plt.xticks(mm, rotation=45); plt.tight_layout()
    plt.savefig(root / "focal_length_histogram.png", dpi=160)

    print("Done!  • focal_length_histogram.csv"
          "  • camera_focal_usage.csv  • focal_length_histogram.png")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: analyze_focal_lengths.py /path/to/photo_folder")
    main(sys.argv[1])

