# ActiveSLAM 系統總覽（SYSTEM_OVERVIEW）

> 2026-11-17 前名為 PROJECT_STATUS.md。

最後更新：2026-11-17（main `314d3ae`，PR #1 合併後）

用途：換電腦或開新的 Claude 對話時先讀這份，了解**系統是什麼、怎麼跑、有哪些已知限制**。
**要做什麼、做到哪**請看 [next_steps_roadmap.md](next_steps_roadmap.md)，這份不放待辦事項。

## 0. 快速說明

- **目標**：複現 Tao et al.〈3D Active Metric-Semantic SLAM〉（RA-L 2024，arXiv 2309.06950，DOI 10.1109/LRA.2024.3363542）。先在筆電＋RealSense D435i 上用手持方式驗證語意 SLAM 與主動語意 loop closure（SLC），再移植到無人機的邊緣運算板。之後計畫加入 RAVEN（arXiv 2610.37111）的想法。
- **原始碼**：GitHub monorepo `SunnyChan0526/3D-Active-SLAM`（私有），本機在 `~/Desktop/ActiveSLAM_move2Laptop`。三個 catkin workspace 的 `src/` 是指向 repo 的 symlink（見 README）。11-03 的 tar 移植包（`kr3d_migration_20261103_161146*`，沒有進 git）已過時，只當本機備份。
- **目前進度**：手持自動探索中，SLC 已經端到端打通（2026-11-17 第一次真實成功），但修正正確性還沒用 ground truth 驗證。詳見第 2 節。
- **安全規則**：開發期間一律維持 `fsm/planning_only=true`。不要啟動舊的執行型 FSM launch，不要呼叫 arm、takeoff、motor、trajectory、controller 相關的 service 或 action。不要為了讓 demo 跑起來而放寬碰撞、膨脹半徑、安全距離或動態限制。

## 1. 系統架構

### 1.1 環境（ASUS 筆電，2026-11-05 移植完成）

| 項目 | 版本 |
|---|---|
| 作業系統 | Ubuntu 20.04.6 LTS x86_64 |
| ROS | Noetic（2025-05-31 已結束標準支援），catkin_tools 0.9.4 |
| 相機 | Intel RealSense D435i（RGB、深度、雙 IR、IMU） |
| RealSense SDK | 2.50.0（原桌機另有獨立 SDK 2.58.4） |
| 自行編譯的依賴 | GTSAM 4.0.3、Ceres 2.0.0、fmt 8.0.0、glog 0.6.0、Sophus `49a7e128`，裝在 `~/.local/opt/active-slam` |
| 環境設定 | `source ~/Desktop/ActiveSLAM_move2Laptop/setup/source_active_slam.bash` |

細節與建置紀錄見 `local_migration_status.txt`。

### 1.2 Repo 結構

| 路徑 | 對應 workspace |
|---|---|
| `src/kr_3d_active_ms_slam` | `~/active_ms_slam_ws` |
| `src/VINS-Fusion` | `~/vins_ws`（含 OpenCV 4 相容修改與 D435i 校正 `config/realsense_d435i_sunny/`，不要拿其他 D435i 的校正值取代） |
| `src/realsense-ros` | `~/realsense_ws`（ros1-legacy） |
| `setup/` | 安裝、建置、啟動、診斷腳本與說明 |
| `docs/` | 本文件與 roadmap |

上游來源與 base commit 見 `UPSTREAM.md`。不在 git 裡的東西：YOLO 權重（`scripts/download_models.sh`）、bag、build/devel、`setup/` 底下的每輪資料、`*.log`。

### 1.3 資料流

```
D435i ──► realsense2_camera ──┬─► VINS-Fusion（雙目＋IMU）──► /vins_estimator/odometry
                              │
                              └─► rgb_sem_segmentation/detect.py（YOLOv8x-seg）
                                        │ 語意點雲（只認 chair、dining table、tv）
                                        ▼
                     scan2shape_launch/process_cloud_node.py（DBSCAN、cuboid 擬合）
                                        │ 物件量測（range/bearing）
                                        ▼
              sloam/active_slam_input_node（GTSAM 語意因子圖、SLC action server、資訊增益 service）
                 │ /factor_graph_atl/quadrotor/high_freq_odom      ▲ DetectLoopClosure
                 │                                                 │
                 │                           loop_closure_server_node（物件配對求位姿）
                 ▼
  loop_closure_submap_node.py ──/factor_graph_atl/loop_closure_submap──► exploration_manager
  （SLC 候選：物件群＋對應的歷史 key pose）                   （frontier、COP、插入 SLC、手持 FSM）
                                                                     └─ global_plan_server_node（COP）
```

