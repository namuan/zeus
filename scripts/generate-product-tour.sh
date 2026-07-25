#!/usr/bin/env bash
#
# generate-product-tour.sh
#
# Reads product-tour/annotations.json and regenerates the full tour in one step:
#   1. Captures the running app.
#   2. Renders one full-screen annotated image per feature.
#   3. Regenerates product-tour/PRODUCT_TOUR.md.
#
# To adjust a box or change a description, edit annotations.json and re-run.
#
# Usage:
#   bash scripts/generate-product-tour.sh
#
# Env overrides:
#   KEEP_SOURCE=1   Keep the raw screenshot as product-tour/source.png.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOUR_DIR="$REPO_ROOT/product-tour"
CFG="$TOUR_DIR/annotations.json"

if [ ! -f "$CFG" ]; then
  echo "error: $CFG not found" >&2
  exit 1
fi

command -v jq      >/dev/null 2>&1 || { echo "error: jq not found" >&2;      exit 1; }
command -v magick  >/dev/null 2>&1 || { echo "error: magick not found" >&2;  exit 1; }
command -v screencapture >/dev/null 2>&1 || { echo "error: screencapture not found" >&2; exit 1; }

# --- Read metadata ----------------------------------------------------------
APP_NAME="$(jq -r '.appName' "$CFG")"
DEFX="$(jq -r '.defaultWinX' "$CFG")"
DEFY="$(jq -r '.defaultWinY' "$CFG")"
SCALE="$(jq -r '.scale' "$CFG")"
SCREEN_W="$(jq -r '.screenWidth' "$CFG")"
BH="$(jq -r '.bannerHeight' "$CFG")"
FS="$(jq -r '.fontSize' "$CFG")"
FONT="$(jq -r '.font' "$CFG")"

if [ ! -f "$FONT" ]; then
  for f in /System/Library/Fonts/Helvetica.ttc /System/Library/Fonts/Supplemental/Arial.ttf /System/Library/Fonts/Menlo.ttc; do
    [ -f "$f" ] && FONT="$f" && break
  done
fi

# --- Capture ----------------------------------------------------------------
echo "Activating $APP_NAME..."
osascript -e "tell application \"${APP_NAME}\" to activate" >/dev/null 2>&1 || true
sleep 1

POS="$(osascript -e "tell application \"System Events\" to tell process \"${APP_NAME}\" to get position of window 1" 2>/dev/null || echo "{$DEFX, $DEFY}")"
WX="$(echo "$POS" | tr -d '{}' | cut -d, -f1 | tr -d ' ')"
WY="$(echo "$POS" | tr -d '{}' | cut -d, -f2 | tr -d ' ')"
WX="${WX:-$DEFX}"; WY="${WY:-$DEFY}"
DX=$(( WX * SCALE - DEFX * SCALE ))
DY=$(( WY * SCALE - DEFY * SCALE ))
echo "Window at logical ($WX,$WY); annotation offset = ($DX,$DY) px"

SOURCE="$TOUR_DIR/source.png"
echo "Capturing screenshot -> $SOURCE"
screencapture -x "$SOURCE"

# --- Render features --------------------------------------------------------
echo "Rendering feature shots..."

jq -c '.features[]' "$CFG" | while read -r feat; do
  file="$(echo "$feat" | jq -r '.file')"
  col="$(echo "$feat"  | jq -r '.color')"
  x="$(echo "$feat"    | jq -r '.x')"
  y="$(echo "$feat"    | jq -r '.y')"
  w="$(echo "$feat"    | jq -r '.width')"
  h="$(echo "$feat"    | jq -r '.height')"
  desc="$(echo "$feat" | jq -r '.desc')"
  x1=$(( x + DX )); y1=$(( y + DY ))
  x2=$(( x + w + DX )); y2=$(( y + h + DY ))
  tmp="$(mktemp "${TMPDIR:-/tmp}/pt.XXXXXX.png")"
  magick "$SOURCE" -stroke "$col" -strokewidth 10 -fill none \
    -draw "rectangle $x1,$y1 $x2,$y2" "$tmp"
  magick -size "${SCREEN_W}x${BH}" -background 'rgba(28,28,30,0.85)' -fill white \
    -font "$FONT" -pointsize "$FS" -gravity Center caption:"$desc" "${tmp}.banner.png"
  magick "$tmp" "${tmp}.banner.png" -gravity South -composite "$TOUR_DIR/$file.png"
  rm -f "$tmp" "${tmp}.banner.png"
  echo "  wrote $file.png"
done

# --- Optimize for web -------------------------------------------------------
echo "Optimizing images for web..."
for f in "$TOUR_DIR"/f*.png; do
  magick "$f" -resize 1800x -strip -define png:compression-level=9 "$f"
done

# --- Regenerate markdown ---------------------------------------------------
echo "Writing $TOUR_DIR/PRODUCT_TOUR.md"

cat > "$TOUR_DIR/PRODUCT_TOUR.md" <<'HEADER'
# OpenZeus — Product Tour

Each feature is shown on a full-screen shot of the running app, with a single colored outline marking the control and a large white description centered at the bottom on a tinted grey bar. No buttons were clicked or states changed — these are captures of the live window.

HEADER

jq -c '.features[]' "$CFG" | while read -r feat; do
  file="$(echo "$feat"  | jq -r '.file')"
  title="$(echo "$feat" | jq -r '.title')"
  desc="$(echo "$feat"  | jq -r '.desc')"
  cat >> "$TOUR_DIR/PRODUCT_TOUR.md" <<MD

### $title
![$title]($file.png)

$desc
MD
done

# --- Cleanup ----------------------------------------------------------------
# source.png is kept so the live editor can load it in Edit mode.
rm -f "$TOUR_DIR"/01-annotated.png "$TOUR_DIR"/0[2-8]-*.png "$TOUR_DIR"/01-main-window.png

echo "Product tour regenerated in $TOUR_DIR"
