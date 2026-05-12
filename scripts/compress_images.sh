#!/usr/bin/env bash
# Resize + recompress bundled image assets so the app doesn't ship hundreds of
# megabytes of overkill 1254² PNGs.
#
# Per-folder targets were picked based on how each asset is used in-app:
#   - avatars  : shown at ~200-300px in cards; 768² = ~3x DPI safe headroom.
#   - skills/items/elements/etc.: small grid thumbs, never bigger than ~150px;
#     512² is generous.
#   - splash   : single big screen; 640x960 still reads as full-bleed on phones.
#   - weapons  : sheet image (4 cols × 1 row); halve the dimensions.
#   - logo / story-art / backgrounds / campaigns covers / icons: untouched.
#     Logo is brand-critical, landscape art needs detail at full screen, and
#     icons have their own pipeline (process_icons.sh).
#
# Run from repo root:
#   bash scripts/compress_images.sh
#
# Idempotent: skips files already <= target. Uses ImageMagick's color
# quantization for additional savings; passes through `-strip` to drop EXIF.
# The originals are tracked in git, so `git checkout -- assets/images/` reverts.

set -euo pipefail
cd "$(dirname "$0")/.."

ROOT=assets/images

if ! command -v magick >/dev/null 2>&1; then
  echo "ERROR: ImageMagick (magick) not found. brew install imagemagick" >&2
  exit 1
fi

# compress <folder> <max-edge-px>
# Resizes every PNG/JPG in the folder so its longest edge is at most the
# given pixel count, then re-encodes with palette quantization. Skips files
# already at or below the target.
compress() {
  local folder="$1" max="$2"
  if [[ ! -d "$folder" ]]; then
    echo "  (skip, missing) $folder"
    return
  fi
  local before after count=0
  before=$(du -sk "$folder" | awk '{print $1}')
  while IFS= read -r -d '' f; do
    # Read current dimensions so we don't bother re-encoding files that
    # are already small enough.
    local w h longest
    w=$(magick identify -format "%w" "$f")
    h=$(magick identify -format "%h" "$f")
    longest=$((w > h ? w : h))
    if (( longest <= max )); then
      continue
    fi
    magick "$f" \
      -resize "${max}x${max}>" \
      -strip \
      -colors 256 \
      -dither None \
      -define png:compression-level=9 \
      -define png:compression-strategy=2 \
      "$f"
    count=$((count + 1))
  done < <(find "$folder" -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" \) -print0)
  after=$(du -sk "$folder" | awk '{print $1}')
  printf "  %-40s %4d files | %5dKB -> %5dKB (%+d%%)\n" \
    "$folder" "$count" "$before" "$after" \
    "$(( (after - before) * 100 / (before > 0 ? before : 1) ))"
}

echo "==> Compressing image assets (skips already-small files)"
echo

# Avatars: -55% target, kept a bit larger because they're shown at full
# card size on character creation / hero details screens.
compress "$ROOT/avatars" 768

# Square pixel-art catalogues: -75% target. These are tiny grid thumbs
# in the codex / inventory; 512 is plenty.
compress "$ROOT/skills"   512
compress "$ROOT/bosses"   512
compress "$ROOT/npcs"     512
compress "$ROOT/monsters" 512
compress "$ROOT/items"    512
compress "$ROOT/elements" 512

# Sheet asset: 1774×887 → halve. The class weapons sheet is sliced at
# runtime, so we just need enough resolution per cell.
compress "$ROOT/weapons" 887

# Splash: shown once on cold start. Keep it readable but not enormous.
compress "$ROOT/splash" 960

echo
echo "==> Done. Untouched (intentional):"
echo "    $ROOT/logo/         (brand asset, kept full-res)"
echo "    $ROOT/story-art/    (landscape narrative art)"
echo "    $ROOT/backgrounds/  (landscape backgrounds)"
echo "    $ROOT/campaigns/    (landscape campaign covers)"
echo "    $ROOT/icons/        (managed by process_icons.sh)"
echo
echo "Total assets/images now:"
du -sh "$ROOT"
