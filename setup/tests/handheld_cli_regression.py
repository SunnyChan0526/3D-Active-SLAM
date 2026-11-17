"""Offline CLI integration: fake ROS only, never connects to a ROS master."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

source = (Path(__file__).resolve().parent.parent / 'free_mapping_session.py').read_text()
source = source.replace('time.sleep(1)', 'time.sleep(0)')  # only skip startup countdown
with tempfile.TemporaryDirectory(prefix='handheld_cli_test_') as temporary:
    p = Path(temporary)
    (p / 'free_mapping_session.py').write_text(source)
    for package, module, kind in [('std_msgs','msg','String'),('std_srvs','srv','SetBool')]:
        (p / package).mkdir()
        (p / package / '__init__.py').write_text('')
        (p / package / (module+'.py')).write_text('class '+kind+': pass\n')
    (p / 'rospy.py').write_text('''import os,json
from pathlib import Path
def init_node(*a,**k): pass
def wait_for_service(*a,**k): pass
class Subscriber:
 def __init__(self,topic,kind,callback): callback(type('Message',(),{'data':'mock status'})())
 def unregister(self): pass
def ServiceProxy(*a,**k):
 def call(value):
  with Path(os.environ['SERVICE_LOG']).open('a') as f:f.write(json.dumps(value)+'\\n')
  return type('Response',(),{'success':True,'message':'ok'})()
 return call
''')
    env = dict(os.environ, ACTIVE_SLAM_HANDHELD_AUTO='true', PYTHONPATH=str(p),
               SERVICE_LOG=str(p/'services.jsonl'))
    result = subprocess.run([sys.executable,str(p/'free_mapping_session.py'),str(p)],
                            input='p\np\nq\n',text=True,capture_output=True,env=env,timeout=10)
    assert result.returncode == 0, result.stderr
    assert [json.loads(v) for v in (p/'services.jsonl').read_text().splitlines()] == [True,False]
    metadata = json.loads((p/'free_mapping_session.json').read_text())
    assert metadata['automatic_planning'] and not metadata['planning_attempts']
    assert 'end_wall_time' in metadata and len(metadata['status_events']) == 1
    assert result.stdout.index('剩餘 1 秒') < result.stdout.index('規劃已自動啟用')
    assert not (p/'auto_plan_result.json').exists()
    (p/'auto_plan_after_walk.py').write_text("import json,sys\nfrom pathlib import Path\np=Path(sys.argv[1]); f=p/'counter'; f.write_text(str(int(f.read_text())+1) if f.exists() else '1'); (p/'auto_plan_result.json').write_text(json.dumps({'trigger_sent':True,'status':'succeeded'}))\n")
    env['ACTIVE_SLAM_HANDHELD_AUTO'] = 'false'
    result = subprocess.run([sys.executable,str(p/'free_mapping_session.py'),str(p)],
                            input='p\np\nq\n',text=True,capture_output=True,env=env,timeout=10)
    assert result.returncode == 0, result.stderr
    assert (p/'counter').read_text() == '1'
print('CLI regression passed: automatic arming after preparation, no manual trigger in auto mode, q pauses/saves; manual mode remains one-shot.')
