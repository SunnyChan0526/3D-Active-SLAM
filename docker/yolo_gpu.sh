#!/usr/bin/env bash
# Jetson GPU YOLO server for the semantic detection node.
#
# The main container (Ubuntu 20.04 / ROS Noetic) cannot use JetPack 6's CUDA,
# so YOLOv8-seg runs in this separate JetPack 6 container and detect.py talks to
# it over 127.0.0.1:8765 (docker/run.sh sets ACTIVESLAM_YOLO_SERVER on Jetson).
# If the server is not running, detect.py falls back to CPU YOLO.
#
#   docker/yolo_gpu.sh build    build the image (once)
#   docker/yolo_gpu.sh start    start in background (restarts on reboot)
#   docker/yolo_gpu.sh stop     stop and remove
#   docker/yolo_gpu.sh logs     follow logs
#   docker/yolo_gpu.sh status
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${ACTIVESLAM_YOLO_IMAGE:-activeslam-yolo-gpu:r36.4}"
name=activeslam-yolo-gpu
port="${ACTIVESLAM_YOLO_PORT:-8765}"
models="$repo/src/kr_3d_active_ms_slam/semantic_detection/rgb_sem_segmentation/models"

case "${1:-start}" in
  build)
    shift
    docker build -f "$repo/docker/yolo_gpu/Dockerfile" -t "$image" "$@" "$repo/docker/yolo_gpu"
    ;;
  start)
    [[ -f "$models/yolov8x-seg.pt" ]] || { echo "Missing $models/yolov8x-seg.pt; run scripts/download_models.sh"; exit 1; }
    docker image inspect "$image" >/dev/null 2>&1 || { echo "Image $image not found. Run: docker/yolo_gpu.sh build"; exit 1; }
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" --runtime nvidia --network host --ipc host \
      --restart unless-stopped \
      -v "$models:/models:ro" \
      "$image" python3 /opt/yolo_server.py --model /models/yolov8x-seg.pt --port "$port"
    echo "Started $name on 127.0.0.1:$port. Waiting for warm-up..."
    for _ in $(seq 1 120); do
      if docker logs "$name" 2>&1 | grep -q 'Listening on'; then
        docker logs "$name" 2>&1 | grep -E 'CUDA available|Warm-up|Listening'; exit 0
      fi
      if docker logs "$name" 2>&1 | grep -q 'Traceback'; then
        echo "Server exited:"; docker logs "$name" 2>&1 | tail -20; exit 1
      fi
      sleep 2
    done
    echo "Still warming up; check: docker/yolo_gpu.sh logs"
    ;;
  stop)   docker rm -f "$name" ;;
  logs)   docker logs -f "$name" ;;
  status) docker ps -a -f "name=^${name}$" --format '{{.Names}}: {{.Status}}' ;;
  *) echo "usage: $0 build|start|stop|logs|status"; exit 1 ;;
esac
