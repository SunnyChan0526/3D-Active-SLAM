#!/usr/bin/env python3
"""Read-only checks for a running preview (no service calls, no commands)."""
import math
import rosgraph
import rospy
from visualization_msgs.msg import MarkerArray
from std_msgs.msg import String


def main():
    rospy.init_node('check_preview_contract', anonymous=True)
    assert rospy.get_param('/planning_preview_node/fsm/planning_only') is True
    master = rosgraph.Master(rospy.get_name())
    pubs, subs, services = master.getSystemState()
    owned = [topic for topic, nodes in pubs if '/planning_preview_node' in nodes]
    assert '/vins_estimator/odometry' not in owned
    assert '/tf' not in owned and '/tf_static' not in owned
    allowed = ('/planning_preview/', '/planning_preview_node/', '/rosout')
    cop_topics = {'/exploration/global_plan_server/goal', '/exploration/global_plan_server/cancel'}
    assert all(topic.startswith(allowed) or topic in cop_topics for topic in owned), owned
    status = rospy.wait_for_message('/planning_preview/status', String, timeout=5).data
    markers = rospy.wait_for_message('/planning_preview/markers', MarkerArray, timeout=5)
    active = {(m.ns, m.id): m for m in markers.markers if m.action == m.ADD}
    assert len(active) == len(set(active))
    for marker in active.values():
        assert marker.header.frame_id == 'world'
        assert all(math.isfinite(v) for point in marker.points for v in (point.x, point.y, point.z))
    assert ('status', 0) in active
    assert 'NO UAV EXECUTION' in active[('status', 0)].text
    print('PASS: preview topics isolated, no VINS/TF publishers, finite world-frame markers')
    print('Status:', status)
    print('Markers:', list(active))


if __name__ == '__main__':
    main()
