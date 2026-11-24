#!/usr/bin/env python3
"""Unit tests for setup/eval_ground_truth.py (no ROS needed).

    python3 setup/tests/test_eval_ground_truth.py
"""
import math
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import eval_ground_truth as eg  # noqa: E402

# Camera at start: forward (optical z) = +Y, right (x) = +X, down (y) = -Z.
R_START = np.column_stack([[1, 0, 0], [0, 0, -1], [0, 1, 0]]).astype(float)


def camera_rot(yaw_deg):
    """Level camera whose forward axis has this world yaw."""
    a = math.radians(yaw_deg)
    fwd = np.array([math.cos(a), math.sin(a), 0.0])
    down = np.array([0.0, 0.0, -1.0])
    return np.column_stack([np.cross(down, fwd), down, fwd])


def straight_track(n=400, rate=20.0, speed=0.5):
    t = np.arange(n) / rate
    p = np.column_stack([np.zeros(n), speed * t, np.zeros(n)])
    q = np.tile(eg.rot_to_quat(R_START), (n, 1))
    return t, p, q


class Geometry(unittest.TestCase):
    def test_start_heading_is_plus_y(self):
        self.assertAlmostEqual(eg.forward_yaw_deg(R_START), 90.0)
        self.assertTrue(np.allclose(camera_rot(90), R_START))

    def test_quaternion_round_trip(self):
        for yaw in (-170, -90, 0, 33, 90, 179):
            r = camera_rot(yaw)
            self.assertTrue(np.allclose(eg.quat_to_rot(eg.rot_to_quat(r)), r, atol=1e-9))

    def test_tag_seen_head_on_matches_apriltag_ros_convention(self):
        # Tag 6 m ahead on the far wall, facing back (-Y), at camera height.
        tag = {'x': 0.0, 'y': 6.0, 'z': 0.4, 'facing_yaw_deg': -90}
        r_wt = eg.tag_world_rotation(tag['facing_yaw_deg'])
        r_ct = R_START.T @ r_wt
        # apriltag_ros: tag x = viewer's right, y = up, z = towards the camera.
        self.assertTrue(np.allclose(r_ct[:, 0], [1, 0, 0]))
        self.assertTrue(np.allclose(r_ct[:, 1], [0, -1, 0]))
        self.assertTrue(np.allclose(r_ct[:, 2], [0, 0, -1]))
        p, r = eg.camera_from_tag(tag, [0, 0, 6.0], eg.rot_to_quat(r_ct), start_height=0.4)
        self.assertTrue(np.allclose(p, [0, 0, 0], atol=1e-9))
        self.assertTrue(np.allclose(r, R_START, atol=1e-9))

    def test_tag_from_oblique_pose(self):
        tag = {'x': -3.0, 'y': 2.0, 'z': 1.0, 'facing_yaw_deg': 0}
        p_wc, r_wc = np.array([-1.0, 1.5, 0.2]), camera_rot(160)
        r_wt = eg.tag_world_rotation(0)
        p_wt = np.array([-3.0, 2.0, 1.0 - 0.4])
        p_ct = r_wc.T @ (p_wt - p_wc)
        q_ct = eg.rot_to_quat(r_wc.T @ r_wt)
        p, r = eg.camera_from_tag(tag, p_ct, q_ct, start_height=0.4)
        self.assertTrue(np.allclose(p, p_wc, atol=1e-9))
        self.assertTrue(np.allclose(r, r_wc, atol=1e-9))


