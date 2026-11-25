# 邊緣運算板移植期間的工作路線圖

> 建立：2026-11-16｜更新：2026-11-25，每個步驟寫成具體做法（步驟 2 加入每輪標準流程：膠帶起點、捲尺量 SLC 點、評估）；每一項加上標題；2026-11-24 晚，步驟 2 的 ground truth 工具（`feat/ground-truth-step2`），並決定先以複現為主、ground truth 延後；2026-11-24，AGX Orin 上相機與手持流程修正（`docker` 分支 `e56e672`…`8f47739`）、PR #7（移除寫死路徑）與 PR #8（主機設定腳本）合併進 `docker`（`2e6990d`）之後；11-23 PR #5（Jetson 支援）合併進 `docker`；11-17 晚 PR #1 合併進 main（merge commit `314d3ae`）
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
- ⚠️ **修正正確性未驗證**：那次位姿在 0.2 秒內跳了約 0.8 m，比對估計的朝向差 7.6°（上限約 9.7°）。可能是真實漂移，也可能是相似椅子誤配，要用步驟 2 的 ground truth 確認（等複現成功後）。
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
- [x] **Git 化**：Monorepo 加上 Git、`.gitignore`、模型下載腳本、上游版本紀錄。
- [x] **GitHub CLI**：安裝並登入 `gh`（之後可以直接開 PR）。
- [x] **文件整理**：原 PROJECT_STATUS.md 改名為 SYSTEM_OVERVIEW.md，改成以 repo 為準，寫進手持自動模式與 11-17 的 SLC 結果；與本 roadmap 一起放進 `docs/`（11-17）。
- [x] **README 網址**：README 裡的 clone 網址改成實際網址（11-17）。
- [x] **路徑（11-24）**：執行路徑上的寫死路徑已移除——兩個 launch 的 VINS 設定改用 `$(find vins)/../config/...`、`vins_launch_prefix.sh` 改用 `$(dirname)`；`install_ros_base.sh` 的 log 目錄改由腳本位置推得；`tmux_sim_slam.sh` 改用 `$HOME`（PR #7，AGX 完整流程測試通過）。Docker 內的 `/home/evil1323/Desktop/ActiveSLAM_move2Laptop` 是容器內固定掛載點（`docker/run.sh` 由腳本位置找主機 repo），與主機帳號無關，保留。
- [x] **同步回 GitHub（11-24）**：Jetson 支援經 PR #5 合併；之後的相機與 VINS 修正改接在 `origin/docker` 上推送。板子上的 repo 已設好 `origin` 並追蹤 `origin/docker`，原本的 ZIP 快照分支 `docker-zip-backup` 已刪除。
- [x] **刪除已合併的分支（11-24）**：`fix/slc-candidates-and-semantic-bag`、`fix/hardcoded-paths`（PR #7）、`fix/jetson-host-setup`（PR #8）等。GitHub 上現在只剩 `main`、`docker`、`fix/slc-false-match-and-duplicates`。
- [ ] **清理備份檔**：repo 裡還追蹤著 6 個 `.bak` 或 `*.before_*` 檔，以及 `src/kr_3d_active_ms_slam/backups/`（7.7 MB）。有 Git 歷史之後可以刪掉。
  1. 開新分支，`git ls-files | grep -E '\.bak$|\.before_'` 列出要刪的檔案，確認沒有程式引用（`grep -rn` 檔名）後 `git rm`。
  2. `git rm -r src/kr_3d_active_ms_slam/backups`。
  3. 重新編譯一次、跑 `setup/docker_smoke_test.sh`，沒問題再開 PR。
  4. 本機根目錄的舊移植包 `kr3d_migration_20261103_161146*` 沒有進 git，確認不再需要就直接刪。
- [ ] **剩餘的寫死路徑**：VINS 設定檔 `output_path`／`pose_graph_save_path` 寫死 `/home/evil1323/vins_output/`（容器內正確，只有原生安裝要改）；文件裡的 `~/Desktop/ActiveSLAM_move2Laptop` 範例路徑，以及 `*_backup.yaml`、`*.original.yaml` 內的 `/home/sunny`，隨上一項清理一併處理。優先度低。
- [ ] **`docker` 合併回 `main`**：等步驟 1 的收尾驗證通過後再做。
  1. 開 PR：base `main`、head `docker`，說明寫「Jetson 支援＋相機與 VINS 修正＋SLC 誤配修正＋ground truth 工具」。
  2. 合併後刪除已併入的分支：`git push origin --delete fix/slc-false-match-and-duplicates`。
  3. 之後新功能一律從 `main` 開分支。

