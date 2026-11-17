#!/usr/bin/env bash
set -euo pipefail

# Export source/configuration and reproducibility manifests for a second Ubuntu
# machine. This script does not stop ROS, alter source files, or package build
# outputs, maps, credentials, or installed OS binaries.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_root="${1:?Usage: $0 OUTPUT_DIRECTORY}"
stamp="$(date +%Y%m%d_%H%M%S)"
bundle="${output_root%/}/kr3d_migration_${stamp}"

mkdir -p "$output_root"
mkdir "$bundle"

tar -czf "$bundle/active_ms_slam_source.tar.gz" \
  --exclude='*/__pycache__' --exclude='*.pyc' \
  -C "$(dirname "$repo_root")" "$(basename "$repo_root")"

if [[ -d "$HOME/vins_ws/src/VINS-Fusion" ]]; then
  tar -czf "$bundle/vins_fusion_source.tar.gz" \
    --exclude='*/__pycache__' --exclude='*.pyc' \
    -C "$HOME/vins_ws/src" VINS-Fusion
else
  echo "Missing $HOME/vins_ws/src/VINS-Fusion" >&2
  exit 1
fi

if [[ -d "$HOME/realsense_ws/src/realsense-ros" ]]; then
  tar -czf "$bundle/realsense_ros_source.tar.gz" \
    --exclude='*/__pycache__' --exclude='*.pyc' \
    -C "$HOME/realsense_ws/src" realsense-ros
else
  echo "Missing $HOME/realsense_ws/src/realsense-ros" >&2
  exit 1
fi

{
  echo "Created: $(date --iso-8601=seconds)"
  echo "Host: $(hostname)"
  echo "Kernel: $(uname -a)"
  echo
  cat /etc/os-release
  echo
  echo "ROS_DISTRO environment: ${ROS_DISTRO:-not-set-in-export-shell}"
  if command -v rosversion >/dev/null 2>&1; then rosversion -d; fi
  echo
  echo "=== Active workspace git status ==="
  git -C "$repo_root" status --short --branch
  git -C "$repo_root" rev-parse HEAD
  git -C "$repo_root" submodule status
  echo
  echo "=== VINS-Fusion git status ==="
  git -C "$HOME/vins_ws/src/VINS-Fusion" status --short --branch
  git -C "$HOME/vins_ws/src/VINS-Fusion" rev-parse HEAD
  echo
  echo "=== RealSense ROS git status ==="
  git -C "$HOME/realsense_ws/src/realsense-ros" status --short --branch
  git -C "$HOME/realsense_ws/src/realsense-ros" rev-parse HEAD
  echo
  echo "=== RealSense SDK ==="
  if command -v rs-enumerate-devices >/dev/null 2>&1; then
    rs-enumerate-devices --version 2>&1 || true
  fi
  dpkg-query -W -f='${binary:Package}\t${Version}\n' \
    'librealsense2*' 'ros-noetic-realsense2-camera*' 2>/dev/null || true
} > "$bundle/system_and_source_manifest.txt"

dpkg-query -W -f='${binary:Package}=${Version}\n' > "$bundle/dpkg_all_installed.txt"
apt-mark showmanual > "$bundle/apt_manual_packages.txt"
dpkg-query -W -f='${binary:Package}=${Version}\n' 'ros-noetic-*' 2>/dev/null \
  | sort > "$bundle/ros_noetic_packages.txt" || true
python3 -m pip freeze > "$bundle/python_pip_freeze.txt" 2>&1 || true

find "$HOME/vins_ws/src/VINS-Fusion/config/realsense_d435i_sunny" \
  -maxdepth 2 -type f -print 2>/dev/null \
  | sort > "$bundle/d435i_vins_config_file_list.txt"

cp "$repo_root/README.md" "$bundle/project_README.md"
cp "$repo_root/exploration_planner/planner/exploration_manager/docs/new_ubuntu_migration.md" \
  "$bundle/new_ubuntu_migration.md"
cp "$repo_root/exploration_planner/planner/exploration_manager/docs/planning_preview.md" \
  "$bundle/planning_preview.md"

(cd "$bundle" && sha256sum ./*.tar.gz > SHA256SUMS)
printf 'Migration bundle created at:\n%s\n' "$bundle"
printf 'Archives: active_ms_slam_source, vins_fusion_source, realsense_ros_source\n'
printf 'Review system_and_source_manifest.txt and SHA256SUMS before transfer.\n'
