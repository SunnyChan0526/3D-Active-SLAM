#!/usr/bin/env python3
"""Write run_metadata.yaml for one recording (step 2 experiments).

Reads the resolved launch parameters (resolved_params.yaml, written just
before this by record_isolated_vins_test.sh) and the ACTIVE_SLAM_* settings,
so every run records what it was run with. Runs are only comparable when
these values match (IR emitter, landmark classes, ig_weight, ...).

Usage: write_run_metadata.py RUN_DIR PIPELINE TEST_MODE
Optional env (set before starting the recording):
  ACTIVE_SLAM_SCENE        scene name, e.g. many_objects / few_objects / loop / corridor
  ACTIVE_SLAM_RUN_NOTE     free text
  ACTIVE_SLAM_GT_FILE      ground-truth yaml for this scene (setup/ground_truth/...)
  ACTIVE_SLAM_START_HEIGHT_M  camera height above the floor at the start mark
"""
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import yaml

# Parameter keys (or key fragments) worth keeping next to the results.
PARAM_FRAGMENTS = (
    '/process_cloud_node/',
    '/loop_closure_submap_node/',
    'active_closure/',
    'handheld',
    'planning_only',
    'max_correction',
    'ambiguity_distance',
    'max_measurements',
)
ENV_KEYS = (
    'ACTIVE_SLAM_TEST_PIPELINE', 'ACTIVE_SLAM_TEST_MODE', 'ACTIVE_SLAM_HANDHELD_AUTO',
    'ACTIVE_SLAM_HANDHELD_HEIGHT_LIMIT', 'ACTIVE_SLAM_HANDHELD_Z_MIN', 'ACTIVE_SLAM_HANDHELD_Z_MAX',
    'ACTIVE_SLAM_HANDHELD_Z_SAMPLES', 'ACTIVE_SLAM_ROOM_FRONT', 'ACTIVE_SLAM_ROOM_BACK',
    'ACTIVE_SLAM_ROOM_LEFT', 'ACTIVE_SLAM_ROOM_RIGHT', 'ACTIVE_SLAM_ROOM_MARGIN',
    'ACTIVE_SLAM_SLC_FLOOR_HEIGHT', 'ACTIVE_SLAM_SLC_CLUSTER_DISTANCE',
    'ACTIVE_SLAM_SLC_CLUSTER_MIN_SAMPLES', 'ACTIVE_SLAM_SLC_MAX_KEY_POSE_CLUSTER_DISTANCE',
    'ACTIVE_SLAM_SLC_MIN_KEY_POSE_TO_LANDMARK', 'ACTIVE_SLAM_SLC_IG_WEIGHT',
    'ACTIVE_SLAM_OBJECT_CLASSES', 'ACTIVE_SLAM_DISABLE_IR_EMITTER',
    'ACTIVE_SLAM_RECORD_FULL', 'ACTIVE_SLAM_RECORD_SEMANTIC', 'ACTIVE_SLAM_RESULTS_DIR',
    'ACTIVE_SLAM_SEMANTIC_THREADS', 'ACTIVE_SLAM_SEMANTIC_NICE',
    'ACTIVESLAM_COLOR_FPS', 'ACTIVESLAM_CAMERA_ALIGN', 'ACTIVESLAM_VINS_TRACK_USED_ONLY',
    'ACTIVESLAM_YOLO_SERVER', 'ACTIVESLAM_HOST_POWER_MODE', 'ACTIVESLAM_HOST_L4T',
)


def git(repo, *args):
    try:
        return subprocess.run(['git', '-C', str(repo)] + list(args), stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL, universal_newlines=True,
                              timeout=5).stdout.strip('\n') or None
    except (OSError, subprocess.SubprocessError):
        return None


def select_params(params):
    return {k: v for k, v in sorted(params.items())
            if any(fragment in k for fragment in PARAM_FRAGMENTS)}


