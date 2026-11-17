#!/usr/bin/env bash
set -eEo pipefail
setup_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec > >(tee -a "$setup_dir/install_python_runtime.log") 2>&1
trap 'code=$?; echo "Python installation failed at line $LINENO (exit $code)."; exit "$code"' ERR
[[ "$EUID" != 0 ]] || { echo 'Run as your normal user, without sudo.'; exit 1; }
source /opt/ros/noetic/setup.bash
runtime="$HOME/.local/opt/active-slam-python"
if [[ ! -e "$runtime" ]]; then
  /usr/bin/python3 -m venv --system-site-packages "$runtime"
fi
[[ -f "$runtime/pyvenv.cfg" ]] || { echo "Not a venv: $runtime"; exit 1; }
python_bin="$runtime/bin/python"
"$python_bin" -m pip install 'pip==24.3.1' 'setuptools==75.3.2' 'wheel==0.45.1'
# CPU builds reproduce the recorded torch/torchvision versions without requiring CUDA.
"$python_bin" -m pip install 'torch==2.4.1+cpu' 'torchvision==0.19.1+cpu' \
  --index-url https://download.pytorch.org/whl/cpu
# numpy <1.24 retains aliases used by Noetic's ros_numpy.
"$python_bin" -m pip install 'numpy==1.23.5' 'scipy==1.10.1' \
  'scikit-learn==1.3.2' 'pandas==2.0.3' 'matplotlib==3.7.5' \
  'opencv-python==4.10.0.84' 'open3d==0.13.0' 'ultralytics==8.0.38' \
  'testresources==2.0.1'
"$python_bin" "$setup_dir/check_python_runtime.py"
"$python_bin" - <<'PY'
import rospy, tf, cv_bridge, ros_numpy
import numpy, scipy, sklearn, open3d, cv2, torch, torchvision
from ultralytics import YOLO
print('Python imports passed; torch:', torch.__version__)
print('numpy:', numpy.__version__, 'Open3D:', open3d.__version__)
PY
"$python_bin" -m pip freeze > "$setup_dir/python_runtime_installed.txt"
echo 'Python runtime installed. Activate it using source_active_slam.bash.'
