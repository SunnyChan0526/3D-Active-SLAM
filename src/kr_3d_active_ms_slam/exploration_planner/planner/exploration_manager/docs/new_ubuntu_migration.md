# 新 Ubuntu 環境移植與建置手冊

本文件把目前 D435i Planning-only 系統移植到另一台電腦。目標環境是 Ubuntu 20.04 + ROS Noetic；目前的 Ubuntu 20.04 與 ROS Noetic 已於 2025-05-31 結束標準支援，安裝來源可能需要使用封存套件庫。移植時保持 Noetic，不要自動升級 ROS 版本或改用 ROS 2。

## 封裝內容與邊界

在目前電腦執行以下匯出器，參數指定 USB 或可供新電腦讀取的位置：

```bash
cd /home/sunny/active_ms_slam_ws/src/kr_3d_active_ms_slam
./scripts/export_migration_bundle.sh /media/sunny/TRANSFER
```

匯出器會建立帶時間戳的資料夾，內有：

- `active_ms_slam_source.tar.gz`：完整主專案工作樹，包括目前的 tracked/untracked 修改、子模組內容、Planning Preview 和語意模型。保留 Git 資料以便檢查版本。
- `vins_fusion_source.tar.gz`：VINS-Fusion 完整 source/Git/config。包含目前未提交的相機模型、特徵追蹤、視覺化修改與 D435i 校正檔。
- `realsense_ros_source.tar.gz`：RealSense ROS wrapper source/Git。
- 套件、版本、Git 狀態及 SHA256 清單。

不封裝 Ubuntu/ROS 安裝本身、核心/USB 驅動、GPU 驅動、`build/devel/logs`、ROS 執行期地圖或 rosbag。這些應在新機安裝或重新生成；舊電腦的 Catkin build 產物不能安全搬到另一台電腦。新電腦需有網路安裝 Ubuntu/ROS/系統依賴。此匯出器只讀取來源，不會停止 ROS 或修改原工作區。

RealSense wrapper 目前是 `ros1-legacy` 分支，記錄的 source commit 為 `debadfaaa4a21c667c076ad2abacf69f9427c825`。主機目前的 librealsense SDK 為 2.58.4；需在新機確認 SDK 與 wrapper 能共同編譯、D435i IMU topic 正常。不要同時混用 ROS apt wrapper 與另一份 source wrapper。

## 新機安裝作業系統與 ROS

1. 安裝 Ubuntu 20.04.6 LTS 64-bit，建立一般使用者帳號。若只有更新版 Ubuntu，先不要照此指南直接建置；Noetic 的 ABI/apt 依賴不同。
2. 安裝 ROS Noetic Desktop Full、`python3-catkin-tools`、`python3-rosdep`、`python3-pip`、Git、CMake、編譯器與本專案 README 所列系統依賴。
3. Noetic 已 EOL，安裝 ROS 前先讓 Codex 根據當時 ROS 官方安裝/封存文件確認套件庫可用，再由使用者核准 `sudo apt` 操作。不要執行未確認來源的安裝腳本。
4. RealSense D435i 需 Intel librealsense SDK、udev rules 和相容的 `realsense-ros`。可使用本 Bundle 的 wrapper source；SDK/相機核心支援必須安裝到新機，而非從舊機複製已編譯 `.so`。

專案 README 列出的依賴包含 OMPL、GTSAM 4.0.3、Ceres、glog、Sophus、fmt、NLopt 與 Python 的 PyTorch/torchvision、scikit-learn、Open3D、Ultralytics、rosnumpy。請 Codex 先讀主專案 `README.md`、各 package `package.xml`、Bundle 的版本清單，確認套件來源及版本再安裝。不要把整份 `python_pip_freeze.txt` 直接 pip install；它含 Ubuntu 系統套件、ROS Python 套件及與 GPU 綁定的 PyTorch 版本，只作版本參考。

## 解開 source

先將 Bundle 複製到新機，例如 `~/TRANSFER/kr3d_migration_YYYYMMDD_HHMMSS`，再驗證雜湊：

```bash
cd ~/TRANSFER/kr3d_migration_YYYYMMDD_HHMMSS
sha256sum -c SHA256SUMS
```

在沒有同名舊資料的目錄解開；若路徑已存在，先選擇另一個空目錄，不要覆蓋既有工作區：

```bash
mkdir -p ~/active_ms_slam_ws/src ~/vins_ws/src ~/realsense_ws/src
tar -xzf active_ms_slam_source.tar.gz -C ~/active_ms_slam_ws/src
tar -xzf vins_fusion_source.tar.gz -C ~/vins_ws/src
tar -xzf realsense_ros_source.tar.gz -C ~/realsense_ws/src
```

預期主專案位於 `~/active_ms_slam_ws/src/kr_3d_active_ms_slam`，VINS 位於 `~/vins_ws/src/VINS-Fusion`，RealSense wrapper 位於 `~/realsense_ws/src/realsense-ros`。先檢查每個 Git 工作樹的狀態，確認 Bundle 保留了原本的 modifications/untracked files。

