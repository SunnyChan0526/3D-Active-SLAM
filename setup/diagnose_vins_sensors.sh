#!/usr/bin/env bash
set -eo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$setup_dir/source_active_slam.bash"
run_dir="$setup_dir/vins_sensor_checks/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$run_dir"
exec > >(tee "$run_dir/summary.log") 2>&1
python - "$run_dir" <<'PY'
import sys,time,json,math,statistics,bisect
from pathlib import Path
import rospy,cv2
from cv_bridge import CvBridge
from sensor_msgs.msg import Image,Imu,CameraInfo
rospy.init_node('vins_sensor_diagnosis',anonymous=True,disable_signals=True)
output=Path(sys.argv[1])
data={'left':[],'right':[],'imu':[]}
info={}; images={}
def image(msg,key):
    data[key].append([msg.header.stamp.to_sec(),time.time()])
    images[key]=msg
def imu(msg):
    a=msg.linear_acceleration;w=msg.angular_velocity
    data['imu'].append([msg.header.stamp.to_sec(),time.time(),a.x,a.y,a.z,w.x,w.y,w.z])
def camera_info(msg,key):
    info[key]={'width':msg.width,'height':msg.height,'K':list(msg.K),'D':list(msg.D),'P':list(msg.P),'frame':msg.header.frame_id}
subs=[rospy.Subscriber('/camera/infra1/image_rect_raw',Image,image,callback_args='left',queue_size=1,buff_size=2**24),
      rospy.Subscriber('/camera/infra2/image_rect_raw',Image,image,callback_args='right',queue_size=1,buff_size=2**24),
      rospy.Subscriber('/camera/imu',Imu,imu,queue_size=1000),
      rospy.Subscriber('/camera/infra1/camera_info',CameraInfo,camera_info,callback_args='left',queue_size=1),
      rospy.Subscriber('/camera/infra2/camera_info',CameraInfo,camera_info,callback_args='right',queue_size=1)]
print('Collecting sensor timing and calibration for 12 seconds. No nodes restarted or parameters changed.',flush=True)
end=time.monotonic()+12
while time.monotonic()<end and not rospy.is_shutdown():time.sleep(.1)
for sub in subs:sub.unregister()
for key,rows in data.items():
    print('\nSTREAM',key,'messages',len(rows))
    if len(rows)<2:continue
    stamps=[r[0] for r in rows];dt=[b-a for a,b in zip(stamps,stamps[1:])]
    print('header rate:',(len(rows)-1)/(stamps[-1]-stamps[0]) if stamps[-1]!=stamps[0] else 'invalid')
    print('header dt min/max:',min(dt),max(dt),'non-increasing stamps:',sum(v<=0 for v in dt))
    age=[r[1]-r[0] for r in rows]
    print('receipt age seconds median/max:',statistics.median(age),max(age))
    if key=='imu':
        acc=[math.sqrt(sum(v*v for v in r[2:5])) for r in rows]
        gyro=[math.sqrt(sum(v*v for v in r[5:8])) for r in rows]
        print('acceleration norm median/min/max:',statistics.median(acc),min(acc),max(acc))
        print('gyro norm median/max:',statistics.median(gyro),max(gyro))
right=sorted(r[0] for r in data['right'])
delta=[]
for row in data['left']:
    i=bisect.bisect_left(right,row[0]);near=right[max(0,i-1):i+1]
    if near:delta.append(min(abs(t-row[0]) for t in near))
if delta:print('\nStereo nearest timestamp difference median/max:',statistics.median(delta),max(delta),'over 3ms:',sum(v>.003 for v in delta),'of',len(delta))
config=Path.home()/'vins_ws/src/VINS-Fusion/config/realsense_d435i_sunny'
for key,filename in [('left','left.yaml'),('right','right.yaml')]:
    print('\nCAMERA INFO',key,info.get(key,'NO DATA'))
    if key not in info:continue
    storage=cv2.FileStorage(str(config/filename),cv2.FILE_STORAGE_READ)
    node=storage.getNode('projection_parameters')
    expected=[node.getNode(k).real() for k in ['fx','fy','cx','cy']]
    actual=[info[key]['P'][i] for i in [0,5,2,6]]
    print('Configured fx/fy/cx/cy:',expected)
    print('Live rectified fx/fy/cx/cy:',actual)
    print('Difference:',[x-y for x,y in zip(actual,expected)])
    storage.release()
    if key in images:cv2.imwrite(str(output/(key+'.png')),CvBridge().imgmsg_to_cv2(images[key],desired_encoding='passthrough'))
if 'right' in info and info['right']['P'][0]:print('CameraInfo right baseline (-P3/P0):',-info['right']['P'][3]/info['right']['P'][0])
(output/'measurements.json').write_text(json.dumps({'streams':data,'camera_info':info}))
print('\nSaved diagnostic data to',output)
PY
ps -C vins_node -o pid,pcpu,pmem,etime || true
