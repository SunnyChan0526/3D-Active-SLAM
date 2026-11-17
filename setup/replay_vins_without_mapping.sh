#!/usr/bin/env bash
# Replay recorded camera/IMU input into VINS only, using a private ROS master.
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
input_bag="${1:-$setup_dir/vins_full_pipeline_tests/20261109_112732/sensors.bag}"
[[ -f "$input_bag" ]] || { echo "Bag not found: $input_bag"; exit 1; }
run_dir="$setup_dir/vins_replay_tests/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$run_dir"
exec > >(tee "$run_dir/summary.log") 2>&1
echo "Replay input: $input_bag"
echo "Replay results: $run_dir"
printf '%s\n' "$input_bag" > "$run_dir/input_bag.txt"
export ROS_MASTER_URI=http://127.0.0.1:11321
export ROS_IP=127.0.0.1
unset ROS_HOSTNAME
export ROS_LOG_DIR="$run_dir/ros_logs"
export PYTHONUNBUFFERED=1
if rosnode list >/dev/null 2>&1; then
  echo 'Port 11321 already has a ROS master; preserved. Please report this message.'
  exit 1
fi
core_pid=''; vins_pid=''; record_pid=''; play_pid=''
cleanup() {
  for pid in "$play_pid" "$vins_pid" "$record_pid" "$core_pid"; do
    [[ -z "$pid" ]] || kill -INT "$pid" 2>/dev/null || true
  done
  for pid in "$play_pid" "$vins_pid" "$record_pid" "$core_pid"; do
    [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT
trap 'exit 130' INT TERM
roscore -p 11321 > "$run_dir/master.log" 2>&1 &
core_pid=$!
ready=false
for attempt in {1..60}; do
  if rosnode list >/dev/null 2>&1; then ready=true; break; fi
  sleep .25
done
[[ "$ready" == true ]] || { echo 'Private ROS master did not start.'; exit 1; }
rosparam set /use_sim_time true
rosrun vins vins_node "$HOME/vins_ws/src/VINS-Fusion/config/realsense_d435i_sunny/realsense_stereo_imu_config.yaml" \
  > "$run_dir/vins.log" 2>&1 &
vins_pid=$!
python - <<'PY'
import rospy
from roscpp.srv import GetLoggers,SetLoggerLevel
rospy.init_node('replay_vins_logger_setup',anonymous=True,disable_signals=True)
rospy.wait_for_service('/vins_estimator/get_loggers',timeout=30)
for logger in rospy.ServiceProxy('/vins_estimator/get_loggers',GetLoggers)().loggers:
    if logger.name=='ros.vins' or logger.name.startswith('ros.vins.'):
        rospy.ServiceProxy('/vins_estimator/set_logger_level',SetLoggerLevel)(logger.name,'debug')
PY
rosbag record --lz4 -O "$run_dir/vins_output.bag" /vins_estimator/odometry \
  /vins_estimator/imu_propagate /vins_estimator/point_cloud /rosout \
  > "$run_dir/record.log" 2>&1 &
record_pid=$!
echo '【重播中】不需要接相機或走動。只重播原始相機/IMU資料，不重播舊的VINS估測。'
rosbag play --clock --hz=200 --delay=2 "$input_bag" --topics \
  /camera/imu /camera/infra1/image_rect_raw /camera/infra2/image_rect_raw \
  /camera/infra1/camera_info /camera/infra2/camera_info /tf_static \
  > "$run_dir/play.log" 2>&1 &
play_pid=$!
wait "$play_pid"
play_pid=''
sleep 2
kill -INT "$vins_pid" 2>/dev/null || true
wait "$vins_pid" 2>/dev/null || true
vins_pid=''
kill -INT "$record_pid" 2>/dev/null || true
record_status=0
wait "$record_pid" || record_status=$?
record_pid=''
[[ "$record_status" == 0 || "$record_status" == 130 ]] || exit "$record_status"
rosbag info "$run_dir/vins_output.bag" > "$run_dir/bag_info.txt"
cleanup
trap - EXIT
echo "【重播完成】結果已保存：$run_dir"
