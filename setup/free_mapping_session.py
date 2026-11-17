"""Interactive free mapping with a single optional planning-only trigger."""
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time


def main():
    run_dir = Path(sys.argv[1])
    pids = [int(value) for value in sys.argv[2:]]
    metadata = {"mode": "free", "start_wall_time": time.time(),
                "recording_policy": "rolling 4 x 1024 MB split bags",
                "planning_attempts": []}

    def save():
        (run_dir / 'free_mapping_session.json').write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2))

    trigger_sent = False
    automatic = os.environ.get('ACTIVE_SLAM_HANDHELD_AUTO', 'false') == 'true'
    metadata['automatic_planning'] = automatic
    if os.environ.get('ACTIVE_SLAM_HANDHELD_HEIGHT_LIMIT', 'false') == 'true':
        metadata['handheld_height_limit'] = {
            'z_min_m': float(os.environ.get('ACTIVE_SLAM_HANDHELD_Z_MIN', '0.1')),
            'z_max_m': float(os.environ.get('ACTIVE_SLAM_HANDHELD_Z_MAX', '0.4')),
            'z_samples': int(os.environ.get('ACTIVE_SLAM_HANDHELD_Z_SAMPLES', '3'))}
    save()
    status_subscriber = None
    try:
        print('\a【初始化後保持靜止】再固定相機 10 秒，接著才開始自由建圖。', flush=True)
        for remaining in range(10, 0, -1):
            for pid in pids:
                os.kill(pid, 0)
            print('【保持靜止】剩餘 {} 秒'.format(remaining), flush=True)
            time.sleep(1)
        print('\a\n【自動探索啟動】請先等候路線或掃描提示。' if automatic else
              '\a\n【自由建圖已開始】現在可以慢走、轉彎、掃描環境，沒有路線或時間限制。', flush=True)
        if automatic:
            import rospy
            from std_msgs.msg import String
            from std_srvs.srv import SetBool
            rospy.init_node('handheld_auto_session', anonymous=True, disable_signals=True)
            metadata['status_events'] = []
            def status_callback(message):
                metadata['status_events'].append({'wall_time': time.time(), 'status': message.data})
                print('\a\n【自動探索】' + message.data, flush=True)
            status_subscriber = rospy.Subscriber('/exploration_node/handheld_status', String, status_callback)
            rospy.wait_for_service('/exploration_node/handheld_enable', timeout=30)
            response = rospy.ServiceProxy('/exploration_node/handheld_enable', SetBool)(True)
            if not response.success:
                raise RuntimeError(response.message)
            print('規劃已自動啟用：請依 RViz 青色軌跡與橘色目標移動，不需輸入 p。', flush=True)
        else:
            print('規劃：停在離障礙物約 1 公尺的位置，保持相機高度，輸入 p 再按 Enter。', flush=True)
        print('結束：輸入 q 再按 Enter，或 Ctrl+C。原始資料會持續錄製。', flush=True)
        print('資料位置：' + str(run_dir), flush=True)
        while True:
            for pid in pids:
                os.kill(pid, 0)
            readable, _, _ = select.select([sys.stdin], [], [], .5)
            if not readable:
                continue
            line = sys.stdin.readline()
            if not line:
                print('【結束】終端輸入已關閉，正在保存。', flush=True)
                break
            command = line.strip().lower()
            if command == 'q':
                print('【結束】正在保存並停止本輪節點，請稍候。', flush=True)
                break
            if command != 'p':
                print('輸入 q 再按 Enter 結束。' if automatic else '輸入 p 再按 Enter 規劃；輸入 q 再按 Enter 結束。', flush=True)
                continue
            if automatic:
                print('已自動規劃，不需要輸入 p；請依實際路線移動，輸入 q 結束。', flush=True)
                continue
            if trigger_sent:
                print('本輪單次規劃已觸發，不會再次送出。可繼續建圖或輸入 q 結束。', flush=True)
                continue
            subprocess.run([sys.executable, str(Path(__file__).parent / 'auto_plan_after_walk.py'),
                            str(run_dir)], check=True)
            result = json.loads((run_dir / 'auto_plan_result.json').read_text())
            metadata['planning_attempts'].append(result)
            trigger_sent = bool(result['trigger_sent'])
            save()
            print('【自由建圖繼續】查看 RViz 時請保持相機原高度；輸入 q 結束。', flush=True)
    except ProcessLookupError:
        metadata['end_reason'] = 'recording_or_pipeline_process_exited'
        print('【本輪停止】錄製或建圖程序已退出，正在保存並停止本輪；請查看 record.log 與 vins.log。', flush=True)
    finally:
        if automatic:
            try:
                if status_subscriber is not None:
                    status_subscriber.unregister()
                rospy.wait_for_service('/exploration_node/handheld_enable', timeout=2)
                rospy.ServiceProxy('/exploration_node/handheld_enable', SetBool)(False)
            except Exception:
                pass
        metadata['end_wall_time'] = time.time()
        save()


if __name__ == '__main__':
    main()
