#!/usr/bin/env bash
set -e
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_SEMANTIC_THREADS=1
export ACTIVE_SLAM_SEMANTIC_NICE=10
echo '【CPU 對照測試】僅限制語意辨識的 CPU 執行緒與優先順序；保留原模型與所有 VINS 校正。'
exec bash "$setup_dir/record_full_slam_walking_test.sh"