## 步驟 1｜讓語意 loop closure 真的觸發 —— ✅ 流程已打通（11-17）
- [x] **啟動候選節點**：在 launch 加入 `loop_closure_submap_node.py`（跟隨 `start_loop`，不設 `use_sim_time`）。
- [x] **確認候選有發布**：log 有 `Loop closure submap callback` 與 `[Plan Active Closure] Closure Utility`。
- [x] **候選參數**：改成 ROS param；小房間用 `cluster_min_samples=3`、`cluster_distance=2.0`、`max_key_pose_cluster_distance=4.0`。論文寫每群至少 3 個、程式原值 4，仍需確認哪個才對。
- [x] **實測 SLC 端到端**：走到 SLC 點 → 原地轉 → 真實成功 → 因子圖加入迴環 → 位姿被修正。
- [ ] **收尾驗證**：在 AGX 上用目前的 `docker` 分支（已包含 SLC 誤配修正：比對上限 6、1.5 m 緩衝、二義性拒絕、修正超過 1 m 拒絕）跑 2 輪，確認 SLC 仍然能成功。
  1. 照步驟 2「每輪標準流程」錄 2 輪，場景用會議室，椅子打散（不要排成等距的一排）。
  2. 每輪結束看 run 目錄的 `slc_summary.txt`：記下 SLC 嘗試次數、成功次數（`SLC SUCCEEDED`）、迴環因子加入次數，以及被拒絕的原因與次數（`AMBIGUOUS`、`CORRECTION TOO LARGE`、`residual ... too large`）。
  3. 每次迴環都照步驟 2 的方法量 SLC 點，用 `eval_ground_truth.py` 看修正是 `correct` 還是 `wrong`。
  4. **完成條件**：2 輪合計至少 1 次 SLC 成功，而且沒有 `wrong` 的修正。結果寫進 `docs/HANDHELD_SLC_TEST_REPORT.md`，和 11-17（2 次嘗試成功 1 次）比較。
- [ ] **已知問題：COP 回傳 0 個目標**：偶爾發生，系統約每秒重新請求，約 30 秒後自行恢復。
  1. 發生時記下 run 目錄和時間，保留 log。
  2. 在原作者的模擬裡（步驟 5）看有沒有同樣情形：有的話是原方法本來的行為，沒有的話是手持改動造成的，再往 COP 的輸入（候選、frontier 數量）查。
- [ ] **比對門檻是否過嚴**：比對門檻（每個地標 8 cm、朝向 0.17 rad）在手持下是否過嚴，累積至少 5 次 SLC 嘗試後再決定。
  1. 從各輪 `slc_summary.txt` 統計因 `residual on landmark positions is too large` 被拒絕的次數。
  2. 如果大部分失敗都是這個原因，而且量測結果顯示當時的漂移本來就很小，再考慮放寬；放寬會增加誤配，要和二義性拒絕一起看。
- [ ] **參考：用模擬對照**：不確定原版流程是否正常時，在模擬裡對照（步驟 5 第一項）。觸發規則可參考 Region Based SLAM-Aware Exploration（arXiv 2504.10416）。

## 步驟 2｜錄資料、建立 baseline
> 11-24 決定：**目前以複現為主，不做 AprilTag**。複現期間只用膠帶和捲尺做下面的「每輪標準流程」；AprilTag、四種場景等完整 ground truth 移到最後「複現成功後再做」，現在不用管。

### 每輪標準流程（複現期間每一輪都照做）
只需要膠帶、捲尺和筆。目的有兩個：每輪條件一樣才能比較；事後能判斷迴環修正對不對、回到起點差多少。

**A. 布置（每個房間做一次）**
1. **起點**：在地上貼一個十字膠帶當起點 O。
2. **朝向**：從 O 往正前方貼一條約 1 m 的膠帶當朝向線，這個方向就是世界座標的 +Y，左邊是 −X。
3. **量測用的第二點 B**：在朝向線的延長線上、距離 O 正好 2.00 m 的地方貼一個小十字 B。之後量 SLC 點只需要量到 O 和 B 的兩段距離。
4. **房間範圍**：從 O 量到前、後、左、右四面牆（或障礙物）的距離，填進 `ACTIVE_SLAM_ROOM_FRONT/BACK/LEFT/RIGHT`。
5. **起始高度**：決定起點時相機離地的高度（在手持高度範圍 0.3–0.5 m 內），每輪都用同一個高度。
6. **擺設紀錄**：拍一張房間全景照，記下椅子的擺法；同一組比較的每一輪都要一樣。
7. **場景檔**：複製 `setup/ground_truth/scene_template.yaml` 成這個房間的檔案（例如 `setup/ground_truth/meeting_room.yaml`），填 `start_camera_height_m`，`markers` 先只留 `start: {x: 0, y: 0, yaw_deg: 90}`，`tags` 和 `objects` 刪掉。

