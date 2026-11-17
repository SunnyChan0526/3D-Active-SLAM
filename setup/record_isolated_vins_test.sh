#!/usr/bin/env bash
# Collect guided sensor data; default to the isolated camera/VINS pipeline.
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Check before creating logs, stopping nodes, or starting ROS.
python3 "$setup_dir/recording_disk_guard.py" "$setup_dir"
source "$setup_dir/source_active_slam.bash"
pipeline="${ACTIVE_SLAM_TEST_PIPELINE:-isolated}"
case "$pipeline" in
  isolated) result_group=vins_isolated_tests; full_nodes=false ;;
  full) result_group=vins_full_pipeline_tests; full_nodes=true ;;
  *) echo "Unknown test pipeline: $pipeline"; exit 1 ;;
esac
run_dir="$setup_dir/$result_group/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$run_dir"
exec > >(tee "$run_dir/summary.log") 2>&1
export PYTHONUNBUFFERED=1
test_mode="${ACTIVE_SLAM_TEST_MODE:-translation}"
case "$test_mode" in
  translation|rotation|walking|corner|free) ;;
  *) echo "Unknown test mode: $test_mode"; exit 1 ;;
esac
if [[ "$test_mode" == free && "$pipeline" != full ]]; then
  echo '自由建圖模式需要完整 Planning-only 流程。'; exit 1
