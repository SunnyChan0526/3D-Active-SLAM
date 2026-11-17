#!/usr/bin/env python3
"""從一輪錄製的 bag 統計手持相機在 SLAM 地圖座標中的實際 Z 範圍。

用法: python3 measure_handheld_height.py <run_dir 或 bag ...> [--skip 10]
--skip: 略過開頭秒數（初始化靜止階段）。
"""
import argparse, glob, os, sys
import numpy as np
import rosbag

TOPIC = '/factor_graph_atl/quadrotor/high_freq_odom'  # 觀察點使用的 SLAM 地圖座標

ap = argparse.ArgumentParser()
ap.add_argument('paths', nargs='+')
ap.add_argument('--skip', type=float, default=10.0)
ap.add_argument('--topic', default=TOPIC)
a = ap.parse_args()
bags = []
for p in a.paths:
    bags += sorted(glob.glob(os.path.join(p, '*.bag'))) if os.path.isdir(p) else [p]
t, z = [], []
for b in bags:
    with rosbag.Bag(b) as bag:
        for _, m, _ in bag.read_messages(topics=[a.topic]):
            t.append(m.header.stamp.to_sec()); z.append(m.pose.pose.position.z)
if not z:
    sys.exit('找不到 {}（SLAM 是否有啟動？）'.format(a.topic))
t, z = np.array(t), np.array(z)
z = z[np.isfinite(z) & (t >= t.min() + a.skip)]
if z.size < 20:
    sys.exit('有效樣本太少 ({})，請走久一點'.format(z.size))
p = np.percentile(z, [1, 5, 50, 95, 99])
print('樣本 {} 筆，時長約 {:.0f} s，topic {}'.format(z.size, t.max() - t.min(), a.topic))
print('min {:.3f} | p1 {:.3f} | p5 {:.3f} | 中位數 {:.3f} | p95 {:.3f} | p99 {:.3f} | max {:.3f} m'.format(
    z.min(), *p[:2], p[2], *p[3:], z.max()))
print('建議: ACTIVE_SLAM_HANDHELD_Z_MIN={:.2f} ACTIVE_SLAM_HANDHELD_Z_MAX={:.2f}  (p5–p95)'.format(p[1], p[3]))
