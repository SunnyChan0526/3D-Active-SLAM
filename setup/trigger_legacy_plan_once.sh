#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
exec > >(tee -a "$setup_dir/legacy_plan_trigger.log") 2>&1
python - <<'PY'
import time
import rospy
from nav_msgs.msg import Path
from geometry_msgs.msg import PoseStamped
rospy.init_node('legacy_plan_once_trigger',anonymous=True,disable_signals=True)
if rospy.get_param('/exploration_node/fsm/planning_only',False) is not True:
    raise SystemExit('Stopped: /exploration_node/fsm/planning_only must be true.')
topic='/sunny_mapping_test/disabled_waypoints'
code,message,state=rospy.get_master().getSystemState()
if code!=1 or '/exploration_node' not in dict(state[1]).get(topic,[]):
    raise SystemExit('Stopped: exploration_node is not subscribed to the expected trigger topic.')
pub=rospy.Publisher(topic,Path,queue_size=1,latch=False)
deadline=time.monotonic()+5
while pub.get_num_connections()==0 and time.monotonic()<deadline:
    time.sleep(.05)
if pub.get_num_connections()==0:
    raise SystemExit('Stopped: no connected trigger subscriber.')
if rospy.get_param('/exploration_node/fsm/planning_only',False) is not True:
    raise SystemExit('Stopped: planning_only changed.')
msg=Path()
msg.header.frame_id='world'
msg.header.stamp=rospy.Time.now()
pose=PoseStamped()
pose.header=msg.header
pose.pose.orientation.w=1.0
pose.pose.position.z=0.0
msg.poses=[pose]
pub.publish(msg)
time.sleep(.5)
print('Published one planning-only FSM trigger at',msg.header.stamp.to_sec(),'on',topic)
print('Inspect the planner log for Triggercallback and PLAN_BEHAVIOR. This message does not specify a destination.')
PY
