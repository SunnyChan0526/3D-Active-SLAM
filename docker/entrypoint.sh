#!/usr/bin/env bash
# ActiveSLAM container environment.
# Runs as the image ENTRYPOINT and is also sourced from ~/.bashrc, so every
# shell (including `docker exec` shells) gets ROS + workspaces + Python venv.
repo="$HOME/Desktop/ActiveSLAM_move2Laptop"
prefix="$HOME/.local/opt/active-slam"

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