### 1.4 主要套件與職責

| 路徑（`src/kr_3d_active_ms_slam/` 底下） | 職責 |
|---|---|
| `semantic_detection/rgb_sem_segmentation/src/detect.py` | YOLOv8 實例分割，輸出語意點雲；類別對照在第 100 行（chair、dining table、tv） |
| `generic_sloam/scan2shape_launch/script/process_cloud_node.py` | 語意點雲分群、擬合物件，產生物件量測 |
| `generic_sloam/scan2shape_launch/script/loop_closure_submap_node.py` | 用 DBSCAN 把物件分群，產生 SLC 候選，發布到 `/factor_graph_atl/loop_closure_submap`；參數已改成 ROS param |
| `generic_sloam/sloam/src/core/activeSlamInputNode.cpp` | 因子圖主節點；active loop closure action server；資訊增益 service `/estimate_info_gain_server`；距離候選 key pose 8 m 內才送 DetectLoopClosure |
| `generic_sloam/sloam/src/factorgraph/graph.cpp` | GTSAM iSAM；資訊增益＝加入虛擬 loop closure 因子前後的協方差 trace 差 |
| `generic_sloam/loop_closure/` | `loop_closure_server_node`：把目前偵測到的物件和候選子地圖配對（`estimate_bearingpos`，窮舉配對；每個地標容許 8 cm、朝向 0.17 rad） |
| `exploration_planner/planner/exploration_manager/src/ms_exploration_manager.cpp` | frontier、COP、`planActiveLoopClosurePath`（約 1407 行起）、手持模式重算與 SLC 排程 |
| `exploration_planner/planner/exploration_manager/src/ms_exploration_fsm.cpp`、`handheld_fsm.cpp` | 探索狀態機；`handheld_fsm.cpp` 是手持自動模式（到達判定、SLC 量測等待、目標箭頭） |
| `exploration_planner/planner/exploration_manager/include/exploration_manager/handheld_policy.h` | 手持重算條件、到達判定等純函式（有回歸測試） |
| `GCOPTER_F250` | 軌跡最佳化 |

## 2. 手持自動探索模式（目前主要的測試方式）

### 2.1 怎麼跑

```bash
cd ~/Desktop/ActiveSLAM_move2Laptop
bash setup/start_auto_handheld_exploration.sh      # 加上需要的環境變數，見下表
```

只需要一個終端。腳本會依序開相機、倒數準備、啟動整個 planning-only 流程，同時在背景跑：
- `setup/slc_monitor.py`：終端顯示 `【SLC】` 里程碑，結束時印出七步檢查。
- `setup/handheld_direction_guide.py`：終端最下面一行顯示目標相對相機朝向的方向與距離；SLC 目標會標 `[SLC 點]`。

RViz 裡橘色箭頭是探索目標（`ftr`），紫色箭頭是 SLC 目標（`clo`）。輸入 `q` 結束。

### 2.2 常用環境變數（不設時行為與預設相同）

| 變數 | 用途 |
|---|---|
| `ACTIVE_SLAM_ROOM_FRONT/BACK/LEFT/RIGHT` | 起點到前／後／左／右牆的公尺數；同時縮小地圖邊界與更新範圍（邊距 `ACTIVE_SLAM_ROOM_MARGIN`，預設 0.3） |
| `ACTIVE_SLAM_HANDHELD_HEIGHT_LIMIT=true`、`_Z_MIN`、`_Z_MAX` | 觀察點與 SLC 點只放在指定高度範圍 |
| `ACTIVE_SLAM_SLC_CLUSTER_MIN_SAMPLES`、`_CLUSTER_DISTANCE`、`_MAX_KEY_POSE_CLUSTER_DISTANCE` 等 | SLC 候選參數（預設為原作者的大樓尺度） |
| `ACTIVE_SLAM_SLC_IG_WEIGHT` | SLC 資訊增益權重 f_sc，預設 6（原作者值）。**只有驗證流程時才調高，實驗一律用 6** |
| `ACTIVE_SLAM_RECORD_SEMANTIC=true` | 加錄 color、aligned depth，可離線重播語意部分（約 25–45 MB/s） |
| `ACTIVE_SLAM_RECORD_FULL=true` | 不滾動刪除，保留整輪 |

