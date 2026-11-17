#!/usr/bin/env bash
set -e
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_WALK_DISTANCE_M=1.5
export ACTIVE_SLAM_PREPARE_SECONDS=15
echo '【1.5 公尺測試】RViz 開啟後準備 15 秒，再依提示靜止、直走到標記終點、保持靜止。'
exec bash "$setup_dir/record_full_slam_walking_budget_test.sh"
