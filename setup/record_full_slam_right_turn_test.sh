#!/usr/bin/env bash
set -e
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_TEST_MODE=corner
export ACTIVE_SLAM_TEST_PIPELINE=full
export ACTIVE_SLAM_PREPARE_SECONDS=15
export ACTIVE_SLAM_SEMANTIC_THREADS=1
export ACTIVE_SLAM_SEMANTIC_NICE=10
unset ACTIVE_SLAM_WALK_DISTANCE_M
printf '\n【右轉步行測試】先量好第一段 7.35 公尺轉角。\n右轉後最多走約 5 公尺；終點請離牆壁、桌椅約 1 公尺，可以提早停下。\n請沿上一輪成功路線的起點與朝向開始。\nRViz 開啟後準備 15 秒，固定相機後才初始化定位與建圖。\n依提示完成：靜止 10 秒 → 直走 20 秒 → 右轉 5 秒 → 第二段慢走 20 秒 → 靜止 20 秒。\n提早到達終點時，剩餘倒數保持不動。終點保持原高度與朝向，等待後續提示。\n\n'
exec bash "$setup_dir/record_isolated_vins_test.sh"
