#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_TEST_MODE=free
export ACTIVE_SLAM_TEST_PIPELINE=full
export ACTIVE_SLAM_PREPARE_SECONDS="${ACTIVE_SLAM_PREPARE_SECONDS:-15}"
export ACTIVE_SLAM_SEMANTIC_THREADS=1
export ACTIVE_SLAM_SEMANTIC_NICE=10
export ACTIVE_SLAM_AUTO_PLAN=false
export ACTIVE_SLAM_KEEP_RUNNING=false
unset ACTIVE_SLAM_WALK_DISTANCE_M
echo '【自由建圖】沒有固定路線或步行倒數。準備、初始化後即可自由慢走。'
if [[ "${ACTIVE_SLAM_HANDHELD_AUTO:-false}" == true ]]; then
  echo '本輪自動選目標與更新規劃，不需要輸入 p；請依 RViz 本段路線移動。'
else
  echo '停止並保持相機高度後，在此終端輸入 p 再按 Enter，檢查定位並單次規劃。'
fi
echo '輸入 q 再按 Enter 結束；原始感測資料持續錄製，保留本輪最近約 4 GB。'
exec bash "$setup_dir/record_isolated_vins_test.sh"