完整說明與每次修改紀錄見 `setup/AUTO_HANDHELD_EXPLORATION.md`、`setup/HANDHELD_HEIGHT_LIMITED.md`。

### 2.3 座標與場地

- 世界座標原點是**啟動時相機的位置**（含高度：z＝0 就是準備階段相機的高度）。
- 啟動時相機朝向＝+Y，左＝-X（四輪 bag 確認）。房間範圍與高度範圍都依此計算，所以**每次要從同一點、同一朝向啟動**。

### 2.4 每輪的輸出

放在 `setup/vins_full_pipeline_tests/<時間戳>/`：

| 檔案 | 內容 |
|---|---|
| `slc_summary.txt` | 七步檢查（候選節點 → 地標 → 候選 → 帶候選的路線 → 評估 → 插入 → 成功）、SLC 與 frontier 效用 |
| `slc_events.log` | SLC 相關事件時間軸 |
| `vins.log` | 所有規劃與 SLAM 節點的輸出（中文狀態在這個檔裡會變成 `???`，要用英文標籤搜尋） |
| `summary.log`、`resolved_params.yaml`、`mapper_room.yaml` | 終端輸出、實際參數、該輪房間範圍 |
| `sensors_*.bag` | 預設滾動保留約 4 GB |

筆電硬碟只有 60 GB，每輪 bag 2–4 GiB。剩餘空間少於 6 GiB 時腳本會拒絕啟動。

### 2.5 手持模式相對原論文的改動

1. **全域重算條件**：論文 VI-B 是「frontier 變化 ≥15% **或** 完成 ≥10%」。原作者程式是「且」。手持模式目前用「且」，因為用「或」時，手持相機每秒都讓 frontier 變化超過 15%，造成約 1 Hz 重算。根本原因可能在 frontier 變化比例的算法（見 `setup/PAPER_PLANNING_AUDIT.md` 第 7 點），還沒解決。
2. SLC key pose 的高度夾進手持高度範圍，不再整個略過。
3. 出現從未交給 COP 的 SLC 候選時觸發重算（間隔至少 10 秒）。
4. 探索結束後若還有候選，改為只走 SLC 點（一次一個、最近優先、每個只試一次）。
5. SLC 量測：0.5 m 內開始，離開超過 1.5 m 才取消（手持轉身時相機會繞著人畫圓）。
6. 迴環比對只取最近 6 個偵測（窮舉配對的耗時隨偵測數呈階乘成長）。
7. 到達判定改用真實位置與朝向（0.5 m、0.2 rad、保持 1 秒），不用軌跡時間推算。SLC 只計真實量測成功；失敗或 45 秒逾時都不算完成。

### 2.6 2026-11-17 實測結果

- `20261117_174344`：**第一次 SLC 真實成功**（`clo96`）。log 依序出現比對成功 → `[Handheld Observed] clo96` → `WILL ADD loop closure factor`。SLAM 位姿在 0.2 秒內修正約 0.8 m，比對估計的朝向差 7.6°（上限約 9.7°）。可能是真實漂移，也可能是相似椅子誤配，**還沒用 ground truth 驗證**。
- 同一輪第二個 SLC 點因為一次偵測到 11 個物體、比對器卡死而失敗（已修，見 2.5 第 6 點）。

## 3. 其他已完成的修改（11-03 前）

