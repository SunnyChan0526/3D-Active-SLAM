#!/usr/bin/env bash
# Build / start the ActiveSLAM Docker container (Ubuntu 20.04 + ROS Noetic).
#
#   docker/run.sh build            build the image (first time, ~30-60 min)
#   docker/run.sh                  open a shell (attaches if already running)
#   docker/run.sh <cmd> [args...]  run a command, e.g.
#                                  docker/run.sh bash setup/start_all_planning_only.sh
#
# Env overrides:
#   ACTIVESLAM_IMAGE   image tag              (default activeslam:noetic)
#   ACTIVESLAM_GPU     auto | on | off        (default auto: use NVIDIA if available)
#   ACTIVESLAM_CAMERA_ALIGN RealSense driver align_depth (default true; false on Jetson)
#   ACTIVESLAM_COLOR_FPS  RealSense color fps (default 30; 15 on Jetson)
#   ACTIVESLAM_RVIZ_PREFIX launch-prefix for RViz (Jetson default: nice -n 19)
#   ACTIVESLAM_JOBS    parallel jobs for image build (default 4)
#   TORCH_VARIANT      cpu | cu121 for image build   (default cpu)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${ACTIVESLAM_IMAGE:-activeslam:noetic}"
name=activeslam
cuser=evil1323                       # fixed container user, see Dockerfile
chome="/home/$cuser"
crepo="$chome/Desktop/ActiveSLAM_move2Laptop"

command -v docker >/dev/null || { echo "docker not installed. See docker/README.md."; exit 1; }

if [[ "${1:-}" == build ]]; then
  shift
  # Minimal build context (package manifests + entrypoint). Assembled by hand
  # because the legacy builder (no buildx) mis-handles the !src/**/package.xml
  # exceptions in .dockerignore and sends an empty src/.
  ctx="$(mktemp -d)"
  trap 'rm -rf "$ctx"' EXIT
  (cd "$repo" && find src \( -name package.xml -o -name CATKIN_IGNORE \) \
      -exec cp --parents {} "$ctx" \; && cp --parents docker/entrypoint.sh "$ctx")
  docker build -f "$repo/docker/Dockerfile" -t "$image" \
    --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" \
    --build-arg JOBS="${ACTIVESLAM_JOBS:-4}" \
    --build-arg TORCH_VARIANT="${TORCH_VARIANT:-cpu}" \
    "$@" "$ctx"
  exit $?
fi

# Jetson: prefer the librealsense 2.54 image (docker/Dockerfile.rs) when it
# exists, and run color at 15 fps so align_depth keeps up on the CPU.
if [[ -f /etc/nv_tegra_release ]]; then
  if [[ -z "${ACTIVESLAM_IMAGE:-}" ]] && docker image inspect activeslam:noetic-rs254 >/dev/null 2>&1; then
    image=activeslam:noetic-rs254
  fi
  : "${ACTIVESLAM_COLOR_FPS:=15}"
  # The driver's CPU align_depth stalls the depth/infra USB stream here; use
  # depth_image_proc in its own process instead (setup/depth_register.launch).
  : "${ACTIVESLAM_CAMERA_ALIGN:=false}"
  # RViz renders on the CPU here (llvmpipe) and starves the RealSense nodelet
  # (infra/IMU stop at startup); run it at the lowest priority.
  : "${ACTIVESLAM_RVIZ_PREFIX=nice -n 19}"
fi

