#!/usr/bin/env bash
# Offline AprilTag detection on a recorded run (no camera, no SLAM).
#
#   bash setup/ground_truth/apriltag_offline.sh RUN_DIR SCENE_YAML [RATE]
#
# Replays RUN_DIR/sensors*.bag (infra1 only), runs apriltag_ros on
# /camera/infra1/image_rect_raw and writes RUN_DIR/tag_detections.bag.
# Then: python3 setup/eval_ground_truth.py RUN_DIR --gt SCENE_YAML
#
# Needs apriltag_ros (Noetic): sudo apt install ros-noetic-apriltag-ros
# Jetson host is Ubuntu 22.04 (no Noetic): install it inside the container there.
# Run it after recording, not while recording.
set -eo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
run_dir="${1:?usage: apriltag_offline.sh RUN_DIR SCENE_YAML [RATE]}"
scene="${2:?usage: apriltag_offline.sh RUN_DIR SCENE_YAML [RATE]}"
rate="${3:-0.5}"   # slower than real time so the detector never drops frames
shopt -s nullglob
bags=("$run_dir"/sensors*.bag)
(( ${#bags[@]} )) || { echo "沒有找到 $run_dir/sensors*.bag"; exit 1; }
source "$here/../source_active_slam.bash"
rospack find apriltag_ros >/dev/null 2>&1 || {
  echo '找不到 apriltag_ros：sudo apt install ros-noetic-apriltag-ros'; exit 1; }

params="$run_dir/apriltag_params.yaml"
python3 - "$scene" "$params" <<'PY'
import sys, yaml
scene = yaml.safe_load(open(sys.argv[1]))
tags = scene.get('tags') or {}
if not tags:
    raise SystemExit('場景檔沒有 tags。')
out = {
    'tag_family': 'tag36h11', 'tag_threads': 2, 'tag_decimate': 1.0, 'tag_blur': 0.0,
    'tag_refine_edges': 1, 'tag_debug': 0, 'max_hamming_dist': 0, 'publish_tf': False,
    'transport_hint': 'raw',
    'standalone_tags': [{'id': int(i), 'size': float(t['size_m']), 'name': 'tag_{}'.format(i)}
                        for i, t in sorted(tags.items(), key=lambda kv: int(kv[0]))],
    'tag_bundles': [],
}
yaml.safe_dump(out, open(sys.argv[2], 'w'), default_flow_style=None)
print('AprilTag：{} 張（{}）'.format(len(tags), ', '.join(str(i) for i in sorted(tags))))
PY

pids=()
cleanup() { for p in "${pids[@]}"; do kill -INT "$p" 2>/dev/null || true; done; wait 2>/dev/null || true; }
trap cleanup EXIT
rosnode list >/dev/null 2>&1 || { roscore >/dev/null 2>&1 & pids+=($!); }
for _ in {1..40}; do rosnode list >/dev/null 2>&1 && break; sleep .5; done
rosparam set /use_sim_time true
rosparam load "$params" /apriltag_offline
rosrun apriltag_ros apriltag_ros_continuous_node __name:=apriltag_offline \
  image_rect:=/camera/infra1/image_rect_raw camera_info:=/camera/infra1/camera_info \
  _camera_frame:=camera_infra1_optical_frame > "$run_dir/apriltag_offline.log" 2>&1 &
pids+=($!)
rosbag record -O "$run_dir/tag_detections.bag" /tag_detections > /dev/null 2>&1 &
rec_pid=$!; pids+=($rec_pid)
sleep 3
echo "重播 ${#bags[@]} 個 bag（速度 ${rate}x）..."
rosbag play --clock -q -r "$rate" "${bags[@]}" \
  --topics /camera/infra1/image_rect_raw /camera/infra1/camera_info
sleep 3
kill -INT "$rec_pid"; wait "$rec_pid" 2>/dev/null || true
rosparam set /use_sim_time false
echo "完成：$run_dir/tag_detections.bag"
