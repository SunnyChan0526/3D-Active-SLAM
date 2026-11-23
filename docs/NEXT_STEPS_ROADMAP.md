# 邊緣運算板移植期間的工作路線圖

> 建立：2026-11-16｜更新：2026-11-23，Jetson 支援（commit `2f02faa`，`docker` 分支）之後；11-17 晚 PR #1 合併進 main（merge commit `314d3ae`）
> 硬體分兩階段：
> - **開發測試（現在）**：Jetson AGX Orin Developer Kit 64GB，JetPack 6.2（L4T R36.4.3，Ubuntu 22.04），電源模式 `MODE_30W`，eMMC 57 GB。
> - **最終部署**：AIR6N0-C-MB NX 載板（裸板）＋ Jetson Orin NX 16GB SOM ＋ 512GB SSD ＋ AIR6N0-C-DB NX 擴充板（4×USB3.2-A）。
> - AGX Orin 64GB 的效能數字**不能代表** Orin NX 16GB（GPU 核心約一半、CPU 核心較少、16 GB 由 CPU 與 GPU 共用），正式數字要在 NX（或 AGX 的 NX 模擬模式）上量。
>
> 原則：全程維持 `fsm/planning_only=true`；不為了 demo 放寬碰撞、膨脹半徑或動態限制。
> 搭配 [SYSTEM_OVERVIEW.md](SYSTEM_OVERVIEW.md)（系統說明與已知限制）、[RELATED_PAPERS.md](RELATED_PAPERS.md)（文獻與閱讀順序）一起看。這份只放待辦與進度。

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
- [ ] **路徑（板子上已經會遇到，優先處理）**：還有 9 個 tracked 檔案含 `/home/sunny`（Jetson 上的帳號是 `nvidia`）；launch 裡寫死了 `$(env HOME)/Desktop/ActiveSLAM_move2Laptop`，要改成 `$(find pkg)` 或環境變數。
- [ ] Jetson 上的 repo 是 GitHub ZIP 匯入的快照（`docker` 分支，`63fdf7f` → `2f02faa`），不是 `main` 的 clone；要把 Jetson 上的修改整理成 PR 同步回 GitHub，之後在板子上改用 `git clone`。
- [ ] 刪除已合併的分支 `fix/slc-candidates-and-semantic-bag`（本機與 GitHub）。

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
- [ ] **磁碟**：每輪 bag 2–4 GiB（加錄語意後會更大），腳本在剩餘不到 6 GiB 時會拒絕啟動。筆電只有 60 GB；AGX Orin 的 eMMC 57 GB 只剩約 12 GB（11-23，Docker image 佔掉大半），在 AGX 上錄製要先接外接 SSD 或錄完就搬走。最終板子有 512GB SSD，系統與 Docker 資料放 SSD 後這個問題基本解決。
- [ ] 決定 IR emitter 的實驗設定（開或關），記錄在每輪的 metadata 裡，比較時要用相同的設定。
- [ ] 場景組：物件多、**物件少**（之後拿來驗證 RAVEN 的特徵點 loop closure 備援）、繞一圈回到起點、白牆走廊（測 VIO 漂移）。每種錄 3 次以上；ground truth 用 AprilTag 加捲尺。**優先用 ground truth 驗證 11-17 那次 0.8 m 的 SLC 修正是否正確。**
- [ ] 注意：原作者實際上**只把椅子**建成地標（`process_cloud_node.py` 只取標號 1）；11-18 起手持設定改為椅子、餐桌、電視三類（`object_class_labels`），基線實驗要記得設回 `[1]`。場景設計要避免一排等距、長得一樣的椅子（11-18 實測會造成比對無法確定），並讓桌子、電視和椅子能一起被看到。
- [ ] 指標：回到起點時的位置與 yaw 誤差、物件間距離誤差、SLC 成功率與誤判次數、pose 協方差 trace。
- [ ] 對照實驗都用同一批 bag 重播，每種設定跑多次。限制：bag 只能評估感知和 SLAM 這一段，規劃好不好要靠模擬或實飛。
- [ ] 手持測試要固定起點與起始朝向：世界座標以啟動時相機為原點，起始朝向＝+Y、左＝-X；房間範圍（`ACTIVE_SLAM_ROOM_*`）與高度範圍都依此計算。

