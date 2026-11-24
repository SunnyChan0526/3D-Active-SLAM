#!/usr/bin/env python3
"""Compare a recorded run with tape-measure / AprilTag ground truth (roadmap step 2).

    python3 setup/eval_ground_truth.py RUN_DIR [--gt SCENE_YAML] [--tags TAG_BAG]

Inputs (all inside RUN_DIR unless given):
  sensors*.bag          the recording (odometry topics and /gt_marker labels)
  tag_detections.bag    optional, from setup/ground_truth/apriltag_offline.sh
  SCENE_YAML            measured markers / tags (setup/ground_truth/scene_template.yaml);
                        default: ground_truth_file in run_metadata.yaml

Outputs (RUN_DIR/gt_eval/):
  report.yaml           all numbers below
  <topic>.tum           trajectories in TUM format (for evo_ape / evo_traj)
  tag_ground_truth.tum  camera poses from AprilTags

What it reports:
  1. markers: SLAM position (and yaw) when you typed "m <label>" vs the measured spot.
     "start" marked again at the end = return-to-start error.
  2. jumps: sudden pose corrections (loop closures) in the SLAM odometry, and, when a
     measured marker or an AprilTag is nearby in time, whether the correction moved the
     pose towards the truth (e_after < e_before) or away from it.
  3. tags: continuous error of each odometry topic against AprilTag poses.

Works on old runs without ground truth too (e.g. 20261117_174344): it still lists
the jumps, which tells you when to look and how large each correction was.

Frames: the SLAM world at start-up, start heading = +Y, left = -X (see the scene
template). VINS body_T_cam0 is identity in realsense_stereo_imu_config.yaml, so the
odometry pose is the infra1 optical frame: camera forward = its z axis.
"""
import argparse
import math
import sys
from pathlib import Path

import numpy as np
import yaml

DEFAULT_TOPICS = ('/factor_graph_atl/quadrotor/high_freq_odom', '/vins_estimator/odometry')
MARKER_TOPIC = '/gt_marker'
TAG_TOPIC = '/tag_detections'


