# Jetson (JetPack 6 / L4T r36.4) GPU YOLO server. See docker/yolo_gpu.sh.
# Base image ships CUDA 12.6, cuDNN, CUDA-enabled torch 2.4.0 and OpenCV.
FROM dustynv/l4t-pytorch:r36.4.0

# The base image points pip at a Jetson mirror; use PyPI for the pure-Python
# packages. --no-deps keeps the CUDA torch/torchvision/OpenCV from the base.
ENV PIP_INDEX_URL=https://pypi.org/simple \
    PIP_TRUSTED_HOST=

RUN pip3 install --no-cache-dir --no-deps 'ultralytics==8.0.38' 'thop==0.1.1.post2209072238' \
    && pip3 install --no-cache-dir 'pyyaml' 'tqdm' 'pandas' 'matplotlib' 'seaborn' 'scipy' 'tensorboard' \
    && python3 -c "import torch, ultralytics; from ultralytics import YOLO; print('ultralytics', ultralytics.__version__, 'torch', torch.__version__)"

COPY yolo_server.py /opt/yolo_server.py
EXPOSE 8765
CMD ["python3", "/opt/yolo_server.py"]
