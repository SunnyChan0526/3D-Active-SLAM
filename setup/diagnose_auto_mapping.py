"""Read-only live depth, occupancy and odometry diagnosis. Never triggers planning."""
import collections
import json
import math
from pathlib import Path
import sys
import time
import threading
import numpy as np
import rospy
from nav_msgs.msg import Odometry
from sensor_msgs.msg import Image, PointCloud2
from std_msgs.msg import String


def main():
    rospy.init_node('auto_mapping_readonly_diagnosis', anonymous=True, disable_signals=True)
    records = {}; lock = threading.Lock()

    def callback(topic, msg):
        with lock:
            record = records.setdefault(topic, {'messages': 0})
            record['messages'] += 1
            if hasattr(msg, 'header'):
                record['stamp'] = msg.header.stamp.to_sec()
                record['frame'] = msg.header.frame_id
                stamp = msg.header.stamp.to_sec()
                record['receipt_age_seconds'] = rospy.Time.now().to_sec() - stamp if stamp > 0 else None
                if stamp == 0:
                    record['timestamp_note'] = 'Publisher supplied a zero stamp; use received message count to assess publication.'
            if isinstance(msg, Image):
                record['encoding'] = msg.encoding
                dtype = {'16UC1': 'u2', '32FC1': 'f4'}.get(msg.encoding)
                if dtype:
                    dt = np.dtype(('>' if msg.is_bigendian else '<') + dtype)
                    pixels = np.ndarray((msg.height, msg.width), dtype=dt, buffer=msg.data,
                                        strides=(msg.step, dt.itemsize))[::8, ::8].astype(float)
                    if msg.encoding == '16UC1': pixels /= 1000.0
                    valid = np.isfinite(pixels) & (pixels >= .2) & (pixels <= 5)
                    record['sampled_valid_depth_fraction_0_2_to_5_m'] = float(valid.mean())
                    record['sampled_depth_median_m'] = float(np.median(pixels[valid])) if valid.any() else None
            elif isinstance(msg, Odometry):
                p = msg.pose.pose.position; v = msg.twist.twist.linear
                record['xyz'] = [p.x, p.y, p.z]
                record.setdefault('first_xyz', record['xyz'])
                record['reported_speed_m_s'] = math.sqrt(v.x*v.x+v.y*v.y+v.z*v.z)
            elif isinstance(msg, PointCloud2):
                record['point_count'] = msg.width * msg.height
                record['max_point_count'] = max(record.get('max_point_count', 0), record['point_count'])
            else:
                record.setdefault('status_events', []).append(msg.data)

    streams = {
        '/camera/depth/image_rect_raw': Image,
        '/vins_estimator/odometry': Odometry,
        '/factor_graph_atl/quadrotor/high_freq_odom': Odometry,
        '/factor_graph_atl/quadrotor/sloam_to_vio_odom': Odometry,
        '/sdf_map/occupancy_global': PointCloud2,
        '/sdf_map/occupancy_storage': PointCloud2,
        '/sdf_map/occupancy_inflate_local': PointCloud2,
        '/exploration_node/handheld_status': String,
    }
    subscribers = [rospy.Subscriber(topic, kind, lambda msg, t=topic: callback(t, msg),
                                   queue_size=1, buff_size=4*1024*1024)
                   for topic, kind in streams.items()]
    print('只讀檢查 20 秒：深度、規劃地圖與定位；不發送規劃或控制指令。', flush=True)
    started = time.monotonic()
    while time.monotonic() - started < 20 and not rospy.is_shutdown(): time.sleep(.2)
    for sub in subscribers: sub.unregister()
    with lock:
        output = {'duration_seconds': time.monotonic()-started,
                  'streams': {t: records.get(t, {'messages': 0}) for t in streams},
                  'parameters': {p: rospy.get_param(p, None) for p in [
                      '/exploration_node/fsm/handheld_auto', '/exploration_node/fsm/planning_only',
                      '/exploration_node/map_ros/global/map_min_boundary_z',
                      '/exploration_node/map_ros/global/map_max_boundary_z',
                      '/exploration_node/frontier/cluster_min',
                      '/exploration_node/frontier/min_info_gain']}}
    destination = Path(sys.argv[1]); destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(output, ensure_ascii=False, indent=2))
    for t, values in output['streams'].items(): print(t, json.dumps(values, ensure_ascii=False))
    print('已保存：' + str(destination))


if __name__ == '__main__': main()