**B. 錄製**
1. 確認磁碟：`df -h` 看錄製位置至少有 15 GB（加錄語意約 25–45 MB/s）。AGX 上建議錄到外接 SSD：主機用 `ACTIVESLAM_RESULTS_DIR=<SSD 目錄> docker/run.sh` 啟動容器。
2. 相機放在 O 正上方、對準朝向線，保持不動直到 VINS 初始化完成。
3. 啟動（數值換成這個房間量到的）：
   ```bash
   ACTIVE_SLAM_SCENE=meeting_room ACTIVE_SLAM_RUN_NOTE="收尾驗證 第1輪" \
   ACTIVE_SLAM_GT_FILE=setup/ground_truth/meeting_room.yaml ACTIVE_SLAM_START_HEIGHT_M=0.40 \
   ACTIVE_SLAM_TEST_PIPELINE=full ACTIVE_SLAM_TEST_MODE=free ACTIVE_SLAM_HANDHELD_AUTO=true \
   ACTIVE_SLAM_RECORD_FULL=true ACTIVE_SLAM_RECORD_SEMANTIC=true \
   ACTIVE_SLAM_HANDHELD_HEIGHT_LIMIT=true ACTIVE_SLAM_HANDHELD_Z_MIN=0.3 ACTIVE_SLAM_HANDHELD_Z_MAX=0.5 \
   ACTIVE_SLAM_ROOM_FRONT=6.1 ACTIVE_SLAM_ROOM_BACK=2.15 ACTIVE_SLAM_ROOM_LEFT=3.26 ACTIVE_SLAM_ROOM_RIGHT=2.86 \
   ACTIVE_SLAM_SLC_CLUSTER_MIN_SAMPLES=3 ACTIVE_SLAM_SLC_CLUSTER_DISTANCE=2.0 \
   ACTIVE_SLAM_SLC_MAX_KEY_POSE_CLUSTER_DISTANCE=4.0 ACTIVE_SLAM_SLC_IG_WEIGHT=6 \
   bash setup/record_isolated_vins_test.sh
   ```
4. 照 RViz 的青色路線和橘色目標慢慢走。終端出現「【SLC】現在的目標是語意迴環點」時，走到該點、原地慢慢轉一圈。
5. **迴環成功時**：終端出現 `SLC SUCCEEDED` 和 `loop closure factor added` 之後，**相機原地不動**，輸入 `m slc1` 再按 Enter（第二次用 `slc2`，以此類推），然後在**相機正下方**的地上貼一小段膠帶、寫上 slc1。可以從相機垂一條綁重物的線來對準；要標的是相機的位置，不是腳的位置。
6. **結束**：走回 O，相機在 O 正上方、對準朝向線，輸入 `m start`，再輸入 `q` 結束。

**C. 錄完之後量測與評估**
1. 用捲尺量每個 slc 膠帶點到 O 的距離 d₀、到 B 的距離 d₁（公尺）。
2. 換算座標（B 在 O 前方 2 m）：
   - y = (d₀² − d₁² + 4) / 4
   - x = √(d₀² − y²)；點在朝向線**左邊**時 x 取負號
   - 例：d₀ = 2.50、d₁ = 1.80 → y = (6.25 − 3.24 + 4) / 4 = 1.75，x = √(6.25 − 3.07) ≈ 1.78，在右邊所以 x = +1.78
3. 把每個點加進場景檔的 `markers`，例如 `slc1: {x: 1.78, y: 1.75}`。注意每輪的 slc 點位置不同；可以每輪各存一份場景檔，或用 `r1_slc1` 這種名稱區分。
4. 評估：`python3 setup/eval_ground_truth.py <run_dir> --gt setup/ground_truth/meeting_room.yaml`
   - 每次迴環修正會得到 `correct`（修正後更接近真實位置，誤差 ≤ 0.3 m）、`partial`（變近但仍差 0.3 m 以上）或 `wrong`（離真實位置更遠，典型的配錯位）。
   - 最後一次 `start` 的誤差就是回到起點的誤差。
5. 錄完把 run 目錄搬到外接硬碟（`MYUSB/ActiveSLAM_bags/`），並在 roadmap 或測試報告記一行：日期、run 目錄、SLC 嘗試／成功次數、每次修正的判斷、回到起點誤差。

