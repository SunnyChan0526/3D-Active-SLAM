#!/usr/bin/env python3
"""Control only the offline preview; never publish vehicle commands."""
import argparse
import rospy
from std_srvs.srv import Trigger
from std_msgs.msg import String


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['start', 'pause', 'resume', 'stop', 'status'])
    args = parser.parse_args(rospy.myargv()[1:])
    rospy.init_node('planning_preview_control', anonymous=True)
    if not rospy.get_param('/planning_preview_node/fsm/planning_only', False):
        raise SystemExit('Preview requires /planning_preview_node/fsm/planning_only=true')
    if args.command == 'status':
        print(rospy.wait_for_message('/planning_preview/status', String, timeout=5).data)
        return
    name = '/planning_preview_node/' + args.command
    rospy.wait_for_service(name, timeout=30)
    result = rospy.ServiceProxy(name, Trigger)()
    print(result.message)
    if not result.success:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
