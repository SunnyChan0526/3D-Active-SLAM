# 邊緣運算板移植期間的工作路線圖

> 建立：2026-11-16｜更新：2026-11-24，AGX Orin 上相機與手持流程修正（`docker` 分支 `e56e672`…`8f47739`）、PR #7（移除寫死路徑）與 PR #8（主機設定腳本）合併進 `docker`（`2e6990d`）之後；11-23 PR #5（Jetson 支援）合併進 `docker`；11-17 晚 PR #1 合併進 main（merge commit `314d3ae`）
> 硬體分兩階段：
> - **開發測試（現在）**：Jetson AGX Orin Developer Kit 64GB，JetPack 6.2（L4T R36.4.3，Ubuntu 22.04），電源模式 `MODE_30W`，eMMC 57 GB。
> - **最終部署（已確定，11-24）**：AIR6N0-C-MB NX 載板（裸板）＋ Jetson Orin NX 16GB SOM ＋ 512GB SSD ＋ AIR6N0-C-DB NX 擴充板（4×USB3.2-A），JetPack 6.2。
> - AGX Orin 64GB 的效能數字**不能代表** Orin NX 16GB（GPU 核心約一半、CPU 核心較少、16 GB 由 CPU 與 GPU 共用），正式數字要在 NX（或 AGX 的 NX 模擬模式）上量。
>
> 原則：全程維持 `fsm/planning_only=true`；不為了 demo 放寬碰撞、膨脹半徑或動態限制。
> 搭配 [SYSTEM_OVERVIEW.md](SYSTEM_OVERVIEW.md)（系統說明與已知限制）、[RELATED_PAPERS.md](RELATED_PAPERS.md)（文獻與閱讀順序）一起看。這份只放待辦與進度。

## 11-24 AGX Orin 實機測試後的結論（`docker` 分支）
- ✅ **相機在板子上穩定了**（D435i 接 Type-C，USB 3.2）。依序找到並修好四個問題：
  1. **librealsense 換成 2.54.2**（RSUSB 後端，`docker/Dockerfile.rs` → `activeslam:noetic-rs254`，`e56e672`）；Jetson 上 `docker/run.sh` 有這個 image 就自動使用，color 降到 15 fps。
  2. **PipeWire 的 v4l2 監控會搶相機**（IMU、color 起不來）：板子上以使用者設定 `~/.config/pipewire/media-session.d/media-session.conf` 關掉 v4l2 監控（系統設定，不在 repo）。
  3. **RViz 在容器裡用 CPU 算圖**，會搶相機節點：Jetson 上以 `nice -n 19` 啟動（`aca4a16`）。
  4. **驅動內建的 align_depth 在 Jetson CPU 上跟不上**，用光 frame pool 後深度／infra 的 USB 端點停住（watchdog），infra 整輪不再恢復、VINS 無法初始化。改成在獨立程序用 `depth_image_proc/register` 對齊（`setup/depth_register.launch`，`1e7384a`）。現在 infra 30、IMU 200、color 15、對齊深度 15 Hz，相機節點約 30% CPU。
- ✅ **VINS 延遲**：前端原本追蹤全部 30 fps，但後端只用一半，Jetson 上影像排隊、odometry 晚 0.46–0.9 秒，超過手持規劃 0.5 秒的新鮮度上限，規劃一直暫停。Jetson 上改成只追蹤後端會用的幀（`ACTIVESLAM_VINS_TRACK_USED_ONLY=1`，`8f47739`），延遲中位數 0.775 → 0.068 秒，規劃不再暫停。
- ✅ 相機靜止的完整流程（相機＋RViz＋rosbag＋語意＋規劃）：沒有節點掛掉，VINS 15 Hz、靜止漂移約 1 mm，語意點雲約 1.9 Hz，地圖約 4.3 Hz，規劃器有輸出路線。
- ⚠️ **還沒做移動中的手持測試**。前端改成每秒追蹤 15 幀，快速轉動時要確認不會跟丟。
- ⚠️ 之前在相機靜止時看過兩個問題，這次沒有重現，仍需追蹤：`active_slam_input_node` 加入語意因子時 gtsam `IndeterminantLinearSystemException`；VINS 偶爾發散（Eigen assertion）。
- ✅ **程式碼整理**：PR #7 移除執行路徑上的寫死路徑，在 AGX 上跑完整流程（相機＋RViz＋語意＋規劃）測過，結果和修改前相同；PR #8 加入主機設定腳本 `setup/jetson_host_setup.sh`，在 AGX 上跑過檢查模式，還沒 `--apply`。兩個都已合併進 `docker`。
- 操作注意：腳本異常結束時容器可能殘留，之後 `docker/run.sh` 會進到舊容器、ROS master 衝突。重跑前先 `docker ps`，有 `activeslam` 就 `docker stop activeslam`。