### 複現期間的設定與注意事項
- [x] **每輪自動寫 `run_metadata.yaml`（11-24）**：場景、IR emitter、地標類別、ig_weight、git commit、電源模式與相關參數。比較兩輪時，先對照 `key_settings` 確認設定相同。
- [x] **錄到外接 SSD（11-24）**：`ACTIVESLAM_RESULTS_DIR=<目錄> docker/run.sh` 掛進容器，錄製結果與磁碟檢查都改用這個位置。
- [x] **補錄語意 topic**：`ACTIVE_SLAM_RECORD_SEMANTIC=true` 加錄 color、aligned depth 與各自的 camera_info，約 25–45 MB/s，之後能用同一個 bag 重播比較不同設定。
- [x] **不滾動錄製**：`ACTIVE_SLAM_RECORD_FULL=true`，整輪都保留，才算得出回到起點誤差。
- [ ] **磁碟**：每輪 bag 2–4 GiB，加錄語意後一輪 5 分鐘約 8–13 GB；腳本在剩餘不到 6 GiB 時會拒絕啟動。AGX 的 eMMC 11-24 清理後只剩約 13 GB，所以**加錄語意時一定要錄到外接 SSD**，或每輪錄完就搬走。最終板子有 512GB SSD，系統與 Docker 資料放 SSD 後這個問題基本解決。
- [ ] **IR emitter 設定**：複現期間先維持預設（`ACTIVE_SLAM_DISABLE_IR_EMITTER=true`，關閉），所有輪次都用同一個設定，不要中途改。之後如果要比較開或關，用同一個房間、同一條路線各錄 2 輪，比較 VINS 是否發散、語意物件位置是否更準。
- [ ] **地標類別**：原作者實際上**只把椅子**建成地標（`process_cloud_node.py` 只取標號 1），11-18 起手持設定改為椅子、餐桌、電視三類。複現原方法時建議設 `ACTIVE_SLAM_OBJECT_CLASSES=1`；要用 `1,2,3` 也可以，但同一組比較要一致（`run_metadata.yaml` 會記錄）。
- [ ] **場景擺設**：避免一排等距、長得一樣的椅子（11-18 實測會造成比對無法確定，兩排打亂後才改善）。會議室的長桌和電視寬度超過 1 m，可能被物體大小上限（`cuboid_length/width_cutoff_upper: 1.0`）濾掉，錄完看 log 的地標數量確認；如果只剩椅子，更要把椅子擺得不規則。
- [ ] **用同一批 bag 重播對照**：比較不同設定（地標類別、YOLO 模型等）時用同一批 bag 重播，每種設定跑多次。完整流程的重播腳本還沒做（目前只有 `setup/replay_vins_without_mapping.sh`），需要時再補。限制：bag 只能評估感知和 SLAM 這一段，規劃好不好要靠模擬或實飛。

### 複現成功後再做（完整 ground truth，現在先不做）
> 詳細流程見 [setup/GROUND_TRUTH_PROTOCOL.md](../setup/GROUND_TRUTH_PROTOCOL.md)。工具已合併（PR #9），不使用時不影響任何預設行為。
- [x] **Ground truth 工具（11-24，尚未實機測試）**：錄製時輸入 `m <編號>` 留下 `/gt_marker`；場景檔範本 `setup/ground_truth/scene_template.yaml`；`setup/ground_truth/apriltag_offline.sh` 離線偵測 tag；`setup/eval_ground_truth.py` 算檢查點誤差、判斷每次迴環修正是對是錯，輸出 TUM 給 `evo`。評估程式有單元測試（`setup/tests/test_eval_ground_truth.py`）。
- [ ] **AprilTag 布置與檢查**：印 tag36h11（黑色方塊約 16 cm），貼在和相機差不多高的牆面，量每張 tag 的位置和朝向填進場景檔。先錄 1 輪 `isolated`，確認報告中的「檢查點 vs AprilTag」只差幾公分，再開始正式實驗。`apriltag_ros` 要在有 Noetic 的環境安裝（筆電，或板子的容器內）。
- [ ] **四種場景**：物件多、物件少（分 3 個與 0–2 個兩組；比對少於 3 個物體一定失敗，0–2 個那組是之後驗證 RAVEN 特徵點迴環備援的對照）、繞一圈回到起點（會議室可以繞長桌一圈）、白牆走廊（測 VIO 漂移，tag 只貼兩端）。每種錄 3 輪以上。
- [ ] **驗證 11-17 那次 0.8 m 的修正**：0.8 m 小於現在 1 m 的拒絕門檻，同樣的修正現在仍會被接受。11-17 那輪沒有記下實際位置，而且是滾動錄製，只能事後粗略判斷；主要做法是在同一個房間、和 11-18 15:07 同樣的擺法重現，照「每輪標準流程」標記迴環點，累積至少 3 次成功的迴環再下結論。
- [ ] **評估指標**：回到起點時的位置與 yaw 誤差、物件間距離誤差、SLC 成功率與誤判次數、pose 協方差 trace。評估程式已涵蓋回到起點誤差、檢查點誤差與迴環修正對錯；物件間距離誤差與協方差 trace 還沒做。