# ---------------------------------------------------------------- geometry
def quat_to_rot(q):
    """q = (x, y, z, w) -> 3x3 rotation matrix."""
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def rot_to_quat(r):
    """3x3 rotation -> (x, y, z, w)."""
    t = np.trace(r)
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [(r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s, s / 4]
    else:
        i = int(np.argmax(np.diag(r)))
        j, k = (i + 1) % 3, (i + 2) % 3
        s = math.sqrt(1.0 + r[i, i] - r[j, j] - r[k, k]) * 2
        q = [0.0, 0.0, 0.0, (r[k, j] - r[j, k]) / s]
        q[i] = s / 4
        q[j] = (r[j, i] + r[i, j]) / s
        q[k] = (r[k, i] + r[i, k]) / s
    return np.array(q)


def forward_yaw_deg(r):
    """Heading of the camera forward (optical z) axis in the world XY plane."""
    return math.degrees(math.atan2(r[1, 2], r[0, 2]))


def wrap_deg(a):
    return (a + 180.0) % 360.0 - 180.0


def circular_mean_deg(values):
    rad = np.radians(values)
    return math.degrees(math.atan2(np.mean(np.sin(rad)), np.mean(np.cos(rad))))


def tag_world_rotation(facing_yaw_deg):
    """Rotation of a vertical wall tag in the world, apriltag_ros convention.

    apriltag_ros reports the tag frame as x = right (as seen by the viewer),
    y = up, z = out of the printed face towards the viewer. Check it once with
    the consistency table in the report (marker vs tag at the same moment).
    """
    psi = math.radians(facing_yaw_deg)
    z = np.array([math.cos(psi), math.sin(psi), 0.0])   # outward normal
    y = np.array([0.0, 0.0, 1.0])                         # up
    x = np.cross(y, z)                                    # viewer's right
    return np.column_stack([x, y, z])


def camera_from_tag(tag, p_cam_tag, q_cam_tag, start_height):
    """World pose of the camera from one detection: T_wc = T_wt * inv(T_ct)."""
    r_wt = tag_world_rotation(tag['facing_yaw_deg'])
    p_wt = np.array([tag['x'], tag['y'], tag['z'] - start_height])
    r_ct = quat_to_rot(np.asarray(q_cam_tag, float))
    r_wc = r_wt @ r_ct.T
    p_wc = p_wt - r_wc @ np.asarray(p_cam_tag, float)
    return p_wc, r_wc


# ---------------------------------------------------------------- tracks
class Track:
    """Time-sorted poses of one odometry topic."""

    def __init__(self, name, t, p, q):
        order = np.argsort(t)
        self.name = name
        self.t = np.asarray(t, float)[order]
        self.p = np.asarray(p, float).reshape(-1, 3)[order]
        self.q = np.asarray(q, float).reshape(-1, 4)[order]
        self.yaw = np.array([forward_yaw_deg(quat_to_rot(q)) for q in self.q]) if len(self.q) else np.zeros(0)

    def __len__(self):
        return len(self.t)

    def nearest(self, t, tol=0.1):
        if not len(self):
            return None
        i = int(np.clip(np.searchsorted(self.t, t), 1, len(self.t) - 1)) if len(self.t) > 1 else 0
        if len(self.t) > 1 and abs(self.t[i - 1] - t) < abs(self.t[i] - t):
            i -= 1
        return i if abs(self.t[i] - t) <= tol else None

    def window(self, t0, t1):
        """Median position and mean yaw in [t0, t1] (standing still)."""
        m = (self.t >= t0) & (self.t <= t1)
        if not m.any():
            return None
        return np.median(self.p[m], axis=0), circular_mean_deg(self.yaw[m]), int(m.sum())


def detect_jumps(track, speed_threshold=2.0, min_size=0.2):
    """Pose corrections: runs of samples moving faster than a person can walk."""
    jumps = []
    if len(track) < 3:
        return jumps
    dt = np.diff(track.t)
    dt[dt <= 0] = 1e-3
    speed = np.linalg.norm(np.diff(track.p, axis=0), axis=1) / dt
    fast = speed > speed_threshold
    i = 0
    while i < len(fast):
        if not fast[i]:
            i += 1
            continue
        j = i
        while j + 1 < len(fast) and fast[j + 1]:
            j += 1
        before, after = i, j + 1
        delta = track.p[after] - track.p[before]
        # Remove the walking motion during the jump (velocity over the previous 0.5 s).
        recent = (track.t >= track.t[before] - 0.5) & (track.t <= track.t[before])
        k = int(np.argmax(recent))
        if recent.sum() >= 2 and track.t[before] > track.t[k]:
            velocity = (track.p[before] - track.p[k]) / (track.t[before] - track.t[k])
            delta = delta - velocity * (track.t[after] - track.t[before])
        size = float(np.linalg.norm(delta[:2]))
        if size >= min_size:
            jumps.append({
                'time': float(track.t[before]),
                'duration_s': round(float(track.t[after] - track.t[before]), 3),
                'correction_xy_m': [round(float(v), 3) for v in delta[:2]],
                'size_xy_m': round(size, 3),
                'yaw_change_deg': round(wrap_deg(track.yaw[after] - track.yaw[before]), 2),
                'pose_before_xy': [round(float(v), 3) for v in track.p[before][:2]],
                'pose_after_xy': [round(float(v), 3) for v in track.p[after][:2]],
            })
        i = j + 1
    return jumps


def verdict(e_before, e_after, ok_threshold=0.3):
    if e_after > e_before:
        return 'wrong: correction moved the pose away from the truth'
    if e_after <= ok_threshold:
        return 'correct'
    return 'partial: closer to the truth but still off by more than {:.1f} m'.format(ok_threshold)


# ---------------------------------------------------------------- evaluation
def evaluate_markers(track, markers, scene, t0=None, before=0.5, after=1.0):
    measured = scene.get('markers') or {}
    rows = []
    for t, label in markers:
        row = {'label': label, 'time': round(t, 3)}
        if t0 is not None:
            row['t_from_start_s'] = round(t - t0, 1)
        w = track.window(t - before, t + after)
        if w is None:
            row['status'] = 'no odometry at this time'
            rows.append(row)
            continue
        p, yaw, n = w
        row.update(slam_xy=[round(float(p[0]), 3), round(float(p[1]), 3)],
                   slam_yaw_deg=round(yaw, 1), samples=n)
        gt = measured.get(label)
        if gt is None:
            row['status'] = 'not measured yet: add markers.{} to the scene yaml'.format(label)
        else:
            err = np.array([p[0] - gt['x'], p[1] - gt['y']])
            row.update(status='ok', truth_xy=[gt['x'], gt['y']],
                       error_xy_m=[round(float(v), 3) for v in err],
                       error_m=round(float(np.linalg.norm(err)), 3))
            if gt.get('yaw_deg') is not None:
                row['yaw_error_deg'] = round(wrap_deg(yaw - gt['yaw_deg']), 1)
        rows.append(row)
    return rows


def evaluate_jump(jump, track, markers, scene, tag_track=None, look_before=10.0, look_after=60.0):
    """Was this correction right? Uses the nearest measured marker, else AprilTags."""
    measured = scene.get('markers') or {}
    c = np.array(jump['correction_xy_m'])
    tj = jump['time']
    end = tj + jump['duration_s']
    evidence = []
    cands = [(t, l) for t, l in markers if l in measured and tj - look_before <= t <= end + look_after]
    after_marks = [m for m in cands if m[0] >= end]
    chosen = after_marks[0] if after_marks else (cands[-1] if cands else None)
    if chosen is not None:
        t, label = chosen
        w = track.window(t - 0.5, t + 1.0)
        if w is not None:
            p = w[0][:2]
            if t >= end:
                p_after, p_before = p, p - c
            else:
                p_before, p_after = p, p + c
            gt = np.array([measured[label]['x'], measured[label]['y']])
            evidence.append(_judge('marker ' + label, t, p_before, p_after, gt, c))
    if tag_track is not None and len(tag_track):
        for side, (a, b) in (('before', (tj - 5.0, tj)), ('after', (end, end + 5.0))):
            m = (tag_track.t >= a) & (tag_track.t <= b)
            if not m.any():
                continue
            # Compare SLAM and tag at the same instants, then express in "before"/"after" terms.
            errs = []
            for t_tag, p_tag in zip(tag_track.t[m], tag_track.p[m]):
                i = track.nearest(t_tag, tol=0.05)
                if i is not None:
                    errs.append((t_tag, track.p[i][:2], p_tag[:2]))
            if not errs:
                continue
            t_tag, p_slam, p_gt = errs[len(errs) // 2]
            if side == 'before':
                p_before, p_after = p_slam, p_slam + c
            else:
                p_before, p_after = p_slam - c, p_slam
            evidence.append(_judge('apriltag ({} the jump, {} detections)'.format(side, len(errs)),
                                   t_tag, p_before, p_after, p_gt, c))
    jump = dict(jump)
    jump['evidence'] = evidence
    if not evidence:
        jump['verdict'] = 'no ground truth near this jump'
    else:
        jump['verdict'] = evidence[0]['verdict']
    return jump


def _judge(source, t, p_before, p_after, gt, c):
    e_b = float(np.linalg.norm(p_before - gt))
    e_a = float(np.linalg.norm(p_after - gt))
    drift = gt - p_before
    cos = float(np.dot(c, drift) / (np.linalg.norm(c) * np.linalg.norm(drift))) \
        if np.linalg.norm(drift) > 1e-6 and np.linalg.norm(c) > 1e-6 else None
    return {'source': source, 'time': round(float(t), 3),
            'error_before_m': round(e_b, 3), 'error_after_m': round(e_a, 3),
            'direction_cosine': None if cos is None else round(cos, 2),
            'verdict': verdict(e_b, e_a)}


def tag_track_from_detections(detections, scene, max_distance=3.0, max_view_angle_deg=60.0):
    """detections: list of (t, tag_id, p_cam_tag, q_cam_tag) for single-tag detections."""
    tags = {int(k): v for k, v in (scene.get('tags') or {}).items()}
    h = float(scene.get('start_camera_height_m') or 0.0)
    ts, ps, qs, ids = [], [], [], []
    rejected = {'unknown_id': 0, 'too_far': 0, 'oblique': 0}
    for t, tag_id, p_ct, q_ct in detections:
        tag = tags.get(int(tag_id))
        if tag is None:
            rejected['unknown_id'] += 1
            continue
        if np.linalg.norm(p_ct) > max_distance:
            rejected['too_far'] += 1
            continue
        # Angle between the camera's line of sight and the tag normal (z_tag in camera).
        normal_cam = quat_to_rot(np.asarray(q_ct, float))[:, 2]
        view = -np.asarray(p_ct, float) / np.linalg.norm(p_ct)
        if math.degrees(math.acos(np.clip(np.dot(normal_cam, view), -1, 1))) > max_view_angle_deg:
            rejected['oblique'] += 1
            continue
        p_wc, r_wc = camera_from_tag(tag, p_ct, q_ct, h)
        ts.append(t)
        ps.append(p_wc)
        qs.append(rot_to_quat(r_wc))
        ids.append(int(tag_id))
    track = Track('apriltag', ts, np.array(ps).reshape(-1, 3), np.array(qs).reshape(-1, 4))
    return track, rejected


def evaluate_against_tags(track, tag_track, tol=0.05):
    errs, yaw_errs = [], []
    for t, p, yaw in zip(tag_track.t, tag_track.p, tag_track.yaw):
        i = track.nearest(t, tol=tol)
        if i is None:
            continue
        errs.append(float(np.linalg.norm(track.p[i][:2] - p[:2])))
        yaw_errs.append(abs(wrap_deg(track.yaw[i] - yaw)))
    if not errs:
        return {'matched': 0}
    e = np.array(errs)
    return {'matched': len(errs), 'xy_error_median_m': round(float(np.median(e)), 3),
            'xy_error_p90_m': round(float(np.percentile(e, 90)), 3),
            'xy_error_max_m': round(float(e.max()), 3),
            'yaw_error_median_deg': round(float(np.median(yaw_errs)), 2)}


def marker_tag_consistency(markers, scene, tag_track, tol=1.0):
    """Measured marker vs tag-derived camera position at the same moment.

    Large differences mean a tag is measured wrongly or the tag frame
    convention is flipped; fix that before trusting the tag numbers.
    """
    measured = scene.get('markers') or {}
    rows = []
    for t, label in markers:
        if label not in measured or not len(tag_track):
            continue
        m = np.abs(tag_track.t - t) <= tol
        if not m.any():
            continue
        p = np.median(tag_track.p[m], axis=0)
        gt = np.array([measured[label]['x'], measured[label]['y']])
        rows.append({'label': label, 'tag_xy': [round(float(v), 3) for v in p[:2]],
                     'difference_m': round(float(np.linalg.norm(p[:2] - gt)), 3),
                     'detections': int(m.sum())})
    return rows


# ---------------------------------------------------------------- I/O
def read_run(run_dir, topics):
    import rosbag  # ROS only; kept here so the maths can be tested without ROS
    data = {tp: ([], [], []) for tp in topics}
    markers = []
    bags = sorted(Path(run_dir).glob('sensors*.bag'))
    if not bags:
        raise SystemExit('沒有找到 {}/sensors*.bag'.format(run_dir))
    for bag_path in bags:
        with rosbag.Bag(str(bag_path)) as bag:
            for topic, msg, t in bag.read_messages(topics=list(topics) + [MARKER_TOPIC]):
                if topic == MARKER_TOPIC:
                    markers.append((t.to_sec(), msg.data))
                    continue
                pose = msg.pose.pose
                ts, ps, qs = data[topic]
                ts.append(msg.header.stamp.to_sec())
                ps.append([pose.position.x, pose.position.y, pose.position.z])
                o = pose.orientation
                qs.append([o.x, o.y, o.z, o.w])
    tracks = {tp: Track(tp, *[np.array(v) for v in data[tp]]) for tp in topics}
    return tracks, sorted(markers), [b.name for b in bags]


def read_tags(tag_bag):
    import rosbag
    dets = []
    with rosbag.Bag(str(tag_bag)) as bag:
        for _, msg, _ in bag.read_messages(topics=[TAG_TOPIC]):
            for d in msg.detections:
                if len(d.id) != 1:
                    continue  # bundles are not used
                p = d.pose.pose.pose.position
                o = d.pose.pose.pose.orientation
                dets.append((d.pose.header.stamp.to_sec() or msg.header.stamp.to_sec(), d.id[0],
                             [p.x, p.y, p.z], [o.x, o.y, o.z, o.w]))
    return dets


def plain(o):
    """numpy scalars/arrays -> built-in types, so yaml.safe_dump accepts them."""
    if isinstance(o, dict):
        return {k: plain(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [plain(v) for v in o]
    if isinstance(o, np.ndarray):
        return plain(o.tolist())
    if isinstance(o, np.generic):
        return o.item()
    return o


def write_tum(track, path):
    with open(path, 'w') as f:
        for t, p, q in zip(track.t, track.p, track.q):
            f.write('{:.6f} {:.4f} {:.4f} {:.4f} {:.6f} {:.6f} {:.6f} {:.6f}\n'.format(t, *p, *q))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('run_dir')
    ap.add_argument('--gt', help='scene yaml (default: ground_truth_file in run_metadata.yaml)')
    ap.add_argument('--tags', help='tag detections bag (default: RUN_DIR/tag_detections.bag if present)')
    ap.add_argument('--topics', nargs='+', default=list(DEFAULT_TOPICS))
    ap.add_argument('--jump-speed', type=float, default=2.0, help='m/s treated as a correction, not walking')
    ap.add_argument('--jump-min', type=float, default=0.2, help='smallest correction to report (m)')
    args = ap.parse_args(argv)
    run_dir = Path(args.run_dir)

    gt_path = args.gt
    meta_path = run_dir / 'run_metadata.yaml'
    if gt_path is None and meta_path.exists():
        gt_path = (yaml.safe_load(meta_path.read_text()) or {}).get('ground_truth_file')
    scene = yaml.safe_load(Path(gt_path).read_text()) if gt_path else {}
    if not gt_path:
        print('【注意】沒有場景檔（--gt）：只列出位姿跳動，無法判斷對錯。')

    tracks, markers, bag_names = read_run(run_dir, args.topics)
    t0 = min((tr.t[0] for tr in tracks.values() if len(tr)), default=None)
    report = {'run_dir': str(run_dir), 'bags': bag_names, 'scene_file': gt_path,
              'markers_logged': [{'label': l, 'time': round(t, 3)} for t, l in markers],
              'topics': {}}

    tag_track = None
    tag_bag = Path(args.tags) if args.tags else run_dir / 'tag_detections.bag'
    if tag_bag.exists() and scene.get('tags'):
        tag_track, rejected = tag_track_from_detections(read_tags(tag_bag), scene)
        report['apriltag'] = {'bag': str(tag_bag), 'poses': len(tag_track), 'rejected': rejected,
                              'marker_consistency': marker_tag_consistency(markers, scene, tag_track)}

    out = run_dir / 'gt_eval'
    out.mkdir(exist_ok=True)
    if tag_track is not None and len(tag_track):
        write_tum(tag_track, out / 'tag_ground_truth.tum')

    for topic, tr in tracks.items():
        entry = {'samples': len(tr)}
        if not len(tr):
            report['topics'][topic] = entry
            continue
        write_tum(tr, out / (topic.strip('/').replace('/', '_') + '.tum'))
        entry['start_yaw_deg'] = round(float(tr.yaw[0]), 1)
        start_yaw = float(scene.get('start_yaw_deg', 90))
        if abs(wrap_deg(tr.yaw[0] - start_yaw)) > 15:
            entry['warning'] = 'start heading is {:.0f} deg, expected {:.0f}: frame convention differs'.format(
                tr.yaw[0], start_yaw)
        entry['markers'] = evaluate_markers(tr, markers, scene, t0)
        jumps = detect_jumps(tr, args.jump_speed, args.jump_min)
        entry['jumps'] = [evaluate_jump(j, tr, markers, scene, tag_track) for j in jumps]
        for j in entry['jumps']:
            j['t_from_start_s'] = round(j['time'] - t0, 1)
        if tag_track is not None and len(tag_track):
            entry['vs_apriltag'] = evaluate_against_tags(tr, tag_track)
        report['topics'][topic] = entry

    (out / 'report.yaml').write_text(yaml.safe_dump(plain(report), allow_unicode=True, sort_keys=False))
    print_summary(report)
    print('\n詳細結果：{}'.format(out / 'report.yaml'))
    return 0


def print_summary(report):
    for topic, e in report['topics'].items():
        print('\n== {} ({} poses)'.format(topic, e['samples']))
        if e.get('warning'):
            print('  【注意】' + e['warning'])
        for m in e.get('markers', []):
            if m.get('status') == 'ok':
                extra = '，yaw 差 {}°'.format(m['yaw_error_deg']) if 'yaw_error_deg' in m else ''
                print('  檢查點 {:<8} 誤差 {:.2f} m{}'.format(m['label'], m['error_m'], extra))
            else:
                print('  檢查點 {:<8} {}'.format(m['label'], m.get('status')))
        for j in e.get('jumps', []):
            print('  跳動 t={}s：{:.2f} m（{} 秒內），yaw {}° → {}'.format(
                j['t_from_start_s'], j['size_xy_m'], j['duration_s'], j['yaw_change_deg'], j['verdict']))
            for ev in j['evidence']:
                print('      {}：修正前誤差 {:.2f} m → 修正後 {:.2f} m（方向一致度 {}）'.format(
                    ev['source'], ev['error_before_m'], ev['error_after_m'], ev['direction_cosine']))
        if 'vs_apriltag' in e:
            v = e['vs_apriltag']
            if v.get('matched'):
                print('  對 AprilTag：{} 筆，xy 誤差中位數 {} m、P90 {} m，yaw 中位數 {}°'.format(
                    v['matched'], v['xy_error_median_m'], v['xy_error_p90_m'], v['yaw_error_median_deg']))
    tag = report.get('apriltag')
    if tag and tag['marker_consistency']:
        print('\n== 檢查點 vs AprilTag（差太多表示 tag 量錯或座標慣例相反）')
        for r in tag['marker_consistency']:
            print('  {:<8} 差 {:.2f} m'.format(r['label'], r['difference_m']))


if __name__ == '__main__':
    sys.exit(main())