fi
echo "Sensor test: $run_dir"
echo "Pipeline: $pipeline"
echo "Test mode: $test_mode"
printf '\n\033[1;93m【啟動】先等待相機與 RViz 就緒。\n就緒後才會開始準備倒數，再進入正式測試。\033[0m\n\n'
bash "$setup_dir/stop_active_slam.sh"
camera_pid=''; pipeline_pid=''; bag_pid=''; disk_guard_pid=''; session_pid=''
cleanup() {
  [[ -z "$session_pid" ]] || kill -TERM "$session_pid" 2>/dev/null || true
  [[ -z "$session_pid" ]] || wait "$session_pid" 2>/dev/null || true
  [[ -z "$disk_guard_pid" ]] || kill "$disk_guard_pid" 2>/dev/null || true
  [[ -z "$disk_guard_pid" ]] || wait "$disk_guard_pid" 2>/dev/null || true
  [[ -z "$bag_pid" ]] || kill -INT "$bag_pid" 2>/dev/null || true
  [[ -z "$pipeline_pid" ]] || kill -INT "$pipeline_pid" 2>/dev/null || true
  [[ -z "$camera_pid" ]] || kill -INT "$camera_pid" 2>/dev/null || true
  [[ -z "$bag_pid" ]] || wait "$bag_pid" 2>/dev/null || true
  if [[ "$test_mode" == free ]]; then
    for bag_file in "$run_dir"/sensors*.bag; do
      [[ -f "$bag_file" ]] || continue
      rosbag info "$bag_file" > "$bag_file.info.txt" 2>&1 || true
    done
  fi
  [[ -z "$pipeline_pid" ]] || wait "$pipeline_pid" 2>/dev/null || true
  [[ -z "$camera_pid" ]] || wait "$camera_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM
python3 "$setup_dir/recording_disk_guard.py" "$run_dir" --watch-parent "$$" &
disk_guard_pid=$!
launch_args=(disable_ir_emitter:=true "start_sloam:=$full_nodes" "start_loop:=$full_nodes"
  "start_semantic:=$full_nodes" "start_cloud:=$full_nodes" "start_cop:=$full_nodes"
  "start_planner:=$full_nodes" "start_rviz:=$full_nodes")
launch_args+=("handheld_auto:=${ACTIVE_SLAM_HANDHELD_AUTO:-false}")
launch_args+=("handheld_height_limit:=${ACTIVE_SLAM_HANDHELD_HEIGHT_LIMIT:-false}"
  "handheld_z_min:=${ACTIVE_SLAM_HANDHELD_Z_MIN:-0.1}" "handheld_z_max:=${ACTIVE_SLAM_HANDHELD_Z_MAX:-0.4}"
  "handheld_z_samples:=${ACTIVE_SLAM_HANDHELD_Z_SAMPLES:-3}")
launch_args+=("semantic_cpu_threads:=${ACTIVE_SLAM_SEMANTIC_THREADS:-0}"
  "semantic_cpu_nice:=${ACTIVE_SLAM_SEMANTIC_NICE:-0}")
echo "Semantic CPU settings: threads=${ACTIVE_SLAM_SEMANTIC_THREADS:-0}, nice=${ACTIVE_SLAM_SEMANTIC_NICE:-0}"
roslaunch "$setup_dir/all_legacy_planning_only.launch" "${launch_args[@]}" --dump-params \
  > "$run_dir/resolved_params.yaml"
python - "$pipeline" "$run_dir/resolved_params.yaml" <<'PY'
import sys,yaml,os
with open(sys.argv[2]) as stream: params=yaml.safe_load(stream) or {}
if sys.argv[1]=='full':
    assert params['/exploration_node/fsm/planning_only'] is True
    assert params['/exploration_node/fsm/handheld_auto'] == (os.environ.get('ACTIVE_SLAM_HANDHELD_AUTO','false')=='true')
    assert params['/exploration_node/handheld_height/enable'] == (os.environ.get('ACTIVE_SLAM_HANDHELD_HEIGHT_LIMIT','false')=='true')
assert not any(k.startswith('/planning_preview_node/') for k in params)
PY
# Preparation starts only camera and RViz; no estimator or map exists yet.
roslaunch "$setup_dir/all_legacy_planning_only.launch" \
  start_vins:=false start_sloam:=false start_loop:=false \
  start_semantic:=false start_cloud:=false start_cop:=false start_planner:=false \
  "start_rviz:=$full_nodes" > "$run_dir/camera_rviz.log" 2>&1 &
camera_pid=$!
# stop_active_slam preserves the existing ROS master; wait if it must be created.
for attempt in {1..60}; do
  if rosnode list >/dev/null 2>&1; then break; fi
  sleep .5
done
rosnode list >/dev/null
# Record initialization as well as every guided stage. The duration is only
# an emergency cap; normally recording stops explicitly after the full guide.
record_args=(--duration=300)
if [[ "$test_mode" == free ]]; then
  # A rolling buffer only removes this session's oldest split bags.
  record_args=(--split --size=1024 --max-splits=4 --repeat-latched)
fi
rosbag record --lz4 --min-space=2G "${record_args[@]}" -O "$run_dir/sensors.bag" \
  /camera/imu /camera/infra1/image_rect_raw /camera/infra2/image_rect_raw \
  /camera/infra1/camera_info /camera/infra2/camera_info /tf_static /tf \
  /vins_estimator/odometry /vins_estimator/imu_propagate \
  /vins_estimator/point_cloud /vins_estimator/keyframe_point /rosout \
  /factor_graph_atl/quadrotor/high_freq_odom \
  /factor_graph_atl/quadrotor/sloam_to_vio_odom \
  /exploration_node/handheld_status /planning_vis/handheld_local_path /planning_vis/handheld_goal \
  /planning_vis/viewpoints /behavior_goal_vis/next_goal \
  > "$run_dir/record.log" 2>&1 &
bag_pid=$!
python - "$pipeline" <<'PY'
import rospy,sys
from sensor_msgs.msg import Image,Imu
rospy.init_node('test_preparation_readiness',anonymous=True,disable_signals=True)
rospy.wait_for_message('/camera/imu',Imu,timeout=60)
rospy.wait_for_message('/camera/infra1/image_rect_raw',Image,timeout=30)
if sys.argv[1]=='full':
    rospy.wait_for_service('/rvizvisualisation/get_loggers',timeout=60)
print('【相機與視窗就緒】VINS 與建圖尚未啟動，現在開始準備倒數。',flush=True)
PY
python - "${ACTIVE_SLAM_PREPARE_SECONDS:-15}" "$run_dir/preparation.json" "$pipeline" <<'PY'
import json,sys,time
from pathlib import Path
try:
    seconds=int(sys.argv[1])
except ValueError:
    raise SystemExit('準備秒數必須是 0～120 的整數。')
if not 0<=seconds<=120:
    raise SystemExit('準備秒數必須是 0～120 的整數。')
record={'stage':'RViz 開啟後準備' if sys.argv[3]=='full' else '相機就緒後準備','seconds':seconds,'start_wall_time':time.time()}
print('\a\n\033[1;93m'+'='*66,flush=True)
print('  相機與視窗已就緒；VINS 與建圖尚未啟動，準備時間：{} 秒\n  現在可以調整 RViz 視窗、站位與握持；正式測試尚未開始。'.format(seconds),flush=True)
print('='*66+'\033[0m',flush=True)
end=time.monotonic()+seconds
while time.monotonic()<end:
    remaining=max(1,int(end-time.monotonic()+.999))
    print('  【準備中】剩餘 {:2d} 秒；正式測試尚未開始。     '.format(remaining),end='\r',flush=True)
    time.sleep(min(1,max(0,end-time.monotonic())))
print('\a\n\033[1;92m【準備結束】現在固定相機，不要再站起或調整握持。\n接著啟動全新的 VINS 與建圖；等待初始化期間也請保持不動。\033[0m\n',flush=True)
record['end_wall_time']=time.time()
Path(sys.argv[2]).write_text(json.dumps(record,ensure_ascii=False,indent=2))
PY


printf '\a\n\033[1;93m【固定相機】5 秒後啟動全新定位與建圖，從現在起不要移動。\033[0m\n'
sleep 5
# Estimator and downstream maps start after preparation with one fresh origin.
roslaunch "$setup_dir/all_legacy_planning_only.launch" "${launch_args[@]}" \
  start_camera:=false start_rviz:=false > "$run_dir/vins.log" 2>&1 &
pipeline_pid=$!
python - "$pipeline" <<'PY'
import rospy,sys
from roscpp.srv import GetLoggers, SetLoggerLevel
from nav_msgs.msg import Odometry
rospy.init_node('vins_diagnostic_logger_setup',anonymous=True,disable_signals=True)
rospy.wait_for_service('/vins_estimator/get_loggers',timeout=30)
rospy.wait_for_service('/vins_estimator/set_logger_level',timeout=30)
loggers=rospy.ServiceProxy('/vins_estimator/get_loggers',GetLoggers)().loggers
selected=[l.name for l in loggers if l.name=='ros.vins' or l.name.startswith('ros.vins.')]
if not selected:raise SystemExit('VINS package logger not found; inspect vins.log')
for name in selected:
    rospy.ServiceProxy('/vins_estimator/set_logger_level',SetLoggerLevel)(name,'debug')
print('Enabled diagnostic feature-count and solver logging:',selected)
print('【等待初始化】請固定相機，正在等候 VINS odometry；最長 60 秒。',flush=True)
rospy.wait_for_message('/vins_estimator/odometry',Odometry,timeout=60)
if sys.argv[1]=='full':
    if rospy.get_param('/exploration_node/fsm/planning_only',False) is not True:
        raise SystemExit('Planning-only check failed; test stopped.')
    print('【完整流程檢查】等待 SLOAM odometry；不觸發規劃。',flush=True)
    rospy.wait_for_message('/factor_graph_atl/quadrotor/high_freq_odom',Odometry,timeout=30)
    print('【確認 RViz】請繼續固定相機，準備倒數已結束。',flush=True)
    rospy.wait_for_service('/rvizvisualisation/get_loggers',timeout=30)
print('【新定位與建圖就緒】請等待下一個操作提示。',flush=True)
PY

if [[ "$test_mode" == free ]]; then
  # wait is interruptible so the disk guard can immediately invoke cleanup.
  python "$setup_dir/free_mapping_session.py" "$run_dir" "$camera_pid" "$pipeline_pid" "$bag_pid" <&0 &
  session_pid=$!
  wait "$session_pid"
  session_pid=''
  cleanup
  trap - EXIT
  echo "自由建圖已結束。Files saved in: $run_dir"
  exit 0
fi

guide_args=()
if [[ -n "${ACTIVE_SLAM_WALK_DISTANCE_M:-}" ]]; then
  guide_args+=(--walking-distance-m "$ACTIVE_SLAM_WALK_DISTANCE_M")
fi
python "$setup_dir/guided_vins_motion.py" --mode "$test_mode" --output "$run_dir/motion_stages.json" \
  --watch-pid "$bag_pid" --watch-pid "$camera_pid" --watch-pid "$pipeline_pid" "${guide_args[@]}"
if [[ "${ACTIVE_SLAM_AUTO_PLAN:-false}" == true ]]; then
  if [[ "$pipeline" != full ]]; then
    echo '自動規劃只允許完整 Planning-only 流程。'
    exit 1
  fi
  kill -0 "$bag_pid"
  python "$setup_dir/auto_plan_after_walk.py" "$run_dir"
fi
kill -INT "$bag_pid"
bag_status=0
wait "$bag_pid" || bag_status=$?
bag_pid=''
if [[ "$bag_status" != 0 && "$bag_status" != 130 ]]; then
  echo "錄製程序異常結束（代碼 $bag_status），請保留紀錄並回報。"
  exit "$bag_status"
fi
rosbag info "$run_dir/sensors.bag" > "$run_dir/bag_info.txt"
if [[ "${ACTIVE_SLAM_KEEP_RUNNING:-false}" == true ]]; then
  echo "Recording completed. Files saved in: $run_dir"
  printf '\a\n\033[1;92m【地圖檢查】錄製已完成，RViz 與建圖繼續運行。\n請查看地圖與路線；相機留在終點原高度，不要遮住鏡頭。\n保留此終端；Ctrl+C 才會停止本次節點。\033[0m\n'
  wait "$pipeline_pid"
  exit 0
fi
echo '【收尾】資料已保存，正在停止本次啟動的節點；仍請不要移動。'
cleanup
trap - EXIT
printf '\a\n\033[1;92m===============================================================\n  已全部完成，可以放下相機。\n  不用再按 Ctrl+C；本次測試程序已停止。\n===============================================================\033[0m\n'
echo "Recording completed. Files saved in: $run_dir"