## 步驟 3｜效能剖析與輕量化（在 Jetson 上做）
> 目的：確認整套系統在最終的 Orin NX 16GB 上跑得動，找出最吃資源的部分再輕量化。每一項都要留下數字（寫進測試報告），之後才能和 NX 比較。
- [ ] **在 NX 規格上量（可先把 AGX 模擬成 NX）**：目標是 Orin NX 16GB，不是 AGX，在 AGX 上量到的數字只能當上限參考。
  - 選項 A：等 NX 到貨直接量（最準）。
  - 選項 B：先把 AGX 刷成 NVIDIA 官方的 NX 16GB 模擬設定（`jetson-agx-orin-devkit-as-nx-16gb`，做法見 NVIDIA Jetson Linux 開發者指南的模擬（Emulation）章節），可在載板到貨前取得接近的數字。刷機會清掉板子上所有資料，要先備份 repo 以外的東西（bag、Docker image、PipeWire 設定），而且之後還要刷回來。NX 如果很快到貨，不建議做。
- [ ] **記錄電源模式**：每輪測試前 `sudo nvpmodel -q` 記下模式（AGX 目前 `MODE_30W`，`run_metadata.yaml` 也會自動記錄）。比較數字時電源模式必須相同；有沒有跑 `sudo jetson_clocks`（鎖最高頻率）也要記下來。Orin NX 在 JetPack 6.2 有 MAXN Super 模式，能不能用取決於載板的供電與散熱，要向載板廠商確認。
- [ ] **各節點的 CPU、記憶體與延遲**：跑一輪標準流程（約 5 分鐘），同時記錄：
  1. 整機：主機上 `sudo tegrastats --interval 1000 --logfile <run_dir>/tegrastats.log`（CPU 各核心、GPU、RAM、溫度、功耗），結束後 `sudo tegrastats --stop`。
  2. 每個節點：容器內 `top -b -d 1 -n 300 > <run_dir>/top.log`，事後依程序名稱（`vins_node`、`active_slam_input_node`、`detect.py`、`process_cloud_node`、規劃節點、相機節點等）算平均 CPU 與記憶體。
  3. 頻率：`rostopic hz` 看相機（infra 30、IMU 200、color 15、對齊深度 15 Hz）、VINS odometry、語意點雲、地圖。
  4. 延遲：`rostopic delay /vins_estimator/odometry`（AGX 改成只追蹤 15 fps 後中位數約 0.068 秒，超過 0.5 秒規劃會暫停）。
  5. 已知的 CPU 瓶頸：VINS 前端（只追蹤 15 fps 後 vins_node 仍約 190% CPU）、深度對齊（已移出驅動）、RViz（NX 上不開，改在筆電看）。NX 的 CPU 更少，要重新確認這幾項。
  6. 還沒有計時的部分：`marginalCovariance` 和資訊增益 service 的耗時，以及耗時隨地圖變大的變化。要先在程式裡加計時的 log，才量得到。
- [ ] **記憶體預算（兩個容器合計）**：NX 只有 16 GB，CPU 和 GPU 共用。
  1. 從 `tegrastats.log` 的 RAM 欄位看整機用量隨時間的變化，跑久一點（至少 15–30 分鐘），確認不會一直上升。
  2. `docker stats --no-stream` 看 Noetic 容器（SLAM、規劃）和 YOLO 容器各用多少。
  3. **完成條件**：整機用量穩定，而且離 16 GB 至少留 2–3 GB 餘裕。
- [ ] **迴環比對的耗時**：窮舉法隨偵測數呈階乘成長（AGX 上 14 個地標時 5／6／7 個偵測約 0.00／0.07／0.82 秒），目前只取最近 6 個偵測。到 NX 上用同樣的方法重量；如果 6 個偵測就超過約 0.5 秒，改成有剪枝的配對方法，或把上限降到 5。
- [ ] **比較 YOLO 模型大小（n／s／x）**：
  1. 先讓 `docker/yolo_gpu.sh` 可以指定模型（目前寫死 `yolov8x-seg.pt`），並下載 `yolov8n-seg.pt`、`yolov8s-seg.pt`（`scripts/download_models.sh` 目前只下載 x 版）。
  2. 用同一批有 `RECORD_SEMANTIC` 的 bag 重播，每個模型各跑一次，比較：每張影像的推論時間（YOLO 伺服器 log）、語意點雲頻率、建出的地標數量和位置、SLC 是否仍能成功。
  3. AGX 上 `yolov8x-seg` GPU（FP16，PyTorch）約 0.1 秒／張、CPU 約 3.5 秒（11-23）。NX 的 GPU 約只有一半，n／s 版的比較更重要。
