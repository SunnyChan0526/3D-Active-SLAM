#!/usr/bin/env python3
"""Follow one run's vins.log and record the semantic loop closure (SLC) chain.

Writes <run_dir>/slc_events.log (timestamped events) and, on SIGTERM/SIGINT,
<run_dir>/slc_summary.txt. Only milestones are printed to the main terminal.
Reads ASCII tags only: Chinese status text is stored as '???' in vins.log.
"""
import re
import signal
import sys
import time
from pathlib import Path

run_dir = Path(sys.argv[1])
log_path = run_dir / 'vins.log'
events_path = run_dir / 'slc_events.log'
summary_path = run_dir / 'slc_summary.txt'
start = time.monotonic()
ansi = re.compile(r'\x1b\[[0-9;]*m')

count = dict(callbacks=0, nonempty_callbacks=0, no_pose=0, plans=0, plans_with_candidates=0,
             refresh=0, cop_sent=0, closure_only=0, height_clamped=0, utility=0, info_gain=0, closure_inserted=0, observed_ftr=0,
             observed_clo=0, match_ambiguous=0, match_too_large=0, match_rejected=0, closure_factor=0, skipped_ftr=0, skipped_clo=0, inaccessible=0, height_skip=0,
             ig_service_fail=0, traceback=0)
state = dict(params=None, landmarks_max=0, landmarks_last=0, candidate_ids=set(),
             last_candidates=None, collecting=None, last_utility=None, ftr_utils=[], clo_utils=[], node_died=False)
printed = set()
events = events_path.open('a', buffering=1)


def stamp():
    return '{} +{:6.1f}s'.format(time.strftime('%H:%M:%S'), time.monotonic() - start)


def event(text, milestone=None, color='96'):
    events.write('{}  {}\n'.format(stamp(), text))
    if milestone and milestone not in printed:
        printed.add(milestone)
        print('\r\033[K\033[1;{}m【SLC】{}\033[0m'.format(color, text), flush=True)


def finish_candidate_set():
    ids = state['collecting']
    state['collecting'] = None
    if ids is None:
        return
    count['callbacks'] += 1
    if not ids:
        return
    count['nonempty_callbacks'] += 1
    key = tuple(sorted(ids))
    state['candidate_ids'].update(ids)
    if key != state['last_candidates']:
        state['last_candidates'] = key
        event('candidates now: key_pose {}'.format(list(key)),
              'first_candidate', '92')


