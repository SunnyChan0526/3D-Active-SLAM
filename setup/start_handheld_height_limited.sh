#!/usr/bin/env bash
# Handheld Testing Mode (方案 A：限制觀察點高度)。
# 與 start_auto_handheld_exploration.sh 相同，但只產生相機實際可到達高度內的觀察點。
# 高度為 SLAM 地圖 z（以啟動時相機位置為原點）。請先實測後用環境變數覆寫：
#   ACTIVE_SLAM_HANDHELD_Z_MIN=0.0 ACTIVE_SLAM_HANDHELD_Z_MAX=0.3 bash start_handheld_height_limited.sh
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_HANDHELD_HEIGHT_LIMIT=true
export ACTIVE_SLAM_HANDHELD_Z_MIN="${ACTIVE_SLAM_HANDHELD_Z_MIN:-0.1}"
export ACTIVE_SLAM_HANDHELD_Z_MAX="${ACTIVE_SLAM_HANDHELD_Z_MAX:-0.4}"
export ACTIVE_SLAM_HANDHELD_Z_SAMPLES="${ACTIVE_SLAM_HANDHELD_Z_SAMPLES:-3}"
python3 - <<'PY'
import os, math, sys
lo, hi = float(os.environ['ACTIVE_SLAM_HANDHELD_Z_MIN']), float(os.environ['ACTIVE_SLAM_HANDHELD_Z_MAX'])
n = int(os.environ['ACTIVE_SLAM_HANDHELD_Z_SAMPLES'])
if not (math.isfinite(lo) and math.isfinite(hi) and lo <= hi and n >= 1 and -0.1 <= lo and hi <= 2.0):
    sys.exit('高度範圍無效：需 -0.1 <= Z_MIN <= Z_MAX <= 2.0 且 Z_SAMPLES >= 1')
PY
echo "【手持高度限制模式】觀察點高度限制 Z ∈ [${ACTIVE_SLAM_HANDHELD_Z_MIN}, ${ACTIVE_SLAM_HANDHELD_Z_MAX}] m（${ACTIVE_SLAM_HANDHELD_Z_SAMPLES} 層取樣）。"
echo '此數值須以實測相機高度為準；超出範圍的 frontier 視角與 SLC 目標不會被選，也不會被算成完成。'
exec bash "$setup_dir/start_auto_handheld_exploration.sh"