- [ ] **YOLO 轉 TensorRT**：在 YOLO GPU 容器裡用 ultralytics 匯出 FP16 engine（例如 `yolo export model=yolov8s-seg.pt format=engine half=True device=0`），再讓伺服器載入 `.engine` 檔，比較和 PyTorch 版的速度與偵測結果。**TensorRT engine 和 GPU 型號、TensorRT 版本綁定，要在 NX 上重新產生**，AGX 上建好的檔案不能沿用。
- [ ] **DBSCAN 加速**：先量 `process_cloud_node` 每次處理（DBSCAN 分群）花多久；如果明顯拖慢地標更新（例如超過語意點雲的間隔），再改用 C++ 實作或先降取樣點雲。

## 步驟 4｜移植準備 —— AGX Orin 上已跑起來（11-23）
- [x] **確定板子與作業系統**：開發測試用 AGX Orin 64GB，最終用 AIR6N0 載板＋Orin NX 16GB（見開頭）。JetPack 6.2 是 Ubuntu 22.04，沒有原生 Noetic，改用 Ubuntu 20.04／Noetic 的 Docker image。可以參考 Perception-Aware Exploration in Feature-Limited Environments（arXiv 2603.15605）在 Jetson Orin NX 上的配置。
- [x] **ARM64 Docker image**（commit `2f02faa`）：主容器 `activeslam:noetic`（Ubuntu 20.04，torch 2.4.1、open3d 0.14.1，以 LD_PRELOAD 解決 libgomp 的 static TLS 問題；Jetson 上不開 GPU passthrough，因為主機的 L4T 函式庫和 20.04 不相容）；GPU YOLO 另外跑在 `activeslam-yolo-gpu:r36.4`（`dustynv/l4t-pytorch:r36.4.0`，CUDA 12.6），透過 localhost TCP 提供給 `detect.py`。其他依賴版本見 `local_migration_status.txt`：GTSAM 4.0.3、Ceres 2.0.0、fmt 8.0.0、glog 0.6.0、Sophus `49a7e128`、RealSense SDK 2.50.0（Jetson 上另有 2.54.2 的 `activeslam:noetic-rs254`）。
- [x] **librealsense 2.54.2 image**：`docker/Dockerfile.rs` 已納入 repo（`e56e672`）：在 `activeslam:noetic` 上把 librealsense 換成 2.54.2（RSUSB）。build context 需要另外放 librealsense 原始碼壓縮檔與 CA bundle（見檔頭說明）；換 image 後 `realsense_ws` 要重建一次。
- [x] **NX 上用 JetPack 6.2**（11-24 確定）：和 AGX 一樣是 L4T R36.4.x，兩個 Docker image 可以直接沿用（YOLO 容器的 `r36.4` base 必須和主機 L4T 版本相符）。
- [x] **板子上的系統設定已寫成腳本（11-24）**：`setup/jetson_host_setup.sh`（預設只檢查，`--apply` 套用），說明在 `setup/JETSON_HOST_SETUP.md`（PR #8）。PipeWire 關 v4l2 監控（使用者設定）；USB autosuspend 改成持久設定（systemd 開機寫入 -1，加上 RealSense udev `power/control=on`）；`uvcvideo` 只檢查不改（效果未證實）。
  - [x] **AGX 上的檢查模式（11-24）**：PipeWire 判斷 `[ok]`，和手動設定一致；autosuspend 目前是手動設的 -1；udev 規則與 systemd 服務尚未安裝；D435i 以 5000 Mb/s（USB 3）連線。
- [ ] **在 AGX 上套用設定**：
  1. 相機沒在串流時（容器關掉），執行 `bash setup/jetson_host_setup.sh --apply`，需要 sudo 密碼。
  2. 重開機。
  3. 再跑 `bash setup/jetson_host_setup.sh` 檢查：autosuspend 仍是 -1、相機 `power/control=on`。
  4. 跑一次相機靜止的完整流程，確認串流正常。
- [ ] **向載板廠商確認**（到貨前問清楚，回覆記在這裡）：
  1. 是否要刷廠商提供的 BSP（第三方載板通常需要），對應哪個 JetPack 版本。
  2. 能否從 NVMe SSD 開機。
  3. 擴充板 4×USB3.2-A 是否需要額外驅動；D435i 接上去是否能以 USB 3 連線。
  4. 載板的輸入電壓範圍（決定電池怎麼接），以及供電與散熱是否支援 MAXN Super。