class Jumps(unittest.TestCase):
    def make(self, jump_xy, at=10.0):
        t, p, q = straight_track()
        p[t >= at, :2] += jump_xy
        return eg.Track('odom', t, p, q)

    def test_detects_one_jump(self):
        jumps = eg.detect_jumps(self.make([0.6, -0.5]))
        self.assertEqual(len(jumps), 1)
        self.assertAlmostEqual(jumps[0]['size_xy_m'], math.hypot(0.6, 0.5), places=2)
        self.assertEqual(jumps[0]['correction_xy_m'], [0.6, -0.5])

    def test_walking_is_not_a_jump(self):
        self.assertEqual(eg.detect_jumps(self.make([0.0, 0.0])), [])

    def test_correct_and_wrong_corrections(self):
        # Before the jump SLAM had drifted: true position = SLAM + (0.6, -0.5).
        track = self.make([0.6, -0.5])
        t_mark = 12.0
        slam_at_mark = np.array([0.6, 0.5 * t_mark - 0.5])
        good = {'markers': {'slc1': {'x': float(slam_at_mark[0]) + 0.05, 'y': float(slam_at_mark[1])}}}
        j = eg.evaluate_jump(eg.detect_jumps(track)[0], track, [(t_mark, 'slc1')], good)
        self.assertEqual(j['verdict'], 'correct')
        self.assertGreater(j['evidence'][0]['direction_cosine'], 0.9)
        # Truth where SLAM was before the correction: the jump made it worse.
        bad = {'markers': {'slc1': {'x': 0.0, 'y': float(slam_at_mark[1]) + 0.5}}}
        j = eg.evaluate_jump(eg.detect_jumps(track)[0], track, [(t_mark, 'slc1')], bad)
        self.assertTrue(j['verdict'].startswith('wrong'))

    def test_jump_checked_with_tags(self):
        track = self.make([0.6, -0.5])
        t, p, q = straight_track()
        p[:, :2] += [0.6, -0.5]                      # truth = corrected trajectory
        tag_track = eg.Track('apriltag', t, p, q)
        j = eg.evaluate_jump(eg.detect_jumps(track)[0], track, [], {}, tag_track)
        self.assertEqual([e['verdict'] for e in j['evidence']], ['correct', 'correct'])


class Markers(unittest.TestCase):
    def test_marker_errors_and_unmeasured(self):
        # Stand at the start for 2 s, walk to y = 2 m, stand there, walk on.
        t = np.arange(0, 20, 0.05)
        y = np.clip(0.5 * (t - 2.0), 0, 2.0) + np.clip(0.5 * (t - 8.0), 0, None)
        p = np.column_stack([np.zeros_like(t), y, np.zeros_like(t)])
        q = np.tile(eg.rot_to_quat(R_START), (len(t), 1))
        track = eg.Track('odom', t, p, q)
        scene = {'markers': {'A2': {'x': 0.1, 'y': 2.0}, 'start': {'x': 0, 'y': 0, 'yaw_deg': 90}}}
        rows = eg.evaluate_markers(track, [(0.5, 'start'), (6.0, 'A2'), (12.0, 'X9')], scene)
        self.assertAlmostEqual(rows[0]['error_m'], 0.0)
        self.assertEqual(rows[0]['yaw_error_deg'], 0.0)
        self.assertAlmostEqual(rows[1]['error_m'], 0.1, places=1)
        self.assertTrue(rows[2]['status'].startswith('not measured'))

    def test_tag_track_filters(self):
        scene = {'start_camera_height_m': 0.4,
                 'tags': {0: {'x': 0.0, 'y': 6.0, 'z': 0.4, 'facing_yaw_deg': -90}}}
        r_ct = eg.rot_to_quat(R_START.T @ eg.tag_world_rotation(-90))
        dets = [(1.0, 0, [0, 0, 2.5], r_ct), (2.0, 0, [0, 0, 5.0], r_ct), (3.0, 7, [0, 0, 1.0], r_ct)]
        track, rejected = eg.tag_track_from_detections(dets, scene)
        self.assertEqual(len(track), 1)
        self.assertEqual(rejected, {'unknown_id': 1, 'too_far': 1, 'oblique': 0})
        self.assertTrue(np.allclose(track.p[0], [0, 3.5, 0]))


if __name__ == '__main__':
    unittest.main(verbosity=2)
