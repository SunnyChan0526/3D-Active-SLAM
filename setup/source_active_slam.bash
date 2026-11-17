# Source this file in each terminal used for ActiveSLAM.
# It only sets the environment; it does not start any ROS processes.
source /opt/ros/noetic/setup.bash
source "$HOME/realsense_ws/devel/setup.bash"
source "$HOME/vins_ws/devel/setup.bash" --extend
source "$HOME/active_ms_slam_ws/devel/setup.bash" --extend
export LD_LIBRARY_PATH="$HOME/.local/opt/active-slam/lib:$HOME/.local/opt/active-slam/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [[ -f "$HOME/.local/opt/active-slam-python/bin/activate" ]]; then
  source "$HOME/.local/opt/active-slam-python/bin/activate"
fi