## 11-17 實機測試後的結論（main `314d3ae`）
- ✅ **SLC 端到端第一次真實成功**（`20261117_174344`，`clo96`）：候選 → COP 評估 → 排入路線 → 走到點、原地轉 → 比對成功 → `[Handheld Observed] clo96` → 因子圖加入迴環（`WILL ADD loop closure factor`）→ SLAM 位姿修正。
- ⚠️ **修正正確性未驗證**：那次位姿在 0.2 秒內跳了約 0.8 m，比對估計的朝向差 7.6°（上限約 9.7°）。可能是真實漂移，也可能是相似椅子誤配，要用步驟 2 的 ground truth 確認。
- ❗ **更正 11-17 早上的判斷**：「論文 VI-B 的 COP 重規劃條件（15% / 10%）已接上」**不正確**。手持模式送出 COP 的程式只寫在無人機分支，這兩個條件以前從未生效。現在已修好，並改成和原作者無人機版**程式**一致的「frontier 變化 ≥15% **且** 完成 ≥10%」。注意：**論文 VI-B 寫的是「或」**（見 `setup/PAPER_PLANNING_AUDIT.md`），11/12 版的「或」才符合論文，但手持相機下每秒成立，造成約 1 Hz 重算。目前的「且」是權宜做法，根本原因可能是 frontier 變化比例的算法（audit 第 7 點）。
- ✅ 已補上：`loop_closure_submap_node.py` 已啟動；候選參數改 ROS param；錄 bag 可加錄 color／aligned depth（`ACTIVE_SLAM_RECORD_SEMANTIC=true`）與不滾動刪除（`ACTIVE_SLAM_RECORD_FULL=true`）。
- ⚠️ 手持模式預設關閉 IR emitter，會影響深度品質與語意物件位置（未變）。

## 手持模式相對原論文的改動（寫實驗方法時要說明）
1. SLC key pose 高度夾進手持高度範圍 [z_min, z_max]，不再整個略過。
2. 出現從未交給 COP 的候選 id 時觸發重算（間隔至少 10 秒）。
3. 探索結束（沒有 frontier）但還有候選時，改為只走 SLC 點（一次一個、最近優先、每個只試一次）。
4. SLC 量測距離緩衝：0.5 m 內開始，超過 1.5 m 才取消（手持轉身時相機繞人畫半徑 0.3–0.5 m 的圓）。
5. 迴環比對只取最近 6 個偵測（`~max_measurements`）。原版 `estimate_bearingpos` 窮舉配對，11 個偵測對 14 個地標約 1.2e11 種組合，伺服器卡死。
6. SLC 資訊增益權重 f_sc 改為參數（預設 6＝原值）；測試時用過 30，**正式實驗一律用 6**。