def handle(line):
    line = ansi.sub('', line)
    if state['collecting'] is not None and 'key_pose marker.ns:' not in line \
            and 'Loop closure submap callback' not in line:
        finish_candidate_set()
    m = re.search(r'\[loop_closure_submap_node\] (floor_height=.*)', line)
    if m:
        state['params'] = m.group(1).strip()
        event('candidate node started: ' + state['params'], 'node_started')
        return
    if 'process has died' in line and 'loop_closure_submap_node' in line:
        state['node_died'] = True
        event('ERROR candidate node died: ' + line.strip()[:200], 'node_died', '91')
        return
    if 'Traceback' in line:
        count['traceback'] += 1
        event('Traceback in vins.log (see vins.log)', 'traceback', '91')
        return
    m = re.search(r'allLandmarksMarkers size is: (\d+)', line)
    if m:
        n = int(m.group(1))
        if n != state['landmarks_last']:
            event('semantic landmarks: {}'.format(n))
        state['landmarks_last'] = n
        state['landmarks_max'] = max(state['landmarks_max'], n)
        return
    if 'Loop closure submap callback' in line:
        finish_candidate_set()
        state['collecting'] = set()
        return
    m = re.search(r'key_pose marker\.ns: key_pose_(\d+)', line)
    if m and state['collecting'] is not None:
        state['collecting'].add(int(m.group(1)))
        return
    if 'no candidate robot poses left' in line:
        count['no_pose'] += 1
        return
    m = re.search(r'\[Handheld COP\] Accepted refined tour with (\d+) targets', line)
    if m:
        count['plans'] += 1
        event('global tour accepted: {} targets'.format(m.group(1)))
        return
    if '[planActiveLoopClosurePath] Start planning' in line and state['candidate_ids']:
        count['plans_with_candidates'] += 1
        return
    if '[Handheld SLC]' in line:
        count['refresh'] += 1
        event('candidates appeared after tour was planned -> global refresh requested',
              'refresh', '93')
        return
    m = re.search(r'\[Handheld SLC-only\] No frontier left; guiding to closure key pose (\d+)', line)
    if m:
        count['closure_only'] += 1
        event('exploration finished; SLC-only goal: key pose ' + m.group(1), 'closure_only', '95')
        return
    if '[Handheld Height] Closure key pose' in line and 'clamped' in line:
        count['height_clamped'] += 1
        return
    if '[Handheld Refresh] Requesting global COP' in line:
        count['cop_sent'] += 1
        event('global COP request sent (keeping current goal)', 'cop_sent', '93')
        return
    m = re.search(r'\[Active Loop Closure\] FTR utility: (\S+)', line)
    if m:
        state['ftr_utils'].append(float(m.group(1)))
        return
    m = re.search(r'\[Plan Active Closure\] ?Closure Utility: (\S+)', line)
    if m:
        count['utility'] += 1
        state['last_utility'] = m.group(1)
        state['clo_utils'].append(float(m.group(1)))
        event('planner evaluated SLC, best utility = ' + m.group(1), 'utility', '92')
        return
    m = re.search(r'\[Plan Active Closure\] ?Info gain: (\S+)', line)
    if m:
        count['info_gain'] += 1
        event('SLC info gain = ' + m.group(1))
        return
    if '[planActiveLoopClosurePath] Adding closure node' in line:
        count['closure_inserted'] += 1
        event('SLC target inserted into tour (walk to it, then rotate in place)',
              'inserted', '92')
        return
    if 'Failed to call service estimate_info_gain_server' in line:
        count['ig_service_fail'] += 1
        event('ERROR estimate_info_gain_server call failed', 'ig_fail', '91')
        return
    if 'is not accessible from current position' in line:
        count['inaccessible'] += 1
        return
    if '[Handheld Height] Skip closure' in line:
        count['height_skip'] += 1
        event('closure key pose skipped by height limit: ' + line.strip()[-80:], 'height', '93')
        return
    m = re.search(r'goal_indices: (clo\d+)', line)
    if m:
        state['want_pos'] = m.group(1) != state.get('current_clo')
        state['current_clo'] = m.group(1)
        return
    m = re.search(r'goal  next_pos: (.+)', line)
    if m and state.get('want_pos'):
        state['want_pos'] = False
        pos = ' '.join('{:.2f}'.format(float(v)) for v in m.group(1).split()[:3])
        event('CURRENT TARGET IS SLC {} at ({}): walk there along the cyan path, then rotate slowly'
              .format(state['current_clo'], pos))
        print('\r\033[K\a\033[1;95m【SLC】現在的目標是語意迴環點 {}（{}）：沿青色線走過去，到了原地慢慢轉一圈。\033[0m'
              .format(state['current_clo'], pos), flush=True)
        return
    if 'goal_indices: ftr' in line:
        state['current_clo'] = None
        return
    m = re.search(r'\[Handheld Observed\] (\w+)', line)
    if m:
        tok = m.group(1)
        if tok.startswith('clo'):
            count['observed_clo'] += 1
            event('SLC SUCCEEDED: ' + tok, 'slc_ok', '92')
        else:
            count['observed_ftr'] += 1
            event('target completed: ' + tok, 'first_ftr_done', '92')
        return
    if 'AMBIGUOUS match rejected' in line:
        count['match_ambiguous'] += 1
        event('matcher: AMBIGUOUS fit rejected (' + line.split('places the robot')[-1].strip()[:40] + ')', 'ambiguous', '93')
        return
    if 'CORRECTION TOO LARGE' in line:
        count['match_too_large'] += 1
        event('matcher: correction too large, rejected (' + line.split('move the robot')[-1].strip()[:30] + ')', 'too_large', '93')
        return
    if 'residual on landmark positions is too large' in line:
        count['match_rejected'] += 1
        return
    if 'WILL ADD loop closure factor' in line:
        if time.time() - state.get('last_factor', 0) > 1.0:
            count['closure_factor'] += 1
            event('loop closure factor added to the factor graph', 'factor', '92')
        state['last_factor'] = time.time()
        return
    m = re.search(r'\[Handheld Skipped, NOT completed\] (\w+)', line)
    if m:
        tok = m.group(1)
        if tok.startswith('clo'):
            count['skipped_clo'] += 1
            event('SLC failed / skipped: ' + tok, 'slc_fail', '91')
        else:
            count['skipped_ftr'] += 1
            event('target skipped (not completed): ' + tok)


