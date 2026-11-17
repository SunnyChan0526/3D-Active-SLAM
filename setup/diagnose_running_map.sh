#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
exec > >(tee "$setup_dir/running_map_diagnosis.log") 2>&1
rosnode list
python - <<'PY'
import time
import rospy
from nav_msgs.msg import Odometry
rospy.init_node('migration_map_diagnosis',anonymous=True,disable_signals=True)
prefix='/planning_preview_node/'
print('planning_only:',rospy.get_param(prefix+'fsm/planning_only'))
bounds=rospy.get_param(prefix+'map_ros/global')
for key,value in sorted(bounds.items()):
    if 'boundary' in key:
        print(key,value)
topics=['/vins_estimator/odometry','/factor_graph_atl/quadrotor/high_freq_odom']
data={topic:[] for topic in topics}
def record(msg,topic):
    p=msg.pose.pose.position
    data[topic].append((time.monotonic(),p.x,p.y,p.z,msg.header.frame_id))
subs=[rospy.Subscriber(t,Odometry,record,callback_args=t,queue_size=10) for t in topics]
end=time.monotonic()+8
while time.monotonic()<end and not rospy.is_shutdown():
    time.sleep(.1)
for topic,samples in data.items():
    print('\nTOPIC',topic,'samples',len(samples))
    if samples:
        print('last xyz/frame:',samples[-1][1:])
        print('z range:',min(s[3] for s in samples),max(s[3] for s in samples))
        if len(samples)>1:
            print('rate:',(len(samples)-1)/(samples[-1][0]-samples[0][0]))
print('Read-only diagnosis finished; no parameters or planning triggers were changed.')
PY
