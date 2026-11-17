#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
if ! timeout 4 rosnode list >/dev/null 2>&1; then
  echo 'ROS 尚未運行；請先啟動自動探索，等到顯示自動啟用後，在另一終端執行本檢查。'
  exit 1
fi
python "$setup_dir/diagnose_auto_mapping.py" "$setup_dir/auto_mapping_checks/$(date +%Y%m%d_%H%M%S).json"
