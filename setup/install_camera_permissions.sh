#!/usr/bin/env bash
# Install official rules matching the ROS SDK 2.50.0; no camera nodes are started.
set -eEuo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec > >(tee -a "$setup_dir/install_camera_permissions.log") 2>&1
rules_dir="$(mktemp -d)"
trap 'rm -rf "$rules_dir"' EXIT
curl --fail --show-error --location --retry 3 \
  https://raw.githubusercontent.com/realsenseai/librealsense/v2.50.0/config/99-realsense-libusb.rules \
  -o "$rules_dir/99-realsense-libusb.rules"
test -s "$rules_dir/99-realsense-libusb.rules"
grep -Fq 'ATTRS{idVendor}=="8086"' "$rules_dir/99-realsense-libusb.rules"
target=/etc/udev/rules.d/99-realsense-libusb.rules
if [[ -f "$target" ]] && ! cmp -s "$target" "$rules_dir/99-realsense-libusb.rules"; then
  echo "Different existing rules preserved: $target. Please report this message."
  exit 1
fi
sudo install -m 0644 "$rules_dir/99-realsense-libusb.rules" "$target"
sudo udevadm control --reload-rules
cp "$rules_dir/99-realsense-libusb.rules" "$setup_dir/99-realsense-libusb.rules"
sha256sum "$setup_dir/99-realsense-libusb.rules"
echo 'Camera access rules installed. Reconnect the camera before later hardware validation.'
