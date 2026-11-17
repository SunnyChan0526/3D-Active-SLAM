#!/usr/bin/env python3
"""Terminal walking guide for handheld exploration.

Shows, relative to where the camera is pointing now, which way and how far the
current orange target is. Uses the same pose and heading the planner uses to
decide "reached": SLAM odometry (body x axis = camera forward) and the goal
marker on /planning_vis/handheld_goal (world frame, SLAM coordinates).
Reached = within 0.5 m and heading within ~11 deg, held for 1 s.
"""
import math
import sys
import time

import rospy
from nav_msgs.msg import Odometry
from visualization_msgs.msg import Marker

ODOM = '/factor_graph_atl/quadrotor/high_freq_odom'
GOAL = '/planning_vis/handheld_goal'
REACH_DIST = 0.5
REACH_YAW = math.degrees(0.2)

pose = None   # (x, y, z, yaw, wall time)
goal = None   # (x, y, z, yaw) or None when the planner deleted it


def yaw_from_quat(q):
    # Heading of the body x axis, identical to msExplorationFSM::odometryCallbackSlam.
    return math.atan2(2 * (q.x * q.y + q.z * q.w), 1 - 2 * (q.y * q.y + q.z * q.z))


def on_odom(msg):
    global pose
    p = msg.pose.pose.position
    pose = (p.x, p.y, p.z, yaw_from_quat(msg.pose.pose.orientation), time.monotonic())


def on_goal(msg):
    global goal
    if msg.action != Marker.ADD:
        goal = None
        return
    p = msg.pose.position
    # handheld_fsm.cpp draws SLC (clo) targets purple (no green), frontiers orange.
    is_slc = msg.color.b > 0.5 and msg.color.g < 0.2
    goal = (p.x, p.y, p.z, yaw_from_quat(msg.pose.orientation), is_slc)


def wrap_deg(a):
    return (a + 180.0) % 360.0 - 180.0


def direction_text(rel):
    """rel: target bearing relative to camera forward, degrees, + = left."""
    a = abs(rel)
    side = '左' if rel > 0 else '右'
    if a < 20:
        return '↑', '正前方'
    if a < 70:
        return ('↖' if rel > 0 else '↗'), side + '前方 {:.0f}°'.format(a)
    if a < 110:
        return ('←' if rel > 0 else '→'), side + '邊 {:.0f}°'.format(a)
    if a < 160:
        return ('↙' if rel > 0 else '↘'), side + '後方 {:.0f}°'.format(a)
    return '↓', '正後方'


def render():
    if pose is None or time.monotonic() - pose[4] > 1.0:
        return '\033[90m【方向】等待定位…\033[0m'
    if goal is None:
        return '\033[90m【方向】目前沒有目標（規劃中或已到達）\033[0m'
    x, y, z, yaw, _ = pose
    gx, gy, gz, gyaw, is_slc = goal
    tag = '\033[1;95m[SLC 點]\033[0m ' if is_slc else ''
    return tag + render_target(x, y, z, yaw, gx, gy, gz, gyaw, is_slc)


def render_target(x, y, z, yaw, gx, gy, gz, gyaw, is_slc):
    dist = math.hypot(gx - x, gy - y)
    dz = gz - z
    # The planner's reached test is the 3D distance (handheld_fsm.cpp), so a
    # target 1 m above you is not "reached" even when standing under it.
    dist3 = math.sqrt(dist * dist + dz * dz)
    height = ''
    if abs(dz) > 0.15:
        height = '，相機{} {:.1f} m'.format('抬高' if dz > 0 else '放低', abs(dz))
    if dist3 > REACH_DIST and abs(dz) > 0.15 and dist <= REACH_DIST:
        return '\033[1;93m【方向】位置對了，但高度差 {:.1f} m：相機{} {:.1f} m\033[0m'.format(
            abs(dz), '抬高' if dz > 0 else '放低', abs(dz))
    if dist3 > REACH_DIST:
        rel = wrap_deg(math.degrees(math.atan2(gy - y, gx - x) - yaw))
        arrow, text = direction_text(rel)
        color = '92' if abs(rel) < 20 else '93'
        return '\033[1;{}m【方向】{} 目標在{}，距離 {:.1f} m{}\033[0m'.format(color, arrow, text, dist, height)
    if is_slc:
        return '\033[1;95m【方向】已到 SLC 點：腳不要動，慢慢原地轉一整圈\033[0m'
    turn = wrap_deg(math.degrees(gyaw - yaw))
    if abs(turn) <= REACH_YAW:
        return '\033[1;92m【方向】✓ 已到目標，朝向正確：保持不動{}\033[0m'.format(height)
    return '\033[1;96m【方向】已到目標附近：原地{}轉 {:.0f}°{}\033[0m'.format(
        '向左' if turn > 0 else '向右', abs(turn), height)


# Write straight to the terminal: stdout is tee'd into summary.log by the run
# script and a self-overwriting line would flood that file.
try:
    out = open('/dev/tty', 'w')
except OSError:
    out = sys.stdout


def main():
    rospy.init_node('handheld_direction_guide', anonymous=True, disable_signals=True)
    rospy.Subscriber(ODOM, Odometry, on_odom, queue_size=1)
    rospy.Subscriber(GOAL, Marker, on_goal, queue_size=1)
    last, drawn = None, 0.0
    while not rospy.is_shutdown():
        line = render()
        # Redraw at least every second: other processes print into this terminal.
        if line != last or time.monotonic() - drawn > 1.0:
            drawn = time.monotonic()
            # Overwrite one status line instead of scrolling the terminal.
            out.write('\r\033[K' + line)
            out.flush()
            last = line
        time.sleep(0.3)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
    finally:
        out.write('\n')
        out.flush()