## 設定使用者路徑與相機校正

原機啟動文件有 `/home/sunny/...` 絕對路徑。新使用者應把 launch/config 中主機絕對路徑改成新家目錄，或改成 ROS package 路徑/`$(env HOME)`；不要全文取代任意出現的 `/home/sunny`，先逐筆檢查用途。主要需要更新：

- 主工作區 `devel/setup.bash` 路徑。
- `vins_node` 的 D435i YAML 路徑。
- `vins_ws/devel/setup.bash` 與 `realsense_ws/devel/setup.bash` 路徑。
- SLOAM、語意偵測、點雲處理與 Global COP launch 中可能使用的絕對路徑。

VINS 的 `config/realsense_d435i_sunny/` 校正資料已跟 VINS source 一起封裝。不可拿其他 D435i 的校正值取代，也不要改 camera extrinsic、baseline、時間同步或 planner/map safety parameters 來消除建置/執行錯誤。

## 建置順序

在新機安裝好 Noetic 和系統依賴後，分開建置三個 Catkin workspace。先由 Codex 檢視 manifest、`package.xml` 與錯誤輸出；只修正建置必要項，避免批次改動規劃/SLAM 參數。

RealSense wrapper：

```bash
source /opt/ros/noetic/setup.bash
cd ~/realsense_ws
rosdep update
rosdep install --from-paths src --ignore-src -r -y --rosdistro noetic
catkin init
catkin config -DCMAKE_BUILD_TYPE=Release
catkin build
```

VINS-Fusion：

```bash
source /opt/ros/noetic/setup.bash
cd ~/vins_ws
rosdep install --from-paths src --ignore-src -r -y --rosdistro noetic
catkin init
catkin config -DCMAKE_BUILD_TYPE=Release
catkin build
```

主工作區：

```bash
source /opt/ros/noetic/setup.bash
cd ~/active_ms_slam_ws
rosdep install --from-paths src --ignore-src -r -y --rosdistro noetic
catkin init
catkin config -DCMAKE_BUILD_TYPE=Release
catkin build
```

若 `rosdep` 遇到自建套件或無 rosdep key，依錯誤確認 README 指定的系統依賴，不要直接忽略依賴。完成後記錄完整編譯結果及未解決警告。

## 新機驗證與 Planning-only 啟動

先 source setup 並驗證 package/launch 可解析，不接上 UAV 控制器：

```bash
source /opt/ros/noetic/setup.bash
source ~/realsense_ws/devel/setup.bash
source ~/vins_ws/devel/setup.bash
source ~/active_ms_slam_ws/devel/setup.bash
rospack find exploration_manager
roslaunch exploration_manager real_robot_planning_preview.launch --nodes
```

`real_robot_planning_preview.launch` 明確將 `fsm/planning_only` 設為 `true`。啟動後也要以 `rosparam get /planning_preview_node/fsm/planning_only` 確認值為 `true`。不得啟動舊的執行型 FSM launch，不得呼叫 arm/takeoff/motor/trajectory/controller service/action。

硬體試跑須由使用者在新機確認 D435i 畫面/IMU、VINS odometry、SLOAM odometry、Global COP Server topic/service 都正常後再進行。先開預覽 node 與專用 RViz、檢查 map 和 odometry，再由使用者明確觸發 `rosrun exploration_manager preview_control.py start`。編譯與唯讀檢查不需要接 UAV，也不等於飛行安全認證。

## 交給新環境 Codex 的任務文字

將以下文字與 Bundle 一起提供給新機 Codex：

> 請先閱讀 `new_ubuntu_migration.md` 和 Bundle manifests，檢查新機 Ubuntu/ROS 版本及磁碟空間，再按文件解開及建置三個 Catkin workspace。先做唯讀盤點並列出需要 `sudo`/網路的步驟，未核准前不要執行系統安裝。保持 `fsm/planning_only=true`，不要啟動 UAV 控制或執行型 FSM，不要觸發規劃。不要刪除或覆蓋既有 workspace、地圖、設定；修改檔案前先說明原因。若路徑、套件版本、校正或 SDK 不一致，先報告差異並停在安全的建置診斷階段。只有 build 成功後，才提供後續由我確認的硬體啟動步驟。

## 目前來源機參考資訊

- OS: Ubuntu 20.04.6 LTS; ROS: Noetic.
- VINS-Fusion source commit: `be55a937a57436548ddfb1bd324bc1e9a9e828e0`，有未提交變更與 D435i 設定；以 Bundle 為準。
- RealSense ROS source commit: `debadfaaa4a21c667c076ad2abacf69f9427c825`，`ros1-legacy` 分支。
- 主專案與子模組有未提交/未追蹤的修改；以完整封裝為準，不可只 clone GitHub origin。
- D435i VINS calibration 在 `VINS-Fusion/config/realsense_d435i_sunny/`。
- Planning Preview 操作及 topic 說明見同目錄的 `planning_preview.md`。
