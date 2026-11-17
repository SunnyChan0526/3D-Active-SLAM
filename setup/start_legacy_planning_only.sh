#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
run_dir="$setup_dir/runs/$(date +%Y%m%d_%H%M%S)_$$"
mkdir -p "$run_dir"
exec > >(tee "$run_dir/console.log") 2>&1
export PYTHONUNBUFFERED=1
echo "Session logs: $run_dir/console.log"
[[ -n "${DISPLAY:-}" ]] || { echo 'Run this in your desktop terminal so RViz can open.'; exit 1; }
nodes="$(rosnode list 2>/dev/null || true)"
if [[ "${ACTIVE_SLAM_DISABLE_IR_EMITTER:-false}" == true ]] && \
   printf '%s\n' "$nodes" | grep -Eq '^/(vins_estimator|active_slam_input_node|exploration_node|loop_closure_server_node)$'; then
  echo 'Emitter-off test requires a fresh estimator and maps; existing pipeline preserved.'
  echo 'Run stop_active_slam.sh, then run this emitter-off command again.'
  exit 1
fi
if printf '%s\n' "$nodes" | grep -qx '/planning_preview_node'; then
  echo 'Multi-segment preview is still running. Stop its launch before switching to legacy mode.'
  exit 1
fi
args=()
args+=("disable_ir_emitter:=${ACTIVE_SLAM_DISABLE_IR_EMITTER:-false}")
choose() {
  local flag="$1" pattern="$2"
  if printf '%s\n' "$nodes" | grep -Eq "$pattern"; then
    args+=("start_$flag:=false")
    echo "Reusing existing $flag node(s)."
  else
    args+=("start_$flag:=true")
  fi
}
choose camera '^/camera/'
choose vins '(^|/)vins_estimator$'
choose sloam '^/active_slam_input_node$'
choose loop '^/loop_closure_server_node$'
choose semantic '^/rgb_sem_segmentation$'
choose cloud '^/process_cloud_node$'
choose cop '^/global_plan_server_node$'
choose planner '^/exploration_node$'
choose rviz '^/rvizvisualisation$'
if printf '%s\n' "$nodes" | grep -qx '/exploration_node'; then
  value="$(rosparam get /exploration_node/fsm/planning_only)"
  [[ "$value" == true || "$value" == True ]] || { echo 'Existing legacy planner is not planning-only. Stopping setup.'; exit 1; }
fi
roslaunch "$setup_dir/all_legacy_planning_only.launch" "${args[@]}" --dump-params > "$run_dir/resolved_params.yaml"
python - "$run_dir/resolved_params.yaml" <<'PY'
import sys, yaml
with open(sys.argv[1]) as stream:
    params=yaml.safe_load(stream) or {}
key='/exploration_node/fsm/planning_only'
if key in params and params[key] is not True:
    raise SystemExit('planning_only must be true')
PY
echo 'Starting mapping, semantic perception, COP server, legacy single-shot planning-only FSM and author RViz.'
echo 'No trigger is sent. Legacy trigger topic: /sunny_mapping_test/disabled_waypoints (nav_msgs/Path). Move slowly while VINS initializes.'
echo 'Keep this terminal open. Ctrl+C stops only nodes started by this launch.'
exec roslaunch "$setup_dir/all_legacy_planning_only.launch" "${args[@]}"
