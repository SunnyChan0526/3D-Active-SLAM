#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ACTIVE_SLAM_HANDHELD_AUTO=true
echo '【手持自動探索】準備與初始化後自動選目標、規劃及更新，不需要按 p。'
echo '請依 RViz 青色本段軌跡與橘色目標緩慢移動。目標高度仍依 3D 規劃。'
echo '深綠線為全域目標順序，不是可直接穿越障礙物的路線。輸入 q 再按 Enter 結束。'
exec bash "$setup_dir/start_free_mapping.sh"