def flatten(tree, prefix=''):
    """roslaunch --dump-params is already flat; this also accepts nested dicts."""
    out = {}
    for key, value in (tree or {}).items():
        name = key if key.startswith('/') else prefix + '/' + key
        if isinstance(value, dict):
            out.update(flatten(value, name))
        else:
            out[name] = value
    return out


def build(run_dir, pipeline, test_mode, env=os.environ):
    repo = Path(__file__).resolve().parent.parent
    params_path = run_dir / 'resolved_params.yaml'
    params = {}
    if params_path.exists():
        params = flatten(yaml.safe_load(params_path.read_text()) or {})
    labels = params.get('/process_cloud_node/object_class_labels')
    ir_off = env.get('ACTIVE_SLAM_DISABLE_IR_EMITTER', 'true') == 'true'
    meta = {
        'run_dir': str(run_dir),
        'created_wall_time': time.time(),
        'created_local': time.strftime('%Y-%m-%d %H:%M:%S %z'),
        'scene': env.get('ACTIVE_SLAM_SCENE') or None,
        'note': env.get('ACTIVE_SLAM_RUN_NOTE') or None,
        'ground_truth_file': env.get('ACTIVE_SLAM_GT_FILE') or None,
        'start_camera_height_m': float(env['ACTIVE_SLAM_START_HEIGHT_M'])
        if env.get('ACTIVE_SLAM_START_HEIGHT_M') else None,
        'pipeline': pipeline,
        'test_mode': test_mode,
        # The experiment settings that must match between compared runs.
        'key_settings': {
            'ir_emitter': 'off' if ir_off else 'on',
            'object_class_labels': list(labels) if isinstance(labels, list) else labels,
            'chairs_only_baseline': labels == [1],
            'slc_ig_weight': params.get('/exploration_node/active_closure/ig_weight'),
            'planning_only': params.get('/exploration_node/fsm/planning_only'),
            'record_full': env.get('ACTIVE_SLAM_RECORD_FULL', 'false') == 'true',
            'record_semantic': env.get('ACTIVE_SLAM_RECORD_SEMANTIC', 'false') == 'true',
        },
        'git': {
            'commit': git(repo, 'rev-parse', 'HEAD'),
            'branch': git(repo, 'rev-parse', '--abbrev-ref', 'HEAD'),
            'dirty_files': (git(repo, 'status', '--porcelain', '--untracked-files=no') or '').splitlines(),
        },
        'host': {
            'hostname': socket.gethostname(),
            'power_mode': env.get('ACTIVESLAM_HOST_POWER_MODE') or None,
            'l4t': env.get('ACTIVESLAM_HOST_L4T') or None,
        },
        'env': {k: env[k] for k in ENV_KEYS if k in env},
        'params': select_params(params),
    }
    warnings = []
    if meta['key_settings']['slc_ig_weight'] not in (None, 6, 6.0):
        warnings.append('ig_weight 不是 6：正式實驗一律用 6。')
    if not meta['scene']:
        warnings.append('沒有設定 ACTIVE_SLAM_SCENE。')
    if test_mode == 'free' and not meta['key_settings']['record_full']:
        warnings.append('沒有 ACTIVE_SLAM_RECORD_FULL=true：滾動錄製會刪掉開頭，算不了回到起點誤差。')
    meta['warnings'] = warnings
    return meta


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    run_dir = Path(sys.argv[1])
    meta = build(run_dir, sys.argv[2], sys.argv[3])
    (run_dir / 'run_metadata.yaml').write_text(
        yaml.safe_dump(meta, allow_unicode=True, sort_keys=False, default_flow_style=None))
    ks = meta['key_settings']
    print('Run metadata: scene={} ir_emitter={} classes={} ig_weight={} commit={}'.format(
        meta['scene'], ks['ir_emitter'], ks['object_class_labels'], ks['slc_ig_weight'],
        (meta['git']['commit'] or '?')[:7]), flush=True)
    for w in meta['warnings']:
        print('【注意】' + w, flush=True)


if __name__ == '__main__':
    main()
