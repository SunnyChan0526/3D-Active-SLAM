#!/usr/bin/env bash
set -e
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_TEST_MODE=walking
export ACTIVE_SLAM_TEST_PIPELINE=full
export ACTIVE_SLAM_WALK_DISTANCE_M="${ACTIVE_SLAM_WALK_DISTANCE_M:-7.35}"
printf '\n【執行前先站好】這次直線慢走 %s 公尺，請先量好起點與終點。\n保持握持與朝向，等候倒數提示再開始；不觸發規劃。\n\n' "$ACTIVE_SLAM_WALK_DISTANCE_M"
exec bash "$setup_dir/record_isolated_vins_test.sh"