## 步驟 0｜整理程式碼（大致完成）
- [x] Monorepo 加上 Git、`.gitignore`、模型下載腳本、上游版本紀錄。
- [x] 安裝並登入 `gh`（之後可以直接開 PR）。
- [x] 原 PROJECT_STATUS.md 改名為 SYSTEM_OVERVIEW.md，改成以 repo 為準，寫進手持自動模式與 11-17 的 SLC 結果；與本 roadmap 一起放進 `docs/`（11-17）。
- [x] README 裡的 clone 網址改成實際網址（11-17）。
- [ ] 清理：repo 裡還追蹤著 6 個 `.bak` 或 `*.before_*` 檔，以及 `src/kr_3d_active_ms_slam/backups/`（7.7 MB）。有 Git 歷史之後可以刪掉。根目錄的舊移植包 `kr3d_migration_20261103_161146*` 沒有進 git，只佔本機空間，確認不再需要就可以刪。
- [x] **路徑（11-24）**：執行路徑上的寫死路徑已移除——兩個 launch 的 VINS 設定改用 `$(find vins)/../config/...`、`vins_launch_prefix.sh` 改用 `$(dirname)`；`install_ros_base.sh` 的 log 目錄改由腳本位置推得；`tmux_sim_slam.sh` 改用 `$HOME`（PR #7，AGX 完整流程測試通過）。Docker 內的 `/home/evil1323/Desktop/ActiveSLAM_move2Laptop` 是容器內固定掛載點（`docker/run.sh` 由腳本位置找主機 repo），與主機帳號無關，保留。
  - [ ] 剩下：VINS 設定檔 `output_path`／`pose_graph_save_path` 寫死 `/home/evil1323/vins_output/`（容器內正確，原生安裝要改）；文件裡的 `~/Desktop/ActiveSLAM_move2Laptop` 範例路徑、`backups/`、`*_backup.yaml` 與 `*.original.yaml` 內的 `/home/sunny` 隨清理一併處理。
- [x] Jetson 上的修改已同步回 GitHub（11-24）：Jetson 支援經 PR #5 合併；之後的相機與 VINS 修正改接在 `origin/docker` 上推送。板子上的 repo 已設好 `origin` 並追蹤 `origin/docker`，原本的 ZIP 快照分支 `docker-zip-backup` 已刪除。
- [x] 刪除已合併的分支（11-24）：`fix/slc-candidates-and-semantic-bag`、`fix/hardcoded-paths`（PR #7）、`fix/jetson-host-setup`（PR #8）等。GitHub 上現在只剩 `main`、`docker`、`fix/slc-false-match-and-duplicates`。
- [ ] `docker` 合併回 `main`；之後刪除 `fix/slc-false-match-and-duplicates`（已合進 `docker`，還沒進 `main`）。

## 步驟 1｜讓語意 loop closure 真的觸發 —— ✅ 流程已打通（11-17）
- [x] 在 launch 加入 `loop_closure_submap_node.py`（跟隨 `start_loop`，不設 `use_sim_time`）。
- [x] 確認候選有發布，log 有 `Loop closure submap callback` 與 `[Plan Active Closure] Closure Utility`。
- [x] 候選參數改成 ROS param；小房間用 `cluster_min_samples=3`、`cluster_distance=2.0`、`max_key_pose_cluster_distance=4.0`。論文寫每群至少 3 個、程式原值 4，仍需確認哪個才對。
- [x] 實測：走到 SLC 點 → 原地轉 → 真實成功 → 因子圖加入迴環 → 位姿被修正。
- [ ] **收尾驗證（建議在步驟 2 之前）**：用 main 再跑 1–2 輪，確認比對上限 6 與 1.5 m 緩衝的效果，記錄 SLC 成功率（11-17 為 2 次嘗試中成功 1 次）。
- [ ] 已知問題：COP 偶爾回傳 0 個目標，系統約每秒重新請求，約 30 秒後自行恢復。
- [ ] 比對門檻（每個地標 8 cm、朝向 0.17 rad）在手持下是否過嚴，等有更多資料再決定；放寬會增加誤配。
- 參考：不確定原版流程是否正常時，用 `tmux_sim_closure_submap.launch` 在模擬裡對照；觸發規則可參考 Region Based SLAM-Aware Exploration（arXiv 2504.10416）。

