#!/usr/bin/env bash
set -e
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_WALK_DISTANCE_M=7.35
export ACTIVE_SLAM_PREPARE_SECONDS=15
printf '\n【長距離測試：7.35 公尺】請先量好起點與終點。\n沿上一輪成功測試相同的行走方向與相機朝向，確認整段路線可直走。\nRViz 開啟後準備 15 秒；固定相機後才初始化 VINS 與建圖。\n看到走動提示才開始，以約 20 秒走到終點；不要跑、不要轉身或走回。\n到終點立即停住，等待保存完成提示再放下相機。\n\n'
exec bash "$setup_dir/record_full_slam_walking_budget_test.sh"
