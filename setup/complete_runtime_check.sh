#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
exec > >(tee "$setup_dir/complete_runtime_check.log") 2>&1
export PYTHONUNBUFFERED=1
python - <<'PY'
import time
import rospy
from sensor_msgs.msg import Imu
rospy.init_node('migration_imu_health_check',anonymous=True,disable_signals=True)
assert rospy.get_param('/planning_preview_node/fsm/planning_only') is True
samples=[]
sub=rospy.Subscriber('/camera/imu',Imu,lambda msg:samples.append(time.monotonic()),queue_size=100)
end=time.monotonic()+8
while time.monotonic()<end and not rospy.is_shutdown():
    time.sleep(.1)
if len(samples)<2:
    raise SystemExit('IMU messages missing; inspect the camera Motion Module warning before continuing.')
print('IMU: {:.2f} Hz; planning_only=true'.format((len(samples)-1)/(samples[-1]-samples[0])))
PY
nodes="$(rosnode list)"
if printf '%s\n' "$nodes" | grep -qx '/loop_closure_server_node'; then
  echo 'Loop closure server already running; preserved.'
else
  echo 'Starting missing loop closure server. No planning trigger is sent.'
  exec roslaunch loop_closure loop_closure_node.launch
fi
