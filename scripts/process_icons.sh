#!/usr/bin/env bash
# One-off image-processing pipeline for the icon pack the user dropped into
# assets/images/icons/. Removes dark backgrounds from solo icons + slices
# the two sprite sheets into individual tiles.
#
# Run from the project root:
#   bash scripts/process_icons.sh
#
# Output: assets/images/icons/processed/<icon>.png
# Default final size: 128x128 PNG with 112px max content.
# Override with ICON_SIZE=64 ICON_CONTENT_SIZE=56 if needed.
# Strategy:
#   - Solo ui_*.png files: dark glow halo on near-pure-black bg.
#     -> remove the dark bg, trim, then center each icon on a square canvas.
#   - action_icons_sheet_noborder.png: imagegen-created 4 cols x 3 rows of
#     bare action icons on a chroma-key green bg. We slice, remove the green
#     bg, trim, then center each icon on a square canvas.
#   - ui_support_icons_sheet.png: 6 cols x 5 rows of bare icons on navy.
#     The icons are not on a perfectly even grid, so we crop around measured
#     centers, remove the dark bg per-tile, trim, then center each icon on a
#     square canvas.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONS=assets/images/icons
OUT=$ICONS/processed
ICON_SIZE=${ICON_SIZE:-128}
ICON_CONTENT_SIZE=${ICON_CONTENT_SIZE:-112}
mkdir -p "$OUT"

echo "==> Cleaning solo UI icons"
SOLO=(ui_play ui_profile ui_settings ui_info ui_logout ui_sign_out ui_delete)
for name in "${SOLO[@]}"; do
  src="$ICONS/${name}.png"
  dst="$OUT/${name}.png"
  if [[ ! -f "$src" ]]; then
    echo "  skip $name (missing)"
    continue
  fi
  magick "$src" \
    -alpha set \
    -fuzz 12% \
    -transparent black \
    -trim +repage \
    -background none \
    -gravity center \
    -resize "${ICON_CONTENT_SIZE}x${ICON_CONTENT_SIZE}" \
    -extent "${ICON_SIZE}x${ICON_SIZE}" \
    "$dst"
  echo "  + $name"
done

echo "==> Slicing action_icons_sheet_noborder (4x3 = 12 bare action icons)"
# This sheet is generated from imagegen to match the bare support/UI concept:
# no frame, no border, no card background.
ACTION_SHEET="$ICONS/action_icons_sheet_noborder.png"
if [[ ! -f "$ACTION_SHEET" ]]; then
  echo "Missing $ACTION_SHEET" >&2
  exit 1
fi
ACTION_SOURCE="$ACTION_SHEET"
CHROMA_HELPER="${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py"
if [[ -f "$CHROMA_HELPER" ]] && command -v python3 >/dev/null 2>&1; then
  ACTION_SOURCE="/private/tmp/dungeonku_action_icons_sheet_alpha.png"
  python3 "$CHROMA_HELPER" \
    --input "$ACTION_SHEET" \
    --out "$ACTION_SOURCE" \
    --auto-key border \
    --soft-matte \
    --transparent-threshold 24 \
    --opaque-threshold 180 \
    --despill >/dev/null
fi
magick "$ACTION_SOURCE" \
  -crop 4x3@ +repage \
  -set filename:tile "%[fx:t]" \
  "$OUT/action_%[filename:tile].png"

# Names follow the order shown in the sheet: row-major.
ACTION_NAMES=(
  sword sparkle shield boot
  speech check cross eye
  magnify footstep fire arrow
)
for i in "${!ACTION_NAMES[@]}"; do
  if [[ -f "$OUT/action_${i}.png" ]]; then
    mv "$OUT/action_${i}.png" "$OUT/action_${ACTION_NAMES[$i]}.png"
  fi
done

for f in "$OUT"/action_*.png; do
  magick "$f" \
    -alpha set \
    -trim +repage \
    -background none \
    -gravity center \
    -resize "${ICON_CONTENT_SIZE}x${ICON_CONTENT_SIZE}" \
    -extent "${ICON_SIZE}x${ICON_SIZE}" \
    "$f"
done
echo "  + 12 action_*.png (${ICON_SIZE}x${ICON_SIZE}, content <= ${ICON_CONTENT_SIZE}px)"

# Row-major naming, matching the sheet.
SUPPORT_NAMES=(
  eye arrow_left arrow_right chevron_right chevron_down dots
  check cross magnify send quill chart
  book scroll group scroll_list dice sparkle
  speech question boot1 boot2 shield hammer
  fire plus home save pause refresh
)

echo "==> Slicing ui_support_icons_sheet (6x5 = 30 measured crops) + bg removal"
SUPPORT_X=(145 355 555 755 960 1150)
SUPPORT_Y=(145 382 610 835 1065)
SUPPORT_CROP=${SUPPORT_CROP:-190}
for i in "${!SUPPORT_NAMES[@]}"; do
  name=${SUPPORT_NAMES[$i]}
  row=$((i / 6))
  col=$((i % 6))
  x=$((SUPPORT_X[$col] - SUPPORT_CROP / 2))
  y=$((SUPPORT_Y[$row] - SUPPORT_CROP / 2))
  magick "$ICONS/ui_support_icons_sheet.png" \
    -crop "${SUPPORT_CROP}x${SUPPORT_CROP}+${x}+${y}" +repage \
    -alpha set \
    -fuzz 6% \
    -transparent '#020617' \
    -trim +repage \
    -background none \
    -gravity center \
    -resize "${ICON_CONTENT_SIZE}x${ICON_CONTENT_SIZE}" \
    -extent "${ICON_SIZE}x${ICON_SIZE}" \
    "$OUT/support_${name}.png"
done
echo "  + 30 support_*.png (${ICON_SIZE}x${ICON_SIZE}, content <= ${ICON_CONTENT_SIZE}px)"

# Reuse the cleaned support icons where an action icon is the same concept.
# This keeps action/support visually consistent and avoids chroma-key damage
# on green/red action symbols generated on the sheet.
ACTION_SUPPORT_PAIRS=(
  sparkle:sparkle
  shield:shield
  boot:boot2
  speech:speech
  check:check
  cross:cross
  eye:eye
  magnify:magnify
  fire:fire
  arrow:arrow_right
)
for pair in "${ACTION_SUPPORT_PAIRS[@]}"; do
  action_name=${pair%%:*}
  support_name=${pair##*:}
  cp "$OUT/support_${support_name}.png" "$OUT/action_${action_name}.png"
done
echo "  + aligned action_*.png with matching support concepts"

echo "==> Done."
echo "Listing $OUT:"
ls -la "$OUT" | head -50
