#!/usr/bin/env bash
# Download model weights that are too large for git (GitHub limit: 100 MB/file).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/src/kr_3d_active_ms_slam/semantic_detection/rgb_sem_segmentation/models"
FILE="$DEST/yolov8x-seg.pt"
SHA256="d63cbfa5764867c0066bedfa43cf2dcd90a412a1de44b2e238c43978a9d28ea6"
URL="${YOLO_URL:-https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8x-seg.pt}"

mkdir -p "$DEST"
if [[ -f "$FILE" ]] && echo "$SHA256  $FILE" | sha256sum -c --quiet; then
  echo "yolov8x-seg.pt already present and verified."; exit 0
fi
echo "Downloading $URL"
curl -fL --retry 3 -o "$FILE.part" "$URL"
mv "$FILE.part" "$FILE"
if ! echo "$SHA256  $FILE" | sha256sum -c --quiet; then
  echo "WARNING: SHA256 differs from the weights used on the dev laptop." >&2
  echo "Copy the original file from the laptop, or set YOLO_URL to the right release." >&2
  exit 1
fi
echo "OK: $FILE"
