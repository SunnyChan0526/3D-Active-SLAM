# ActiveSLAM runtime image: Ubuntu 20.04 + ROS Noetic + pinned C++/Python deps.
# Mirrors setup/install_ros_base.sh, setup/install_project_deps.sh and
# setup/install_python_runtime.sh so the container matches the validated laptop.
#
# The repo itself is NOT baked in: docker/run.sh bind-mounts it at the same
# path as on the dev laptop, and the catkin workspaces are built inside the
# container with setup/build_workspaces.sh (outputs live in named volumes).
#
# Build from the repo root (docker/run.sh build does this for you):
#   docker build -f docker/Dockerfile -t activeslam:noetic \
#     --build-arg UID=$(id -u) --build-arg GID=$(id -g) .

FROM ubuntu:20.04

# The container user is always "evil1323" so the absolute paths in the VINS
# config (/home/evil1323/vins_output/...) keep working on any host. UID/GID
# should match the host user so files written into the bind-mounted repo are
# owned by you.
ARG USERNAME=evil1323
ARG UID=1000
ARG GID=1000
ARG JOBS=4
# cpu (validated on the laptop) or cu121 (needs NVIDIA driver >= 530 and
# nvidia-container-toolkit on the host).
ARG TORCH_VARIANT=cpu

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Asia/Taipei

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# ROS Noetic from the official final snapshot (Noetic is EOL; same source as
# setup/install_ros_base.sh).
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg dirmngr tzdata locales \
    && key_fingerprint=4B63CF8FDE49746E98FA01DDAD19BAB3CBF125EA \
    && key_dir="$(mktemp -d)" \
    && gpg --homedir "$key_dir" --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$key_fingerprint" \
    && gpg --homedir "$key_dir" --batch --export "$key_fingerprint" > /usr/share/keyrings/ros1-snapshots-archive-keyring.gpg \
    && test -s /usr/share/keyrings/ros1-snapshots-archive-keyring.gpg \
    && rm -rf "$key_dir" \
    && echo 'deb [signed-by=/usr/share/keyrings/ros1-snapshots-archive-keyring.gpg] http://snapshots.ros.org/noetic/final/ubuntu focal main' \
         > /etc/apt/sources.list.d/ros1-snapshots.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      ros-noetic-desktop-full python3-catkin-tools python3-rosdep \
      build-essential cmake git pkg-config python3-pip python3-venv python-is-python3 \
      libeigen3-dev libboost-all-dev libsuitesparse-dev libatlas-base-dev \
      libgoogle-glog-dev libgflags-dev libompl-dev libnlopt-dev libnlopt-cxx-dev \
      libqhull-dev libdw-dev libgtest-dev libarmadillo-dev libusb-1.0-0-dev \
      libssl-dev libgtk-3-dev libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev \
      ros-noetic-ddynamic-reconfigure ros-noetic-librealsense2 ros-noetic-mavros-msgs \
      ros-noetic-ros-numpy \
      sudo tmux nano less usbutils mesa-utils \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# rosdep system dependencies of the three workspaces. Only package.xml /