## 步驟 3｜效能剖析與輕量化（在 Jetson 上做）
- [ ] **目標是 Orin NX 16GB，不是 AGX**。在 AGX 上量到的數字只能當上限參考。可選：把 AGX Orin 開發套件用 NVIDIA 官方的模擬模式刷成 Orin NX 16GB 規格（`jetson-agx-orin-devkit-as-nx-16gb` 一類的設定），在載板到貨前取得接近實際的數字；重新刷機會清掉板子上的資料，要先備份。
- [ ] 每輪測試記錄電源模式（`nvpmodel -q`；AGX 目前 `MODE_30W`）。Orin NX 在 JetPack 6.2 有 MAXN Super 模式，能不能用取決於載板的供電與散熱，要向載板廠商確認。
- [ ] 量每個節點的 CPU、GPU、記憶體、頻率、延遲（可用 `tegrastats`／`jtop`）；也要量 `marginalCovariance` 和資訊增益 service 的耗時，以及耗時隨地圖變大的變化。
- [ ] **記憶體預算**：NX 只有 16 GB 且 CPU、GPU 共用，要量 Noetic 容器（SLAM、規劃）加 YOLO 容器的總用量，確認長時間運行不會 OOM。
- [ ] **迴環比對的耗時**：窮舉法隨偵測數呈階乘成長（14 個地標時 5／6／7 個偵測約 0.00／0.07／0.82 秒），板子上要重新量，必要時改成有剪枝的配對方法。
- [ ] 用步驟 2 補錄的 bag 比較 `yolov8n-seg`、`yolov8s-seg`、`yolov8x-seg` 對 SLAM 指標的影響；目前語意偵測已經限制在單執行緒、nice 10，也要記錄這個設定對頻率的影響。AGX 上 `yolov8x-seg` GPU（FP16，PyTorch）約 0.1 秒／張、CPU 約 3.5 秒（11-23）；NX 上預期會變慢，要重量，因此 n／s 版的比較更重要。
- [ ] 把 YOLO 轉成 ONNX，再轉 TensorRT（FP16）。**TensorRT engine 與 GPU 型號和 TensorRT 版本綁定，要在 Orin NX 上重新產生**，不能沿用 AGX 上建好的檔案。
- [ ] Python DBSCAN 太慢的話，改用 C++ 或降低取樣。

## 步驟 4｜移植準備 —— AGX Orin 上已跑起來（11-23）
- [x] 確定板子：開發測試用 AGX Orin 64GB，最終用 AIR6N0 載板＋Orin NX 16GB（見開頭）。JetPack 6.2 是 Ubuntu 22.04，沒有原生 Noetic，改用 Ubuntu 20.04／Noetic 的 Docker image。可以參考 Perception-Aware Exploration in Feature-Limited Environments（arXiv 2603.15605）在 Jetson Orin NX 上的配置。
- [x] ARM64 Docker（commit `2f02faa`）：主容器 `activeslam:noetic`（Ubuntu 20.04，torch 2.4.1、open3d 0.14.1，以 LD_PRELOAD 解決 libgomp 的 static TLS 問題；Jetson 上不開 GPU passthrough，因為主機的 L4T 函式庫和 20.04 不相容）；GPU YOLO 另外跑在 `activeslam-yolo-gpu:r36.4`（`dustynv/l4t-pytorch:r36.4.0`，CUDA 12.6），透過 localhost TCP 提供給 `detect.py`。其他依賴版本見 `local_migration_status.txt`：GTSAM 4.0.3、Ceres 2.0.0、fmt 8.0.0、glog 0.6.0、Sophus `49a7e128`、RealSense SDK 2.50.0。
- [ ] 未提交的 `docker/Dockerfile.rs` 要決定是否納入 repo。
- [ ] **向載板廠商確認 AIR6N0-C-MB 支援的 JetPack／L4T 版本與 BSP**。第三方載板通常要刷廠商提供的 BSP；最好和 AGX 一樣是 R36.4.x（JetPack 6.2），兩個 Docker image 才能直接沿用（YOLO 容器的 `r36.4` base 必須和主機 L4T 版本相符）。同時確認：從 NVMe SSD 開機、擴充板 4×USB3.2-A 的驅動、MAXN Super 是否支援。
- [ ] **到貨第一天檢查清單**：刷廠商 BSP 並把系統裝到 SSD → `nvpmodel` 設定並記錄電源模式 → 載入（或重建）兩個 Docker image → `setup/docker_smoke_test.sh` → 確認 RealSense D435i 接在 USB3 埠且以 USB 3.x 連線（`rs-enumerate-devices`）→ 重新產生 TensorRT engine → 重播同一批 bag，和 AGX、筆電的指標比較。

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