- **Planning-only 安全模式**（`ms_exploration_fsm.cpp`）：參數 `fsm/planning_only`。只允許 INIT、WAIT_TRIGGER、PLAN_BEHAVIOR、FINISH；規劃成功只做視覺化，不發布軌跡；擋掉 tracker 和 active loop closure 指令（手持自動模式例外：只送 SLC 量測請求，不送任何運動指令）。
- **多段路徑預覽**：`planning_preview_node.cpp`、`scripts/preview_control.py`、`real_robot_planning_preview.launch` 等；說明見 `exploration_manager/docs/planning_preview.md`。
- **D435i 與 VINS 座標系整合**：`activeSlamInputNode.cpp` 把 VINS 光學座標系姿態轉成機體座標（FLU）；`map_ros.cpp` 參數 `map_ros/vio_orientation_is_optical`；`process_cloud_node.py` 改用 world；`detect.py` 改用 ApproximateTimeSynchronizer（0.05 s）、mask resize 回原圖。
- **除錯與診斷**：A* 失敗原因統計（`astar2.cpp`）、目標 marker latched、視覺化擴充。
- **實機設定**：`mapper_sunny.yaml`（12×11 m 場地邊界）、`real_robot_planning_sunny.launch`、`run_indoor_large_scale_exploration_sunny.launch`、`sloam_active_slam_sunny.yaml`、`process_cloud_node_real_robot_sunny.yaml`、`rgb_segmentation_real_robot_sunny.launch`。

11-03 之後的修改都在 git 歷史裡（`git log`），不再另外列在這份文件。

## 4. 已知限制

- **效用單位不一致**：在 `planActiveLoopClosurePath` 中，frontier 效用＝資訊增益 ÷ 距離成本（約 1454 行）；SLC 效用＝資訊增益 × f_sc（約 1502 行），沒有除以距離。選了 SLC 之後也會 `i++`，等於跳過那個 frontier。是否為原作者刻意設計尚未確認。實測中 SLC 效用會隨不確定度累積，從約 0 漲到 60（f_sc＝6）。
- **候選參數原為大樓多樓層設計**：程式原值 `cluster_min_samples=4`，論文寫每群至少 3 個；小房間要調小。
- **迴環比對門檻嚴格**：每個地標容許 8 cm、朝向 0.17 rad；手持時大多比對失敗。放寬會增加誤配。
- **語意類別少**：只有 chair、dining table、tv 會成為地標。
- **IR emitter**：手持模式預設關閉（為了 VINS 特徵追蹤），會影響深度品質與物件位置。
- **COP 偶爾回傳 0 個目標**：系統約每秒重新請求，約 30 秒後自行恢復。
- **邊緣運算板效能未量測**：yolov8x-seg 很大；Python DBSCAN；每次評估 SLC 都要算 marginalCovariance；迴環比對隨偵測數階乘成長。
- **路徑寫死**：9 個 tracked 檔案含 `/home/sunny`；launch 裡寫死 `$(env HOME)/Desktop/ActiveSLAM_move2Laptop`。

## 5. 在新電腦上恢復環境

1. Ubuntu 20.04.6、ROS Noetic（套件來源可能要用封存庫）、RealSense SDK（在新機安裝，不要複製 `.so`）。
2. 依 `local_migration_status.txt` 的版本安裝 GTSAM、Ceres、fmt、glog、Sophus（安裝腳本在 `setup/install_*.sh`）。
3. Clone repo、下載模型、建 symlink：見 README 的「Fresh clone」。
4. 依序建置：`setup/build_workspaces.sh`（realsense → vins → active_ms_slam）。
5. 確認：`roslaunch ... --nodes` 只有預期的節點，`fsm/planning_only` 是 true。

舊的 tar 移植流程（`new_ubuntu_migration.md`）仍可參考依賴與 rosdep 例外，但原始碼一律以 repo 為準。

## 6. 參考文獻

| 論文 | 關係 |
|---|---|
| 3D Active Metric-Semantic SLAM（Tao，RA-L 2024，arXiv 2309.06950） | 本專案複現的對象；論文與程式差異整理在 `setup/PAPER_PLANNING_AUDIT.md` |
| RAVEN（Chen 等，T-RO 2026，arXiv 2610.37111） | 改進方向：特徵點 loop closure、λ 優先順序、感知導向軌跡（OFIF）。程式碼尚未公開 |
| Perception-Aware Autonomous Exploration in Feature-Limited Environments（RA-L 2026，arXiv 2603.15605） | 低紋理室內環境的 VIO 感知導向探索 |
| Region Based SLAM-Aware Exploration（arXiv 2504.10416） | 室內主動 loop closure 的觸發機制 |
| SlideSLAM（T-RO 2025，arXiv 2406.17249） | 同團隊的多機語意 SLAM |
| FALCON（HKUST，T-RO） | 開源探索基線 |
| LA-Planner（Robotics-STAR-Lab，arXiv 2503.15273） | 開源的感知導向規劃器 |