## 步驟 2｜錄資料、建立 baseline
- [x] 在 `record_isolated_vins_test.sh` 補錄語意需要的 topic（color、aligned depth 與各自的 camera_info）：`ACTIVE_SLAM_RECORD_SEMANTIC=true`，約 25–45 MB/s。
- [x] 實驗用錄製可關掉滾動刪除：`ACTIVE_SLAM_RECORD_FULL=true`。
- [ ] **磁碟**：每輪 bag 2–4 GiB（加錄語意後會更大），腳本在剩餘不到 6 GiB 時會拒絕啟動。筆電只有 60 GB；AGX Orin 的 eMMC 57 GB 只剩約 12 GB（11-23，Docker image 佔掉大半），在 AGX 上錄製要先接外接 SSD 或錄完就搬走。最終板子有 512GB SSD，系統與 Docker 資料放 SSD 後這個問題基本解決。11-24 清理後剩約 13 GB；只錄 infra＋IMU（lz4）每分鐘約 0.8 GB，預設滾動保留 4 個 1 GB 分檔。
- [ ] 決定 IR emitter 的實驗設定（開或關），記錄在每輪的 metadata 裡，比較時要用相同的設定。
- [ ] 場景組：物件多、**物件少**（之後拿來驗證 RAVEN 的特徵點 loop closure 備援）、繞一圈回到起點、白牆走廊（測 VIO 漂移）。每種錄 3 次以上；ground truth 用 AprilTag 加捲尺。**優先用 ground truth 驗證 11-17 那次 0.8 m 的 SLC 修正是否正確。**
- [ ] 注意：原作者實際上**只把椅子**建成地標（`process_cloud_node.py` 只取標號 1）；11-18 起手持設定改為椅子、餐桌、電視三類（`object_class_labels`），基線實驗要記得設回 `[1]`。場景設計要避免一排等距、長得一樣的椅子（11-18 實測會造成比對無法確定），並讓桌子、電視和椅子能一起被看到。
- [ ] 指標：回到起點時的位置與 yaw 誤差、物件間距離誤差、SLC 成功率與誤判次數、pose 協方差 trace。
- [ ] 對照實驗都用同一批 bag 重播，每種設定跑多次。限制：bag 只能評估感知和 SLAM 這一段，規劃好不好要靠模擬或實飛。
- [ ] 手持測試要固定起點與起始朝向：世界座標以啟動時相機為原點，起始朝向＝+Y、左＝-X；房間範圍（`ACTIVE_SLAM_ROOM_*`）與高度範圍都依此計算。

## 步驟 3｜效能剖析與輕量化（在 Jetson 上做）
- [ ] **目標是 Orin NX 16GB，不是 AGX**。在 AGX 上量到的數字只能當上限參考。可選：把 AGX Orin 開發套件用 NVIDIA 官方的模擬模式刷成 Orin NX 16GB 規格（`jetson-agx-orin-devkit-as-nx-16gb` 一類的設定），在載板到貨前取得接近實際的數字；重新刷機會清掉板子上的資料，要先備份。
- [ ] 每輪測試記錄電源模式（`nvpmodel -q`；AGX 目前 `MODE_30W`）。Orin NX 在 JetPack 6.2 有 MAXN Super 模式，能不能用取決於載板的供電與散熱，要向載板廠商確認。
- [ ] 量每個節點的 CPU、GPU、記憶體、頻率、延遲（可用 `tegrastats`／`jtop`）。AGX 上已知的 CPU 瓶頸：VINS 前端特徵追蹤（已改為只追蹤 15 fps，vins_node 仍約 190% CPU）、深度對齊（已移出驅動）、RViz 軟體算圖；NX 的 CPU 更少，要重新確認這三項。也要量 `marginalCovariance` 和資訊增益 service 的耗時，以及耗時隨地圖變大的變化。
- [ ] **記憶體預算**：NX 只有 16 GB 且 CPU、GPU 共用，要量 Noetic 容器（SLAM、規劃）加 YOLO 容器的總用量，確認長時間運行不會 OOM。
- [ ] **迴環比對的耗時**：窮舉法隨偵測數呈階乘成長（14 個地標時 5／6／7 個偵測約 0.00／0.07／0.82 秒），板子上要重新量，必要時改成有剪枝的配對方法。
- [ ] 用步驟 2 補錄的 bag 比較 `yolov8n-seg`、`yolov8s-seg`、`yolov8x-seg` 對 SLAM 指標的影響；目前語意偵測已經限制在單執行緒、nice 10，也要記錄這個設定對頻率的影響。AGX 上 `yolov8x-seg` GPU（FP16，PyTorch）約 0.1 秒／張、CPU 約 3.5 秒（11-23）；NX 上預期會變慢，要重量，因此 n／s 版的比較更重要。
- [ ] 把 YOLO 轉成 ONNX，再轉 TensorRT（FP16）。**TensorRT engine 與 GPU 型號和 TensorRT 版本綁定，要在 Orin NX 上重新產生**，不能沿用 AGX 上建好的檔案。
- [ ] Python DBSCAN 太慢的話，改用 C++ 或降低取樣。

