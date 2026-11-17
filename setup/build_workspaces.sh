#!/usr/bin/env bash
set -eEo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec > >(tee -a "$setup_dir/build_workspaces.log") 2>&1
trap 'code=$?; echo "FAILED at line $LINENO (exit $code). See $setup_dir/build_workspaces.log"; exit "$code"' ERR
prefix="$HOME/.local/opt/active-slam"
source /opt/ros/noetic/setup.bash
export CMAKE_PREFIX_PATH="$prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$prefix/lib:$prefix/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
jobs="${ACTIVE_SLAM_JOBS:-2}"
for workspace in realsense_ws vins_ws active_ms_slam_ws; do
  cd "$HOME/$workspace"
  catkin init
  catkin config --extend /opt/ros/noetic --cmake-args \
    -DCMAKE_BUILD_TYPE=Release -UCMAKE_PREFIX_PATH \
    -DCeres_DIR="$prefix/lib/cmake/Ceres" -Dglog_DIR="$prefix/lib/cmake/glog" \
    -Dfmt_DIR="$prefix/lib/cmake/fmt" -DSophus_DIR="$prefix/share/sophus/cmake" \
    -DGTSAM_DIR="$prefix/lib/cmake/GTSAM" \
    -DCMAKE_INCLUDE_PATH="$prefix/include" -DCMAKE_LIBRARY_PATH="$prefix/lib" \
    -DCMAKE_BUILD_RPATH="$prefix/lib" -DPYTHON_EXECUTABLE=/usr/bin/python3
  catkin build --jobs "$jobs" --parallel-packages 1 --summarize --no-status --no-notify
done
source "$HOME/realsense_ws/devel/setup.bash"
source "$HOME/vins_ws/devel/setup.bash" --extend
source "$HOME/active_ms_slam_ws/devel/setup.bash" --extend
rospack find realsense2_camera
rospack find vins
rospack find exploration_manager
# Parse launch only. This does not start nodes or a ROS master.
roslaunch exploration_manager real_robot_planning_preview.launch --nodes
roslaunch exploration_manager real_robot_planning_preview.launch --dump-params \
  > "$setup_dir/planning_preview_resolved_params.yaml"
/usr/bin/python3 - "$setup_dir/planning_preview_resolved_params.yaml" <<'PY'
import sys
import yaml
with open(sys.argv[1]) as stream:
    params = yaml.safe_load(stream)
assert params['/planning_preview_node/fsm/planning_only'] is True, 'planning_only must be true'
print('Verified resolved launch parameter: planning_only=true')
PY
echo 'All workspace builds and launch parsing completed. No hardware or planning was started.'
