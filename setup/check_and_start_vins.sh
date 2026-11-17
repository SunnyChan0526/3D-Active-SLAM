#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
exec > >(tee -a "$setup_dir/vins_hardware_check.log") 2>&1
export PYTHONUNBUFFERED=1
echo "Hardware check started: $(date --iso-8601=seconds)"
rosnode list > /dev/null || { echo 'ROS master unavailable. Keep the camera launch running first.'; exit 1; }
python - <<'PY'
import time
import rospy
from sensor_msgs.msg import Image
rospy.init_node('migration_image_check', anonymous=True, disable_signals=True)
topics=['/camera/infra1/image_rect_raw','/camera/infra2/image_rect_raw']
samples={t:[] for t in topics}
def record(msg, topic):
    samples[topic].append(time.monotonic())
subs=[rospy.Subscriber(t,Image,record,callback_args=t,queue_size=1) for t in topics]
end=time.monotonic()+8
while time.monotonic()<end and not rospy.is_shutdown():
    time.sleep(0.1)
for topic,times in samples.items():
    if len(times)<2:
        raise SystemExit('No usable image stream: '+topic)
    print('{}: {:.2f} Hz ({} frames)'.format(topic,(len(times)-1)/(times[-1]-times[0]),len(times)))
PY
nodes="$(rosnode list)"
vins_pid=''
cleanup() {
  if [[ -n "$vins_pid" ]]; then
    kill -INT "$vins_pid" 2>/dev/null || true
    wait "$vins_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM
if printf '%s\n' "$nodes" | grep -Eq '(^|/)vins_estimator$'; then
  echo 'Existing VINS estimator preserved; checking its odometry.'
else
  echo 'Starting VINS. Slowly move and rotate the camera in a well-lit, textured scene.'
  rosrun vins vins_node "$HOME/vins_ws/src/VINS-Fusion/config/realsense_d435i_sunny/realsense_stereo_imu_config.yaml" &
  vins_pid=$!
fi
python - <<'PY'
import time
import rospy
from nav_msgs.msg import Odometry
rospy.init_node('migration_vins_odom_check',anonymous=True,disable_signals=True)
samples=[]
def record(msg):
    samples.append((time.monotonic(),msg))
sub=rospy.Subscriber('/vins_estimator/odometry',Odometry,record,queue_size=10)
deadline=time.monotonic()+90
while not rospy.is_shutdown():
    now=time.monotonic()
    if samples and now-samples[0][0]>=8:
        break
    if now>=deadline:
        raise SystemExit('Odometry check timed out. Inspect VINS initialization messages in this log.')
    time.sleep(0.1)
if len(samples)<2:
    raise SystemExit('Insufficient odometry messages.')
rate=(len(samples)-1)/(samples[-1][0]-samples[0][0])
msg=samples[-1][1]
print('VINS odometry: {:.2f} Hz; frame: {}'.format(rate,msg.header.frame_id))
print('This checks message publication; pose accuracy still requires visual validation.')
PY
if [[ -n "$vins_pid" ]]; then
  echo 'Checks completed. VINS remains running in this terminal; Ctrl+C stops this VINS instance.'
  wait "$vins_pid"
fi
