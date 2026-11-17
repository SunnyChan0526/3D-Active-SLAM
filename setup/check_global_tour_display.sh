#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
exec > >(tee "$setup_dir/global_tour_display_check.log") 2>&1
python - <<'PY'
import time
import rospy
from visualization_msgs.msg import Marker
rospy.init_node('global_tour_display_check',anonymous=True,disable_signals=True)
topic='/planning_vis/viewpoints'
code,message,state=rospy.get_master().getSystemState()
if code!=1:
    raise SystemExit(message)
print('Publishers:',dict(state[0]).get(topic,[]))
print('Subscribers:',dict(state[1]).get(topic,[]))
seen={}
def record(msg):
    seen[(msg.ns,msg.id)]=msg
sub=rospy.Subscriber(topic,Marker,record,queue_size=1000)
end=time.monotonic()+5
while time.monotonic()<end and not rospy.is_shutdown():
    time.sleep(.1)
for key,msg in sorted(seen.items()):
    print('Marker:',key,'frame:',msg.header.frame_id,'type:',msg.type,
          'action:',msg.action,'points:',len(msg.points),'alpha:',msg.color.a,
          'width:',msg.scale.x,'lifetime:',msg.lifetime.to_sec())
    if msg.ns=='global_tour' and msg.points:
        for axis in ['x','y','z']:
            values=[getattr(p,axis) for p in msg.points]
            print(axis,'range:',min(values),max(values))
if not any(k[0]=='global_tour' and m.action==Marker.ADD and len(m.points)>=2 for k,m in seen.items()):
    print('No drawable global_tour marker received during the check.')
print('Read-only display check finished; no planning trigger sent.')
PY
