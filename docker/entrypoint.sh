#!/usr/bin/env bash
# ActiveSLAM container environment.
# Runs as the image ENTRYPOINT and is also sourced from ~/.bashrc, so every
# shell (including `docker exec` shells) gets ROS + workspaces + Python venv.
repo="$HOME/Desktop/ActiveSLAM_move2Laptop"
prefix="$HOME/.local/opt/active-slam"

# aarch64 (e.g. Jetson): torch and open3d fail with "libgomp...: cannot
# allocate memory in static TLS block" unless both torch's bundled libgomp and
# the system libgomp are preloaded (in that order).
if [[ "$(uname -m)" == aarch64 && ":${LD_PRELOAD:-}:" != *libgomp* ]]; then
  gomp_preload=
  for lib in "$prefix"-python/lib/python3.8/site-packages/torch.libs/libgomp-*.so* \
             /usr/lib/aarch64-linux-gnu/libgomp.so.1; do
    [[ -f "$lib" ]] && gomp_preload="${gomp_preload:+$gomp_preload:}$lib"
  done
  [[ -n "$gomp_preload" ]] && export LD_PRELOAD="$gomp_preload${LD_PRELOAD:+:$LD_PRELOAD}"
  unset gomp_preload lib
fi

if [[ ! -d "$repo/src" ]]; then
  echo "[activeslam] WARNING: repo not mounted at $repo (use docker/run.sh)." >&2
fi

if [[ -f "$HOME/active_ms_slam_ws/devel/setup.bash" && -f "$repo/setup/source_active_slam.bash" ]]; then
  # Workspaces already built: use the project's own env script.
  source "$repo/setup/source_active_slam.bash"
else
  source /opt/ros/noetic/setup.bash
  export CMAKE_PREFIX_PATH="$prefix${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
  export LD_LIBRARY_PATH="$prefix/lib:$prefix/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig:$prefix/lib64/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
  [[ -f "$prefix-python/bin/activate" ]] && source "$prefix-python/bin/activate"
  if [[ -z "${ACTIVESLAM_QUIET:-}" ]]; then
    echo "[activeslam] Workspaces not built yet. Run once:"
    echo "    ACTIVE_SLAM_JOBS=4 bash ~/Desktop/ActiveSLAM_move2Laptop/setup/build_workspaces.sh"
    echo "  then open a new shell (or: source ~/Desktop/ActiveSLAM_move2Laptop/setup/source_active_slam.bash)."
  fi
fi

# Executed (not sourced): hand over to the requested command.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  export ACTIVESLAM_QUIET=
  exec "$@"
fi
