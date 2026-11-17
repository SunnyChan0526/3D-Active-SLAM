#!/usr/bin/env bash
# Run as the normal desktop user. Only apt operations use sudo.
set -eEo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec > >(tee -a "$setup_dir/install_project_deps.log") 2>&1
trap 'code=$?; echo "FAILED at line $LINENO (exit $code). See $setup_dir/install_project_deps.log"; exit "$code"' ERR
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 20.04 ]] || { echo 'Requires Ubuntu 20.04'; exit 1; }
[[ "$EUID" != 0 ]] || { echo 'Run using bash, without sudo.'; exit 1; }
source /opt/ros/noetic/setup.bash
prefix="$HOME/.local/opt/active-slam"
sources="$HOME/active_slam_dependencies"
jobs="${ACTIVE_SLAM_JOBS:-2}"
mkdir -p "$prefix" "$sources"
export CMAKE_PREFIX_PATH="$prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$prefix/lib:$prefix/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
sudo -v
sudo apt-get update
sudo apt-get install -y build-essential cmake git pkg-config python3-venv \
  libeigen3-dev libboost-all-dev libsuitesparse-dev libatlas-base-dev \
  libgoogle-glog-dev libgflags-dev libompl-dev libnlopt-dev libnlopt-cxx-dev \
  libqhull-dev libdw-dev libgtest-dev libarmadillo-dev libusb-1.0-0-dev \
  libssl-dev libgtk-3-dev libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev \
  ros-noetic-ddynamic-reconfigure ros-noetic-librealsense2 ros-noetic-mavros-msgs \
  ros-noetic-ros-numpy tmux

# Noetic provides SDK 2.50.0, also present in the source machine's package list.
# Do not install a second apt ROS wrapper or mix SDK versions during this build.
dpkg-query -W ros-noetic-librealsense2

checkout() {
  local name="$1" url="$2" ref="$3" dir="$sources/$1"
  if [[ ! -e "$dir" ]]; then
    git clone "$url" "$dir"
  fi
  [[ -d "$dir/.git" ]] || { echo "Not a git checkout: $dir"; return 1; }
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]]; then
    echo "Preserving modified source: $dir"; return 1
  fi
  git -C "$dir" checkout --detach "$ref"
  git -C "$dir" rev-parse HEAD
}
build_install() {
  local name="$1"; shift
  cmake -S "$sources/$name" -B "$sources/$name-build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_POSITION_INDEPENDENT_CODE=ON "$@"
  cmake --build "$sources/$name-build" --parallel "$jobs"
  cmake --install "$sources/$name-build"
}

checkout fmt https://github.com/fmtlib/fmt.git 8.0.0
build_install fmt -DFMT_TEST=OFF -DFMT_DOC=OFF -DBUILD_SHARED_LIBS=ON
checkout glog https://github.com/google/glog.git v0.6.0
build_install glog -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=ON
checkout ceres https://ceres-solver.googlesource.com/ceres-solver 206061a6ba02dc91286b18da48825f7a9ef561f0
build_install ceres -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=ON
checkout Sophus https://github.com/strasdat/Sophus.git 49a7e1286910019f74fb4f0bb3e213c909f8e1b7
build_install Sophus -DBUILD_SOPHUS_TESTS=OFF -DBUILD_SOPHUS_EXAMPLES=OFF
checkout gtsam https://github.com/borglab/gtsam.git 4.0.3
build_install gtsam -DGTSAM_BUILD_TESTS=OFF -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
  -DGTSAM_BUILD_WRAP=OFF -DGTSAM_BUILD_UNSTABLE=ON \
  -DGTSAM_USE_SYSTEM_EIGEN=ON -DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF

# Explicit exceptions, checked against the packaged source:
# ceres: provided by the pinned source build above (no rosdep key).
# rosflight_msgs: optional flight interface; CMake omits it when absent.
# vikit_ros: stale local_sensing manifest entry, unused by source and CMake.
# librealsense2: provided by ros-noetic-librealsense2 above.
# glog: provided by the pinned glog source build above.
# Eigen: nonstandard key spelling; libeigen3-dev is installed above.
# svo_msgs: stale local_sensing manifest entry, unused by source and CMake.
rosdep install --from-paths "$HOME/realsense_ws/src" "$HOME/vins_ws/src" \
  "$HOME/active_ms_slam_ws/src" --ignore-src --rosdistro noetic -y \
  --skip-keys 'ceres rosflight_msgs vikit_ros librealsense2 glog Eigen svo_msgs'

printf '\nC++ dependencies installed into %s\n' "$prefix"
echo 'Next: run build_workspaces.sh. Hardware drivers and Python runtime checks are separate from compilation.'
