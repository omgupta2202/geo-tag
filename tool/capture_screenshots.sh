#!/usr/bin/env bash
# Capture a Play-Store-ready phone screenshot from the currently connected
# Android device or emulator (whatever `adb` sees).
#
# Usage:
#   ./tool/capture_screenshots.sh <name>
#
# Example flow (navigate the app on the device, then run one of these):
#   ./tool/capture_screenshots.sh 1_camera_hud
#   ./tool/capture_screenshots.sh 2_captured_photo
#   ./tool/capture_screenshots.sh 3_gallery
#   ./tool/capture_screenshots.sh 4_settings
#
# Output: assets/marketing/screenshots/<name>.png  (1080x1920, 9:16 — Play-ready)
#
# Why crop? Modern phones are ~20:9 (≈2.23:1). Google Play rejects screenshots
# with an aspect ratio steeper than 2:1, so we scale to width 1080 and
# center-crop to a clean 1080x1920 (9:16).

set -euo pipefail

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <name>   e.g. $0 1_camera_hud" >&2
  exit 1
fi

# Resolve repo root relative to this script so it works from anywhere.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTDIR="$ROOT/assets/marketing/screenshots"
mkdir -p "$OUTDIR"

# Check a device is attached.
DEVCOUNT="$(adb devices | awk 'NR>1 && $2=="device"' | wc -l | tr -d ' ')"
if [[ "$DEVCOUNT" == "0" ]]; then
  echo "✗ No Android device/emulator detected by adb." >&2
  echo "  • Real phone: enable USB debugging and plug in, then run 'adb devices'." >&2
  echo "  • Emulator:  flutter emulators --launch Pixel_9_Pro" >&2
  exit 1
fi

RAW="$OUTDIR/.${NAME}_raw.png"
FINAL="$OUTDIR/${NAME}.png"

echo "📸 Capturing current screen…"
adb exec-out screencap -p > "$RAW"

# Scale to width 1080, then center-crop to 1080x1920 (9:16).
sips --resampleWidth 1080 "$RAW" >/dev/null
sips -c 1920 1080 "$RAW" --out "$FINAL" >/dev/null
rm -f "$RAW"

DIMS="$(sips -g pixelWidth -g pixelHeight "$FINAL" | awk '/pixel/{print $2}' | paste -sd'x' -)"
echo "✓ Saved $FINAL  ($DIMS)"