def summary():
    finish_candidate_set()
    c, s = count, state
    stages = [
        ('candidate node started', s['params'] is not None and not s['node_died']),
        ('>= 3 semantic landmarks', s['landmarks_max'] >= 3),
        ('candidates published and received', c['nonempty_callbacks'] > 0),
        ('global tour planned with candidates', c['plans_with_candidates'] > 0),
        ('planner evaluated SLC (Closure Utility)', c['utility'] > 0),
        ('SLC target inserted into tour', c['closure_inserted'] + c['closure_only'] > 0),
        ('SLC succeeded', c['observed_clo'] > 0),
    ]
    reached = 0
    for _, ok in stages:
        if not ok:
            break
        reached += 1
    hints = {
        0: 'candidate node not running: check vins.log for loop_closure_submap_node errors.',
        1: 'too few landmarks: walk past more objects YOLO can detect.',
        2: 'no candidate cluster: relax ACTIVE_SLAM_SLC_* params or walk more '
           '(no-candidate-pose discards: {}).'.format(c['no_pose']),
        3: 'no global tour after candidates appeared: refresh={}, COP sent={}.'.format(
            c['refresh'], c['cop_sent']),
        4: 'SLC never evaluated: look for "not accessible" / height-limit skips.',
        5: 'SLC evaluated but never inserted: utility/budget too low vs frontiers.',
        6: 'SLC target given but not confirmed: walk within 0.5 m and rotate slowly.',
    }
    lines = ['SLC summary for ' + str(run_dir), '']
    for i, (name, ok) in enumerate(stages, 1):
        lines.append('  {} {}. {}'.format('OK ' if ok else '-- ', i, name))
    lines += ['', 'Reached step {}/{}.'.format(reached, len(stages))]
    if reached < len(stages):
        lines.append('Next to check: ' + hints[reached])
    lines += ['', 'params: {}'.format(s['params']),
              'landmarks max/last: {}/{}'.format(s['landmarks_max'], s['landmarks_last']),
              'candidate key poses seen: {}'.format(sorted(s['candidate_ids'])),
              'last SLC utility: {}'.format(s['last_utility']),
              'SLC utility max: {}'.format(max(s['clo_utils']) if s['clo_utils'] else None),
              'frontier utility min/median: {}'.format(
                  '{:.3g}/{:.3g}'.format(min(s['ftr_utils']), sorted(s['ftr_utils'])[len(s['ftr_utils']) // 2])
                  if s['ftr_utils'] else None),
              '(SLC is inserted only when its utility beats the next frontier, or after exploration ends)',
              'counts:']
    lines += ['  {}: {}'.format(k, v) for k, v in c.items()]
    text = '\n'.join(lines) + '\n'
    summary_path.write_text(text)
    print('\r\033[K\033[1;96m' + '=' * 66 + '\n' + text + '=' * 66 + '\033[0m', flush=True)


stop = False


def on_signal(*_):
    global stop
    stop = True


signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

while not log_path.exists() and not stop:
    time.sleep(0.2)
with log_path.open('r', errors='replace') as f:
    while True:
        line = f.readline()
        if line:
            handle(line)
            continue
        if stop:
            break
        time.sleep(0.2)
summary()
events.close()