# CATKIN_IGNORE files are in the build context (see .dockerignore).
# Skip keys are the same explicit exceptions as setup/install_project_deps.sh.
# ---------------------------------------------------------------------------
COPY src /tmp/rosdep_src
RUN rosdep init \
    && rosdep update --include-eol-distros --rosdistro noetic \
    && apt-get update \
    && rosdep install --from-paths /tmp/rosdep_src --ignore-src --rosdistro noetic -y \
         --skip-keys 'ceres rosflight_msgs vikit_ros librealsense2 glog Eigen svo_msgs' \
    && rm -rf /var/lib/apt/lists/* /tmp/rosdep_src

# ---------------------------------------------------------------------------
# Non-root user matching the host UID/GID, passwordless sudo inside container.
# ---------------------------------------------------------------------------
RUN groupadd -g "$GID" "$USERNAME" 2>/dev/null || true \
    && useradd -m -u "$UID" -g "$GID" -s /bin/bash "$USERNAME" \
    && usermod -aG sudo,plugdev,video,dialout "$USERNAME" \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$USERNAME \
    && chmod 0440 /etc/sudoers.d/90-$USERNAME

USER $USERNAME
WORKDIR /home/$USERNAME
ENV HOME=/home/$USERNAME

# rosdep cache for the user too (catkin/rosdep commands run as the user).
RUN rosdep update --include-eol-distros --rosdistro noetic

# ---------------------------------------------------------------------------
# Pinned source-built C++ deps into ~/.local/opt/active-slam (same prefix and
# versions as setup/install_project_deps.sh, so build_workspaces.sh and
# source_active_slam.bash work unchanged).
# ---------------------------------------------------------------------------
RUN set -e; \
    prefix="$HOME/.local/opt/active-slam"; srcs=/tmp/deps; mkdir -p "$prefix" "$srcs"; \
    source /opt/ros/noetic/setup.bash; \
    export CMAKE_PREFIX_PATH="$prefix:$CMAKE_PREFIX_PATH" LD_LIBRARY_PATH="$prefix/lib:$LD_LIBRARY_PATH"; \
    fetch() { git clone --quiet "$2" "$srcs/$1" && git -C "$srcs/$1" checkout --quiet --detach "$3"; }; \
    build() { n="$1"; shift; \
      cmake -S "$srcs/$n" -B "$srcs/$n-build" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$prefix" -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON "$@"; \
      cmake --build "$srcs/$n-build" --parallel "$JOBS"; \
      cmake --install "$srcs/$n-build"; rm -rf "$srcs/$n" "$srcs/$n-build"; }; \
    fetch fmt https://github.com/fmtlib/fmt.git 8.0.0; \
    build fmt -DFMT_TEST=OFF -DFMT_DOC=OFF -DBUILD_SHARED_LIBS=ON; \
    fetch glog https://github.com/google/glog.git v0.6.0; \
    build glog -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=ON; \
    fetch ceres https://ceres-solver.googlesource.com/ceres-solver 206061a6ba02dc91286b18da48825f7a9ef561f0; \
    build ceres -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DBUILD_SHARED_LIBS=ON; \
    fetch Sophus https://github.com/strasdat/Sophus.git 49a7e1286910019f74fb4f0bb3e213c909f8e1b7; \
    build Sophus -DBUILD_SOPHUS_TESTS=OFF -DBUILD_SOPHUS_EXAMPLES=OFF; \
    fetch gtsam https://github.com/borglab/gtsam.git 4.0.3; \
    build gtsam -DGTSAM_BUILD_TESTS=OFF -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
      -DGTSAM_BUILD_WRAP=OFF -DGTSAM_BUILD_UNSTABLE=ON \
      -DGTSAM_USE_SYSTEM_EIGEN=ON -DGTSAM_BUILD_WITH_MARCH_NATIVE=OFF; \
    rm -rf "$srcs"

# ---------------------------------------------------------------------------
# Python runtime venv (same path and pins as setup/install_python_runtime.sh).
# ---------------------------------------------------------------------------
RUN set -e; \
    runtime="$HOME/.local/opt/active-slam-python"; \
    /usr/bin/python3 -m venv --system-site-packages "$runtime"; \
    py="$runtime/bin/python"; \
    "$py" -m pip install --no-cache-dir 'pip==24.3.1' 'setuptools==75.3.2' 'wheel==0.45.1'; \
    "$py" -m pip install --no-cache-dir "torch==2.4.1+${TORCH_VARIANT}" "torchvision==0.19.1+${TORCH_VARIANT}" \
      --index-url "https://download.pytorch.org/whl/${TORCH_VARIANT}"; \
    "$py" -m pip install --no-cache-dir 'numpy==1.23.5' 'scipy==1.10.1' \
      'scikit-learn==1.3.2' 'pandas==2.0.3' 'matplotlib==3.7.5' \
      'opencv-python==4.10.0.84' 'open3d==0.13.0' 'ultralytics==8.0.38' \
      'testresources==2.0.1'; \
    source /opt/ros/noetic/setup.bash; \
    "$py" -c "import rospy, tf, cv_bridge, ros_numpy, numpy, scipy, sklearn, open3d, cv2, torch, torchvision; from ultralytics import YOLO; print('Python imports OK, torch', torch.__version__)"

# ---------------------------------------------------------------------------
# Catkin workspace skeletons. src/ entries are symlinks into the bind-mounted
# repo (same layout as the README "Fresh clone" section). docker/run.sh mounts
# named volumes over these dirs so build/devel survive container restarts;
# Docker seeds a new volume from this image content (incl. ownership).
# ---------------------------------------------------------------------------
RUN set -e; repo="$HOME/Desktop/ActiveSLAM_move2Laptop"; \
    mkdir -p "$HOME/Desktop" "$HOME/vins_output/pose_graph"; \
    for pair in realsense_ws:realsense-ros vins_ws:VINS-Fusion active_ms_slam_ws:kr_3d_active_ms_slam; do \
      ws="${pair%%:*}"; pkg="${pair##*:}"; mkdir -p "$HOME/$ws/src"; \
      ln -s "$repo/src/$pkg" "$HOME/$ws/src/$pkg"; \
    done

COPY --chown=$UID:$GID docker/entrypoint.sh /usr/local/bin/activeslam-entrypoint
RUN echo 'source /usr/local/bin/activeslam-entrypoint' >> "$HOME/.bashrc"
ENV ACTIVESLAM_QUIET=1
ENTRYPOINT ["/usr/local/bin/activeslam-entrypoint"]
CMD ["bash"]