tty_args=(-i)
[[ -t 0 && -t 1 ]] && tty_args=(-it)
(( $# )) || set -- bash
# Commands run from the repo root, so relative paths like setup/... work.
wrapped=(bash -c 'cd "$0" && exec "$@"' "$crepo" "$@")

# Jetson: semantic YOLO goes to the GPU server from docker/yolo_gpu.sh
# (detect.py falls back to CPU if it is not running). Empty = always local.
if [[ -z "${ACTIVESLAM_YOLO_SERVER+x}" && -f /etc/nv_tegra_release ]]; then
  ACTIVESLAM_YOLO_SERVER=127.0.0.1:8765
  docker ps -q -f "name=^activeslam-yolo-gpu$" | grep -q . ||
    echo "NOTE: GPU YOLO server not running (docker/yolo_gpu.sh start); semantic YOLO will use CPU."
fi
yolo_env=(-e ACTIVESLAM_YOLO_SERVER="${ACTIVESLAM_YOLO_SERVER:-}")
if [[ -n "${ACTIVESLAM_RVIZ_PREFIX:-}" ]]; then
  yolo_env+=(-e ACTIVESLAM_RVIZ_PREFIX="$ACTIVESLAM_RVIZ_PREFIX")
fi
if [[ -n "${ACTIVESLAM_CAMERA_ALIGN:-}" ]]; then
  yolo_env+=(-e ACTIVESLAM_CAMERA_ALIGN="$ACTIVESLAM_CAMERA_ALIGN")
fi
if [[ -n "${ACTIVESLAM_COLOR_FPS:-}" ]]; then
  yolo_env+=(-e ACTIVESLAM_COLOR_FPS="$ACTIVESLAM_COLOR_FPS")
fi

# Already running -> open another shell / run the command in it.
if [[ -n "$(docker ps -q -f "name=^${name}$")" ]]; then
  exec docker exec "${tty_args[@]}" -e DISPLAY="${DISPLAY:-}" "${yolo_env[@]}" "$name" \
    /usr/local/bin/activeslam-entrypoint "${wrapped[@]}"
fi

docker image inspect "$image" >/dev/null 2>&1 || {
  echo "Image $image not found. Run: docker/run.sh build"; exit 1; }

# --- X11 for RViz -----------------------------------------------------------
x_args=()
if [[ -n "${DISPLAY:-}" ]]; then
  if command -v xhost >/dev/null; then
    # Allow only this host user's UID (the container user shares it).
    xhost +SI:localuser:"$(id -un)" >/dev/null || echo "WARNING: xhost failed; RViz may not open."
  else
    echo "WARNING: xhost not found (sudo apt install x11-xserver-utils); RViz may not open."
  fi
  x_args+=(-e DISPLAY="$DISPLAY" -e QT_X11_NO_MITSHM=1 -v /tmp/.X11-unix:/tmp/.X11-unix:rw)
  if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
    x_args+=(-e XAUTHORITY=/tmp/.host_Xauthority -v "$XAUTHORITY:/tmp/.host_Xauthority:ro")
  fi
else
  echo "NOTE: DISPLAY not set; RViz will not open (start from a desktop terminal)."
fi

# --- GPU ----------------------------------------------------------------------
gpu_args=()
case "${ACTIVESLAM_GPU:-auto}" in
  on)  gpu_args=(--gpus all) ;;
  off) ;;
  auto)
    # Jetson: the nvidia runtime injects host L4T libs built for the host's
    # Ubuntu, which do not match this 20.04 image, so stay on CPU/Mesa.
    if [[ -f /etc/nv_tegra_release ]]; then
      echo "Jetson host detected: GPU passthrough off (set ACTIVESLAM_GPU=on to try)."
    elif docker info 2>/dev/null | grep -qi 'nvidia'; then
      gpu_args=(--gpus all)
    fi ;;
esac
if (( ${#gpu_args[@]} )); then
  gpu_args+=(-e NVIDIA_DRIVER_CAPABILITIES=all -e NVIDIA_VISIBLE_DEVICES=all)
  echo "Using NVIDIA GPU."
fi

mkdir -p "$HOME/vins_output/pose_graph"

# --privileged + /dev + /run/udev: RealSense D435i (USB re-enumerates on reset,
#   so a single --device is not enough).
# --network host: ROS master/topics reachable from host and other machines.
# Named volumes keep catkin build/devel/logs between container runs.
exec docker run --rm "${tty_args[@]}" --name "$name" \
  --privileged -v /dev:/dev -v /run/udev:/run/udev:ro \
  --network host --ipc host \
  "${x_args[@]}" "${gpu_args[@]}" "${yolo_env[@]}" \
  -v "$repo:$crepo" \
  -v "$HOME/vins_output:$chome/vins_output" \
  -v activeslam_realsense_ws:"$chome/realsense_ws" \
  -v activeslam_vins_ws:"$chome/vins_ws" \
  -v activeslam_active_ms_slam_ws:"$chome/active_ms_slam_ws" \
  "$image" "${wrapped[@]}"
