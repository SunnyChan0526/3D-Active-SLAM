#!/usr/bin/env bash
set -euo pipefail
source /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 20.04 ]] || { echo 'Requires Ubuntu 20.04'; exit 1; }
log_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$log_dir"
exec > >(tee -a "$log_dir/install_ros_base.log") 2>&1
sudo -v
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg dirmngr build-essential cmake git pkg-config python3-pip python3-venv
key_fingerprint=4B63CF8FDE49746E98FA01DDAD19BAB3CBF125EA
key_dir="$(mktemp -d)"
trap 'rm -rf "$key_dir"' EXIT
chmod 700 "$key_dir"
gpg --homedir "$key_dir" --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$key_fingerprint"
gpg --homedir "$key_dir" --batch --export "$key_fingerprint" > "$key_dir/ros1-snapshots.gpg"
test -s "$key_dir/ros1-snapshots.gpg"
sudo install -m 0644 "$key_dir/ros1-snapshots.gpg" /usr/share/keyrings/ros1-snapshots-archive-keyring.gpg
source_line='deb [signed-by=/usr/share/keyrings/ros1-snapshots-archive-keyring.gpg] http://snapshots.ros.org/noetic/final/ubuntu focal main'
source_file=/etc/apt/sources.list.d/ros1-snapshots.list
if sudo test -e "$source_file"; then
  existing="$(sudo cat "$source_file")"
  [[ "$existing" == "$source_line" ]] || { echo "Existing $source_file differs; preserved. Please report this message."; exit 1; }
else
  printf '%s\n' "$source_line" | sudo tee "$source_file"
fi
sudo apt-get update
sudo apt-get install -y ros-noetic-desktop-full python3-catkin-tools python3-rosdep
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  sudo rosdep init
fi
rosdep update --include-eol-distros --rosdistro noetic
set +u
source /opt/ros/noetic/setup.bash
set -u
rosversion -d
catkin --version
echo 'ROS base installation completed. RealSense SDK and project dependencies still require installation before building.'