- [ ] **到貨第一天檢查清單**（依序做，每一步記下結果）：
  1. 刷廠商 BSP，系統裝到 SSD。
  2. `bash setup/jetson_host_setup.sh --apply`，重開機後再檢查一次。
  3. 設定 `nvpmodel`，記下電源模式。
  4. 載入（或重建）`activeslam:noetic-rs254` 和 `activeslam-yolo-gpu:r36.4` 兩個 image。
  5. `setup/docker_smoke_test.sh`。
  6. D435i 接在 USB3 埠，`rs-enumerate-devices` 確認以 USB 3.x 連線。
  7. 重新產生 TensorRT engine（如果步驟 3 已改用 TensorRT）。
  8. 重播 1–2 個 AGX 上錄的 bag，確認定位、語意、規劃的結果和 AGX 相近（這是移植檢查，不是板子之間的比較實驗），同時照步驟 3 量 CPU、記憶體與延遲。
  9. 逐項重新驗證 `docker/run.sh` 的 Jetson 預設值（`ACTIVESLAM_COLOR_FPS=15`、`ACTIVESLAM_CAMERA_ALIGN=false`、`ACTIVESLAM_RVIZ_PREFIX="nice -n 19"`、`ACTIVESLAM_VINS_TRACK_USED_ONLY=1`）：確認相機頻率、VINS 延遲都和 AGX 上一樣正常；RViz 在 NX 上不開。

## 步驟 5｜飛行前的閉環驗證（模擬）
> 目的：在真的讓無人機自己飛之前，先確認「規劃 → 控制 → 飛行 → 定位 → 再規劃」的循環能完整跑通，並準備好上機需要的安全機制和硬體。
- [ ] **跑原作者的模擬**（在筆電上；之前在筆電上跑過一次完整探索，當時沒留 log）：
  1. 執行 `src/kr_3d_active_ms_slam/exploration_planner/planner/exploration_manager/scripts/tmux_sim_slam.sh`：Gazebo Classic、`smallroom1` 世界（11 張椅子）、`dragon_ddk` 無人機、`kr_mav_control` 控制器；定位不跑 VINS，用真實位姿加人造漂移（`/gt_odom_perturbed`）。
  2. 用 `rqt_mav_manager` 啟動馬達、起飛，再觸發探索。
  3. 跑完後把 `~/.ros/log/latest/rosout.log` 複製保存，搜 `Loop closure submap callback`、`[Plan Active Closure]`、`WILL ADD loop closure factor`，確認 SLC 有沒有觸發、成功幾次。
  4. 拿來當手持的參考答案，對照：SLC 成功率和修正量（模擬的真實位置已知）、COP 是否也會回傳 0 個目標、重規劃多久一次（原版「且」的條件）、地標數量和實際的 11 張椅子差多少。
  5. 注意：模擬的漂移是人造的而且很平滑，修正量不能直接和實機比較；`smallroom1` 的椅子集中在一角，和會議室的擺法不同。
- [ ] **PX4 SITL＋MAVROS 介面驗證**：驗證你的系統接上真的飛控（PX4）之後能不能安全地飛。原專案沒有這部分，橋接程式要自己寫。
  1. 在 AGX 上先用 PX4 的 SIH（PX4 內建的簡單物理模擬，不需要 Gazebo 和 GPU）：用 PX4 官方的 arm64 容器 `px4io/px4-sitl`，`--network host` 執行。PX4 版本要和之後實飛的飛控韌體一致。
  2. Noetic 容器裡安裝 MAVROS（目前 image 只有 `ros-noetic-mavros-msgs`，要加 `ros-noetic-mavros` 和 GeographicLib 資料），`roslaunch mavros px4.launch fcu_url:=udp://:14540@127.0.0.1:14557`，確認 `/mavros/state` 顯示已連線。
  3. 寫橋接節點：把規劃器的軌跡（位置、速度、yaw）轉成 `/mavros/setpoint_raw/local`，持續送出（PX4 的 OFFBOARD 模式要求 setpoint 不能中斷）。
  4. 逐項驗證：
     - 座標轉換：SLAM 世界（起始朝向 +Y、左 −X）→ MAVROS 的 ENU → PX4 內部的 NED，下指令「往前 1 m」要真的往前。
     - 把 VINS odometry 餵給 PX4 的 EKF2（external vision），確認有被融合、延遲多少。
     - 規劃暫停或 setpoint 中斷時：有沒有持續送懸停指令；中斷時 PX4 會進 failsafe，行為要符合預期。
     - 解鎖 → 起飛 → 切 OFFBOARD → 探索 → 降落的流程。
  5. 需要 Gazebo 和模擬相機時：在筆電跑，或 NX 到貨後拿 AGX 當模擬機（AGX 主機是 Ubuntu 22.04，可以直接裝 PX4 和 Gazebo），NX 跑整套系統加 MAVROS，用網路線連起來。
