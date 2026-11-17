"""Check current odometry, send one legacy planning-only trigger, save result."""
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import time

import rospy
from nav_msgs.msg import Odometry


def main():
    run_dir = Path(sys.argv[1])
    result = {"trigger_sent": False, "started_wall_time": time.time()}
    try:
        rospy.init_node('auto_plan_after_walk', anonymous=True, disable_signals=True)
        if rospy.get_param('/exploration_node/fsm/planning_only', False) is not True:
            raise RuntimeError('planning_only 必須為 true')
        samples = []

        def collect(msg):
            p = msg.pose.pose.position
            samples.append((time.monotonic(), msg.header.stamp.to_sec(),
                            msg.header.frame_id, (p.x, p.y, p.z)))

        subscriber = rospy.Subscriber('/vins_estimator/odometry', Odometry, collect)
        deadline = time.monotonic() + 5
        print('【規劃前檢查】請保持終點高度與朝向，檢查定位 5 秒。', flush=True)
        while time.monotonic() < deadline:
            time.sleep(.05)
        subscriber.unregister()
        if len(samples) < 40 or time.monotonic() - samples[-1][0] > .5:
            raise RuntimeError('定位資料不足或已中斷')
        bounds = [(rospy.get_param('/exploration_node/map_ros/global/map_min_boundary_' + axis),
                   rospy.get_param('/exploration_node/map_ros/global/map_max_boundary_' + axis))
                  for axis in 'xyz']
        origin = samples[0][3]
        for _, stamp, frame, xyz in samples:
            if frame != 'world' or not all(math.isfinite(v) for v in xyz):
                raise RuntimeError('定位座標無效')
            if not all(lo <= v <= hi for v, (lo, hi) in zip(xyz, bounds)):
                raise RuntimeError('目前位置超出地圖範圍；不觸發規劃')
            if math.sqrt(sum((v - o) ** 2 for v, o in zip(xyz, origin))) > .2:
                raise RuntimeError('5 秒內位置變化超過 20 公分；請保持相機固定')
        if not 0 <= rospy.Time.now().to_sec() - samples[-1][1] < .5:
            raise RuntimeError('定位時間戳過舊或異常')
        result['checked_position'] = samples[-1][3]
        log = run_dir / 'vins.log'
        offset = log.stat().st_size
        print('【自動單次規劃】定位檢查通過，現在送出一次 Planning-only 觸發。', flush=True)
        subprocess.run(['bash', str(Path(__file__).parent / 'trigger_legacy_plan_once.sh')], check=True)
        result['trigger_sent'] = True
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            with log.open(errors='replace') as stream:
                stream.seek(offset)
                text = stream.read()
            matches = re.findall(r'PLAN BEHAVIOR Result:\s*(\d+)', text)
            final = next((int(v) for v in matches if int(v) != 2), None)
            if final is not None:
                result['planner_result'] = final
                result['status'] = {0: 'no_frontier', 1: 'failed', 3: 'succeeded'}.get(final, 'unknown')
                print('【規劃結果】' + {0: '沒有可探索目標', 1: '規劃失敗，請保留紀錄',
                      3: '規劃成功，請在 RViz 查看路線'}.get(final, '未知結果，請檢查紀錄'), flush=True)
                break
            time.sleep(.2)
        else:
            result['status'] = 'result_timeout'
            print('【等待逾時】觸發已送出，30 秒內未看到最終結果；不會重複觸發。', flush=True)
    except Exception as error:
        result['status'] = 'check_or_trigger_failed'
        result['error'] = str(error)
        print('【自動規劃停止】' + str(error), flush=True)
    finally:
        result['ended_wall_time'] = time.time()
        (run_dir / 'auto_plan_result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