## 步驟 4｜移植準備 —— AGX Orin 上已跑起來（11-23）
- [x] 確定板子：開發測試用 AGX Orin 64GB，最終用 AIR6N0 載板＋Orin NX 16GB（見開頭）。JetPack 6.2 是 Ubuntu 22.04，沒有原生 Noetic，改用 Ubuntu 20.04／Noetic 的 Docker image。可以參考 Perception-Aware Exploration in Feature-Limited Environments（arXiv 2603.15605）在 Jetson Orin NX 上的配置。
- [x] ARM64 Docker（commit `2f02faa`）：主容器 `activeslam:noetic`（Ubuntu 20.04，torch 2.4.1、open3d 0.14.1，以 LD_PRELOAD 解決 libgomp 的 static TLS 問題；Jetson 上不開 GPU passthrough，因為主機的 L4T 函式庫和 20.04 不相容）；GPU YOLO 另外跑在 `activeslam-yolo-gpu:r36.4`（`dustynv/l4t-pytorch:r36.4.0`，CUDA 12.6），透過 localhost TCP 提供給 `detect.py`。其他依賴版本見 `local_migration_status.txt`：GTSAM 4.0.3、Ceres 2.0.0、fmt 8.0.0、glog 0.6.0、Sophus `49a7e128`、RealSense SDK 2.50.0（Jetson 上另有 2.54.2 的 `activeslam:noetic-rs254`）。
- [x] `docker/Dockerfile.rs` 已納入 repo（`e56e672`）：在 `activeslam:noetic` 上把 librealsense 換成 2.54.2（RSUSB）。build context 需要另外放 librealsense 原始碼壓縮檔與 CA bundle（見檔頭說明）；換 image 後 `realsense_ws` 要重建一次。
- [x] **板子上的系統設定已寫成腳本（11-24）**：`setup/jetson_host_setup.sh`（預設只檢查，`--apply` 套用），說明在 `setup/JETSON_HOST_SETUP.md`（PR #8，已合併；`--apply` 只在真的改了 PipeWire 設定時才重啟 pipewire）。PipeWire 關 v4l2 監控（使用者設定）；USB autosuspend 改成持久設定（systemd 開機寫入 -1，加上 RealSense udev `power/control=on`）；`uvcvideo` 只檢查不改（效果未證實）。
  - [x] AGX 上的檢查模式（11-24）：PipeWire 判斷 `[ok]`，和手動設定一致；autosuspend 目前是手動設的 -1；udev 規則與 systemd 服務尚未安裝；D435i 以 5000 Mb/s（USB 3）連線。
  - [ ] 在 AGX 上 `--apply`（需要 sudo 密碼，在相機沒串流時跑），重開機後再跑檢查模式，確認 autosuspend 仍是 -1、相機 `power/control=on`、串流正常。
