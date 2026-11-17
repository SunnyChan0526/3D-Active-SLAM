#!/usr/bin/env bash
# Stop only the known nodes in this migration setup; preserve ROS master/files.
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
python - <<'PY'
import time
import socket
import errno
from xmlrpc.client import ServerProxy
import rosnode
import rosgraph
known={
    '/exploration_node','/planning_preview_node','/rvizvisualisation',
    '/planning_preview_rviz','/global_plan_server_node','/process_cloud_node',
    '/rgb_sem_segmentation','/active_slam_input_node','/loop_closure_server_node',
    '/vins_estimator','/camera/realsense2_camera','/camera/realsense2_camera_manager',
}
try:
    running=set(rosnode.get_node_names())
except rosnode.ROSNodeIOException:
    print('ROS master unavailable; nothing stopped.')
    raise SystemExit(0)
targets=sorted(known & running)
if targets:
    print('Stopping ActiveSLAM nodes:',', '.join(targets),flush=True)
    stopped,failed=rosnode.kill_nodes(targets)
    if failed:print('Shutdown requests failed:',failed)
deadline=time.monotonic()+10
while time.monotonic()<deadline:
    remaining=known & set(rosnode.get_node_names())
    if not remaining:
        print('ActiveSLAM nodes stopped. ROS master and saved files preserved.')
        break
    time.sleep(.25)
else:
    # Remove a leftover registration only when its XMLRPC port explicitly
    # refuses connections. A timeout may be a busy live process: preserve it.
    master=rosgraph.Master('/migration_stop_check')
    socket.setdefaulttimeout(3)
    stale=[]
    for node in sorted(remaining):
        try:
            api=master.lookupNode(node)
        except rosgraph.MasterError:
            continue
        try:
            with ServerProxy(api) as remote:
                remote.getPid('/migration_stop_check')
        except OSError as error:
            if error.errno==errno.ECONNREFUSED:
                stale.append(node)
            else:
                print('Node connectivity uncertain; preserved:',node,str(error))
        except Exception as error:
            print('Node shutdown uncertain; preserved:',node,str(error))
    if stale:
        rosnode.cleanup_master_blacklist(master,stale)
    remaining=known & set(rosnode.get_node_names())
    if remaining:
        raise SystemExit('Nodes still registered; press Ctrl+C in their original launch terminals: '+', '.join(sorted(remaining)))
    print('ActiveSLAM nodes stopped; stale registrations cleared. Saved files preserved.')
PY