- [ ] **安全機制**（先在 SITL 裡演練過再上機）：
  1. VIO 發散（odometry 跳動、協方差暴增或停止更新）時自動懸停或降落。
  2. geofence：超出房間範圍就停。
  3. 遙控器隨時能切回手動。
  4. 第一次實飛用繩子拴著，或在網室裡飛。
- [ ] **硬體標定與安裝**：
  1. 相機鎖到機架上之後，用 Kalibr 重新標定相機與 IMU 的外參和時間差（錄一段對著 Aprilgrid 標定板的 bag）。注意：目前 VINS 設定的 `body_T_cam0` 是單位矩陣（假設相機和 IMU 同位置），標定後要換成實際值。
  2. IMU 雜訊參數用靜止錄 1–2 小時的資料做 Allan variance（例如 `allan_variance_ros`）重新估計。
  3. 相機和板子用減震方式安裝（馬達振動會讓 IMU 資料變差），裝好後在機上錄一段資料，確認 VINS 仍然穩定。
- [ ] **機載運算的重量、供電與散熱**：
  1. 秤 Orin NX＋AIR6N0 載板＋擴充板＋SSD＋散熱器的重量，量尺寸，納入機體設計。
  2. 在 NX 上跑完整流程時，從 `tegrastats` 讀功耗，估算電池容量與飛行時間。
  3. 確認電池電壓在載板輸入範圍內（廠商回覆，見步驟 4）。
  4. 確認飛行時（有氣流）和地面測試時溫度都不會過熱降頻。

## 步驟 6｜論文主軸（同時進行）
- [ ] **閱讀順序**：照 [RELATED_PAPERS.md](RELATED_PAPERS.md) 的建議順序讀：Tao → RAVEN → Region-Based → Perception-Aware；Related Work 優先引用 Placed et al.（T-RO 2023）。每讀完一篇，在 RELATED_PAPERS.md 該篇下面寫 3–5 行：做了什麼、和這篇論文的關係、能不能拿來比較。
- [ ] **確認撞題風險**：優先讀那篇 ⚠️ 的《Perception-aware active SLAM for MAVs》（*Aerospace* 2025），它和 RAVEN 的主題很接近。讀完寫下它和你預計的貢獻重疊多少，重疊太多就要調整主軸。
- [ ] **重規劃條件**：論文 VI-B 是「或」，原作者程式與目前手持模式是「且」。
  1. 檢查 frontier 變化比例的算法（`evaPlannedFrontierChanged`／`isFrontierChanged`）：手持時任何一格更新就算整個 frontier 變化，所以「或」時每秒都成立。
  2. 修好算法後改回論文的「或」，確認重規劃頻率合理（不會每秒重算）。
  3. 寫論文時要說明採用哪一種、為什麼。
- [ ] **效用權重**：`* 6` 是 f_sc，現在是參數 `active_closure/ig_weight`。
  1. 對照論文的效用公式。11-17 實測佐證兩個疑點：frontier 效用有除以距離、SLC 效用沒有；SLC 效用隨時間累積的不確定度從約 0 漲到 60（權重 6）。
  2. 選了 SLC 之後會 `i++` 也要確認。
  3. 確認不了就到原作者的 GitHub 開 issue 問。
  4. 確認後再加入 RAVEN 的 λ 參數。
- [ ] **VINS 發散調查**：發散會影響所有實驗。每次發散都記下當時的情況（IR emitter 開或關、是否快速旋轉、場景紋理），結論寫進 `local_migration_status.txt` 或測試報告。
- [ ] **比較基線**：Tao 原版加 FALCON。RAVEN 也跟 FALCON 比較過，所以可以間接和 RAVEN 對照；RAVEN 程式碼釋出後再直接比較。
- [ ] **貢獻定義與實驗設計**：1 到 2 個月內寫下一頁：要解決什麼問題、貢獻是什麼、用哪些實驗證明、和哪些基線比。可以從 RAVEN 的三個想法裡，選一到兩個能在手持階段驗證的作為主軸（特徵點 loop closure 備援、λ 優先順序）。
- [ ] **先寫的章節**：先寫 Related Work 和原方法的摘要章節，這兩章不需要等實驗結果。
