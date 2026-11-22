# 在 Ubuntu 22.04（或任何 Linux）用 Docker 執行 ActiveSLAM

容器內是 Ubuntu 20.04 + ROS Noetic，依賴版本與 `setup/install_*.sh` 相同。
repo 不打包進映像，而是由 `docker/run.sh` 掛載進容器。改 code 不需要重 build 映像。

## 1. 主機一次性設定（22.04）

```bash
# Docker Engine（官方說明：https://docs.docker.com/engine/install/ubuntu/）
sudo apt install -y docker.io x11-xserver-utils
sudo usermod -aG docker $USER        # 登出再登入後生效

# RealSense udev rules 要裝在「主機」上
sudo cp setup/99-realsense-libusb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

建議登入時選擇「Ubuntu on Xorg」，RViz 在 Wayland 下比較容易出問題。

（選用）用 NVIDIA GPU 跑 RViz 和 YOLO：先安裝 NVIDIA 驅動和
[nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)，
執行 `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`。

## 2. 取得程式碼和模型

```bash
git clone git@github.com:SunnyChan0526/3D-Active-SLAM.git ~/Desktop/ActiveSLAM_move2Laptop
cd ~/Desktop/ActiveSLAM_move2Laptop
./scripts/download_models.sh
```

## 3. Build 映像（約 30–60 分鐘）

```bash
docker/run.sh build                         # 預設 CPU 版 PyTorch（與筆電驗證過的相同）
TORCH_VARIANT=cu121 docker/run.sh build     # 想讓 YOLO 用 GPU 時改用這行
```

## 4. 第一次進容器：編譯三個 workspace

```bash
docker/run.sh
# 以下在容器內執行
ACTIVE_SLAM_JOBS=4 bash setup/build_workspaces.sh
exit
```

編譯結果存在 Docker volume（`activeslam_realsense_ws`、`activeslam_vins_ws`、`activeslam_active_ms_slam_ws`）裡，
容器關掉也不會消失。之後改了 C++ 程式碼，在容器內 `cd ~/active_ms_slam_ws && catkin build <pkg>` 即可。

## 5. 執行

```bash
docker/run.sh bash setup/start_all_planning_only.sh   # 跟原本一樣的啟動腳本
docker/run.sh                                         # 容器已經在跑時，再開一個 shell
```

- 執行紀錄寫在 `setup/runs/`（就是 repo 本身），VINS 輸出寫在主機的 `~/vins_output/`。
- 容器使用者固定是 `evil1323`（UID 跟主機相同），所以 VINS yaml 裡的 `/home/evil1323/...` 不用改。
- 容器使用主機網路（`--network host`）。主機本身不要再開一個 roscore。

## 常見問題

| 狀況 | 處理 |
|---|---|
| `rs-enumerate-devices` 找不到相機 | 確認主機已裝 udev rules；拔插相機；`lsusb | grep 8086` |
| RViz 開不起來 / `could not connect to display` | 從桌面終端機執行；確認主機有 `xhost`；改用 Xorg session |
| 想強制開或關 GPU | `ACTIVESLAM_GPU=on` 或 `ACTIVESLAM_GPU=off docker/run.sh ...` |
| 想從頭重新編譯 workspace | `docker volume rm activeslam_realsense_ws activeslam_vins_ws activeslam_active_ms_slam_ws` |
