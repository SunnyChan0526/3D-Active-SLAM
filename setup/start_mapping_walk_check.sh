#!/usr/bin/env bash
set -e
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_KEEP_RUNNING=true
export ACTIVE_SLAM_AUTO_PLAN=true
echo '【自動規劃模式】終點靜止結束後會檢查定位，再自動規劃一次；不必操作另一個終端。'
exec bash "$setup_dir/record_full_slam_right_turn_test.sh"