- [ ] Jetson 專用的預設值都在 `docker/run.sh`（`ACTIVESLAM_COLOR_FPS=15`、`ACTIVESLAM_CAMERA_ALIGN=false`、`ACTIVESLAM_RVIZ_PREFIX="nice -n 19"`、`ACTIVESLAM_VINS_TRACK_USED_ONLY=1`）；到 NX 上要逐項重新驗證。
- [x] **NX 上用 JetPack 6.2**（11-24 確定）：和 AGX 一樣是 L4T R36.4.x，兩個 Docker image 可以直接沿用（YOLO 容器的 `r36.4` base 必須和主機 L4T 版本相符）。
- [ ] **仍要向載板廠商確認**：是否要刷廠商提供的 BSP（第三方載板通常需要）、能否從 NVMe SSD 開機、擴充板 4×USB3.2-A 的驅動、載板的供電與散熱是否支援 MAXN Super。
- [ ] **到貨第一天檢查清單**：刷廠商 BSP 並把系統裝到 SSD → `bash setup/jetson_host_setup.sh --apply` → `nvpmodel` 設定並記錄電源模式 → 載入（或重建）兩個 Docker image → `setup/docker_smoke_test.sh` → 確認 RealSense D435i 接在 USB3 埠且以 USB 3.x 連線（`rs-enumerate-devices`）→ 重新產生 TensorRT engine → 重播 1–2 個 AGX 上錄的 bag，確認定位、語意、規劃的結果和 AGX 相近（這是移植檢查，不是板子之間的比較實驗），並量 NX 的 CPU、記憶體與延遲 → 重新驗證 `docker/run.sh` 的 Jetson 預設值。

## 步驟 5｜飛行前的閉環驗證（模擬）
- [ ] 先在原專案的模擬（`tmux_sim_slam.sh`、mrsl_quadrotor、kr_mav_control）跑完整的探索、規劃、軌跡閉環，也可以當作 SLC 流程的參考答案。
- [ ] 接上 PX4 SITL 和 MAVROS offboard，在 Gazebo 驗證。
- [ ] 安全機制：VIO 發散時懸停或降落、geofence、遙控器隨時切回手動；先用繩子拴著或在網室裡飛。
- [ ] 硬體：用 Kalibr 做相機與 IMU 的標定、時間同步、減震安裝方式。
- [ ] 機載運算：Orin NX＋AIR6N0 載板＋擴充板的重量、尺寸、供電（電池到載板的電壓範圍）與散熱，要納入機體設計與飛行時間估算。

## 步驟 6｜論文主軸（同時進行）
- [ ] 照 [RELATED_PAPERS.md](RELATED_PAPERS.md) 的建議順序讀：Tao → RAVEN → Region-Based → Perception-Aware；Related Work 優先引用 Placed et al.（T-RO 2023）。
- [ ] 優先確認那篇 ⚠️ 的《Perception-aware active SLAM for MAVs》（*Aerospace* 2025），它和 RAVEN 的主題很接近，可能會撞題。
- [ ] **重規劃條件**：論文 VI-B 是「或」，原作者程式與目前手持模式是「且」。檢查 frontier 變化比例的算法（`evaPlannedFrontierChanged`／`isFrontierChanged`，手持時任何一格更新就算整個 frontier 變化），修好後改回論文的「或」；寫論文時要說明採用哪一種。
- [ ] 效用權重：`* 6` 是 f_sc，現在是參數 `active_closure/ig_weight`。先對照論文公式。11-17 實測佐證兩個疑點：frontier 效用有除以距離、SLC 效用沒有；SLC 效用隨時間累積的不確定度從約 0 漲到 60（權重 6）。選了之後會 `i++` 也仍需確認（可到原作者 GitHub 開 issue）。確認後再加入 RAVEN 的 λ 參數。
- [ ] VINS 發散的調查（IR 投影點、快速旋轉，見 `local_migration_status.txt`）會影響所有實驗，請把結論記下來。
- [ ] 基線：Tao 原版加 FALCON。RAVEN 也跟 FALCON 比較過，所以可以間接和 RAVEN 對照；RAVEN 程式碼釋出後再直接比較。
- [ ] 1 到 2 個月內寫下一頁的貢獻定義和實驗設計；可以從 RAVEN 的三個想法裡，選一到兩個能在手持階段驗證的作為主軸（特徵點 loop closure 備援、λ 優先順序）。
- [ ] 先寫 Related Work 和原方法的摘要章節。
