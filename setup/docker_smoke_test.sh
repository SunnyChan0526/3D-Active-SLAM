#!/usr/bin/env bash
# Quick runtime check inside the container (no ROS master, no UAV nodes):
#   docker/run.sh bash setup/docker_smoke_test.sh
set -uo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== ROS packages"
for p in realsense2_camera vins exploration_manager; do
  printf '%-22s %s\n' "$p" "$(rospack find "$p" 2>&1)"
done

echo "== Python / YOLO"
python - "$repo/src/kr_3d_active_ms_slam/semantic_detection/rgb_sem_segmentation/models/yolov8x-seg.pt" <<'PY'
import sys, time
import numpy as np, torch, open3d
from ultralytics import YOLO
print("torch", torch.__version__, "| cuda", torch.cuda.is_available(), "| open3d", open3d.__version__)
m = YOLO(sys.argv[1])
img = np.zeros((480, 640, 3), dtype=np.uint8)
m(img, verbose=False)                      # warm-up
t = time.time(); m(img, verbose=False)
print("YOLO OK, inference %.2f s/frame (640x480)" % (time.time() - t))
PY

if [[ -n "${ACTIVESLAM_YOLO_SERVER:-}" ]]; then
  echo "== GPU YOLO server ($ACTIVESLAM_YOLO_SERVER)"
  python - "$repo/src/kr_3d_active_ms_slam/semantic_detection/rgb_sem_segmentation/src" <<'PY'
import os, sys, time
import numpy as np
sys.path.insert(0, sys.argv[1])
try:
    from remote_yolo import RemoteYOLO
    r = RemoteYOLO(os.environ["ACTIVESLAM_YOLO_SERVER"])
    img = np.zeros((480, 640, 3), np.uint8)
    r.predict(img); t = time.time(); r.predict(img)
    print("GPU server OK, round-trip %.0f ms (server %.0f ms)" % ((time.time() - t) * 1000, r.last_ms))
except Exception as e:
    print("GPU server NOT reachable (%s): detect.py will use CPU. Start it: docker/yolo_gpu.sh start" % e)
PY
fi

echo "== RealSense"
if command -v rs-enumerate-devices >/dev/null; then  # not shipped by ros-noetic-librealsense2
  rs-enumerate-devices -s 2>&1 | head -5
else
  lsusb 2>/dev/null | grep -i "8086" || echo "No Intel RealSense on USB (lsusb | grep 8086)"
fi
