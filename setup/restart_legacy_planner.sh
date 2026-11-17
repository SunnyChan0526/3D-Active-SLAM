#!/usr/bin/env bash
# Restart only the planner; preserve the camera, VINS and SLOAM origins.
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
exec > >(tee "$setup_dir/legacy_planner_restart.log") 2>&1
nodes="$(rosnode list)"
if printf '%s\n' "$nodes" | grep -qx '/planning_preview_node'; then
  echo 'Stop the multi-segment preview before starting the legacy planner.'
  exit 1
fi
if printf '%s\n' "$nodes" | grep -qx '/exploration_node'; then
  value="$(rosparam get /exploration_node/fsm/planning_only)"
  [[ "$value" == true || "$value" == True ]] || { echo 'Existing planner is not planning-only; no change made.'; exit 1; }
  rosnode kill /exploration_node
  for attempt in {1..30}; do
    if ! rosnode list | grep -qx '/exploration_node'; then break; fi
    sleep .1
  done
  if rosnode list | grep -qx '/exploration_node'; then
    echo 'Previous planner still registered; no duplicate started.'; exit 1
  fi
fi
echo 'Starting updated legacy planner only. Other nodes are preserved; no trigger is sent.'
exec roslaunch exploration_manager real_robot_planning_sunny.launch
