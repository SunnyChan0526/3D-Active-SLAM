# 步驟 2：Ground truth 與錄資料流程

> 建立：2026-11-24。對應 [NEXT_STEPS_ROADMAP.md](../docs/NEXT_STEPS_ROADMAP.md) 步驟 2。
> 原則不變：全程 `fsm/planning_only=true`，正式實驗 `ig_weight` 一律用 6。

## 目的

1. **優先**：判斷 SLC（語意迴環）的修正是把位姿拉回正確位置，還是配錯位。11-17 那次（`20261117_174344`）修正了約 0.8 m，小於現在 1 m 的拒絕門檻，所以同樣的修正現在仍會被接受。
2. 四種場景各錄 3 輪以上，建立 baseline：物件多、物件少、繞一圈回到起點、白牆走廊。

## 工具

| 檔案 | 用途 |
| --- | --- |
| `setup/ground_truth/scene_template.yaml` | 每個場景複製一份，填入捲尺量到的檢查點、AprilTag、物體位置 |
| `setup/free_mapping_session.py` | 錄製時輸入 `m <編號>`，在 bag 裡留下 `/gt_marker`（站在檢查點上的時間） |
| `setup/record_isolated_vins_test.sh` | 每輪自動寫 `run_metadata.yaml`；新增 `ACTIVE_SLAM_DISABLE_IR_EMITTER`、`ACTIVE_SLAM_OBJECT_CLASSES`、`ACTIVE_SLAM_RESULTS_DIR` |
| `docker/run.sh` | `ACTIVESLAM_RESULTS_DIR=<外接 SSD 目錄>` 會掛進容器，錄製結果直接寫到 SSD；Jetson 上順便記下電源模式與 L4T 版本 |
| `setup/ground_truth/apriltag_offline.sh` | 錄完後離線重播 infra1，跑 `apriltag_ros`，輸出 `tag_detections.bag` |
| `setup/eval_ground_truth.py` | 比較 SLAM 與 ground truth：檢查點誤差、每次位姿跳動（迴環）是對是錯、對 AprilTag 的連續誤差；輸出 TUM 軌跡給 `evo` |
| `setup/tests/test_eval_ground_truth.py` | 評估程式的單元測試（不需要 ROS） |

## 一、布置 ground truth（每個場景一次）

### 1. 座標
- 世界座標＝啟動時的 SLAM 世界：起點為原點，起始朝向為 +Y，左邊為 −X（和 `ACTIVE_SLAM_ROOM_*` 相同）。
- 地上貼十字膠帶當起點，往前貼一條約 1 m 的膠帶標示朝向。每輪都從同一點、同一朝向、同一高度開始，最好用靠板或腳架固定起始姿態。
- 量起點時的相機離地高度，填進場景檔的 `start_camera_height_m`。

### 2. 地上檢查點
- 從起點沿朝向線（Y）和左右線（X）量，大約每 1 m 貼一個編號點（`A1`、`A2`、`B1`…），把座標填進場景檔的 `markers`。
- 量 X、Y 時要先用直角規或 3-4-5 三角形確認兩條線垂直；誤差控制在 2 cm 內。
- `start` 是起點本身。最後回到起點時再標一次 `start`，就能算出回到起點的位置誤差。如果相機對準朝向膠帶，也能算 yaw 誤差。

### 3. AprilTag
- 印 tag36h11，黑色方塊邊長約 16 cm（`size_m` 填黑色方塊的邊長，不含白邊），平整地貼在牆上。高度大約和相機同高。
- 量 tag 中心的 x、y 和離地高度 z，以及印刷面朝向 `facing_yaw_deg`（例如遠端牆面朝回起點就是 −90）。
- **第一次使用要先檢查座標慣例**：站在某張 tag 正前方的檢查點，標記 `m <編號>`，評估報告最後的「檢查點 vs AprilTag」表格應該只差幾公分。差很多就表示 tag 量錯，或 tag 座標慣例和程式假設的相反（程式假設 apriltag_ros 的 x 向右、y 向上、z 指向相機）。

### 4. 物體位置
- 用捲尺量每個物體中心的位置，填進場景檔的 `objects`。之後拿來算地標誤差與物體間距離誤差（評估程式還沒做這一項，見最後的待辦）。

## 二、每輪錄製

### 磁碟
加錄語意 topic 約 25–45 MB/s，5 分鐘大約 8–13 GB。AGX 的 eMMC 只剩約 13 GB，**一定要錄到外接 SSD**：

```bash
# 主機上（容器還沒啟動時；已啟動要先 docker stop activeslam）
ACTIVESLAM_RESULTS_DIR=/media/<user>/<ssd>/activeslam_runs docker/run.sh
```

容器內的 `ACTIVE_SLAM_RESULTS_DIR` 會自動設好，錄製結果放在 SSD 上的 `vins_full_pipeline_tests/<時間>/`。磁碟檢查（至少 6 GiB）也改成檢查這顆 SSD。

### 指令範例（容器內）

```bash
ACTIVE_SLAM_SCENE=many_objects ACTIVE_SLAM_RUN_NOTE="run 1" \
ACTIVE_SLAM_GT_FILE=setup/ground_truth/room_1118.yaml ACTIVE_SLAM_START_HEIGHT_M=0.40 \
ACTIVE_SLAM_TEST_PIPELINE=full ACTIVE_SLAM_TEST_MODE=free \
ACTIVE_SLAM_RECORD_FULL=true ACTIVE_SLAM_RECORD_SEMANTIC=true \
ACTIVE_SLAM_DISABLE_IR_EMITTER=true ACTIVE_SLAM_OBJECT_CLASSES=1,2,3 \
ACTIVE_SLAM_HANDHELD_AUTO=true ACTIVE_SLAM_HANDHELD_HEIGHT_LIMIT=true \
ACTIVE_SLAM_HANDHELD_Z_MIN=0.3 ACTIVE_SLAM_HANDHELD_Z_MAX=0.5 \
ACTIVE_SLAM_ROOM_FRONT=6.1 ACTIVE_SLAM_ROOM_BACK=2.15 \
ACTIVE_SLAM_ROOM_LEFT=3.26 ACTIVE_SLAM_ROOM_RIGHT=2.86 \
ACTIVE_SLAM_SLC_CLUSTER_MIN_SAMPLES=3 ACTIVE_SLAM_SLC_CLUSTER_DISTANCE=2.0 \
ACTIVE_SLAM_SLC_MAX_KEY_POSE_CLUSTER_DISTANCE=4.0 ACTIVE_SLAM_SLC_IG_WEIGHT=6 \
bash setup/record_isolated_vins_test.sh
```

- 房間範圍要依每個場景重新量；上面是 11-18 那個房間的數字。
- `RECORD_FULL` 只在 `free` 模式有效，而 `free` 模式需要 `full` 流程。沒開 `RECORD_FULL` 時滾動錄製會刪掉開頭，就算不出回到起點的誤差（`run_metadata.yaml` 會出現警告）。
- `ACTIVE_SLAM_DISABLE_IR_EMITTER`：預設 `true`（和以前一樣關閉）。開或關要在第一輪前決定，之後同一組比較都用相同設定。emitter 開著時，投影點也可能干擾 infra 影像上的 tag 偵測。
- `ACTIVE_SLAM_OBJECT_CLASSES`：不設就用設定檔的值（目前 `[1, 2, 3]`）。原作者基線只用椅子 `1`。有開 `RECORD_SEMANTIC` 時，**錄一次就好**，兩種類別設定用同一個 bag 重播比較。

### 錄製中
- 走到檢查點、站定，輸入 `m A3` 再按 Enter；聽到提示音後再保持不動 1 秒。終端會順便印出系統目前估計的位置，可以當場看出偏多少。
- **迴環成功時**（`slc_monitor` 印出 `[Handheld Observed]` 或約束已加入）：原地不動，輸入 `m slc1`（第二次用 `slc2`…），在腳下貼膠帶。錄完再量這點的座標，補進場景檔的 `markers`。
- 結束前回到起點十字、對準朝向膠帶，輸入 `m start`。

### 每輪產生的檔案
`sensors*.bag`、`run_metadata.yaml`（場景、IR emitter、地標類別、ig_weight、git commit 與未提交的修改、電源模式、相關參數）、`free_mapping_session.json`（含每次標記當下的估計位置）、`slc_summary.txt`、`slc_events.log`。

## 三、錄完之後

```bash
# 1. AprilTag 偵測（需要 ros-noetic-apriltag-ros，見下方說明；不要邊錄邊跑）
bash setup/ground_truth/apriltag_offline.sh <run_dir> setup/ground_truth/room_1118.yaml
# 2. 評估（場景檔預設讀 run_metadata.yaml 的 ground_truth_file）
python3 setup/eval_ground_truth.py <run_dir>
# 3. 需要時用 evo 看軌跡
evo_ape tum <run_dir>/gt_eval/tag_ground_truth.tum \
  <run_dir>/gt_eval/factor_graph_atl_quadrotor_high_freq_odom.tum --plot
```

`apriltag_ros` 要在有 ROS Noetic 的環境跑：筆電（原生 Noetic）可以直接 `sudo apt install ros-noetic-apriltag-ros`；板子的主機是 Ubuntu 22.04，沒有 Noetic，要在容器裡安裝（容器以 `--rm` 啟動，重開後要再裝一次）。

評估程式對兩條 odometry（SLOAM `high_freq_odom`，以及只有 VIO 的 `/vins_estimator/odometry`）分別輸出：

- **檢查點**：標記當下前 0.5 秒到後 1 秒的位置中位數，和捲尺量到的位置比較。
- **跳動（迴環修正）**：速度超過 2 m/s 的一段位姿變化就算一次修正（已扣掉同時間的走路位移）。找跳動前後最近的已量檢查點或 AprilTag，算出修正前誤差 e_before 和修正後誤差 e_after：
  - `correct`：e_after < e_before，而且 e_after ≤ 0.3 m
  - `wrong`：e_after > e_before（把位置拉離真實位置，典型的配錯位）
  - `partial`：有變好，但仍差 0.3 m 以上
  - 「方向一致度」是修正向量和實際漂移方向的 cosine，接近 1 表示方向正確。
- **對 AprilTag**：每個 tag 位姿（距離 ≤ 3 m、視角 ≤ 60°）和同一時刻 odometry 的 xy 誤差中位數、P90，以及 yaw 誤差。
- 程式會檢查啟動朝向是否為 +Y（90°），不是的話代表座標慣例不同，結果不能直接用。

## 四、驗證 0.8 m 修正（優先）

### 路線 A：11-17 的 bag（事後粗略判斷）
1. 從 `MYUSB/ActiveSLAM_bags/` 找 `20261117_174344`，複製到 SSD，執行 `python3 setup/eval_ground_truth.py <run_dir>`（不加 `--gt`）。報告會列出每次跳動的時間、大小和方向；確認其中有約 0.8 m 的那一次，同時用 `bag_info` 看 bag 是否還涵蓋起點（當時是滾動錄製）。
2. 如果房間能還原成 11-17 的擺法：量好物體位置，看跳動那一刻 infra 影像拍到哪幾張椅子、距離多遠，反推當時站的位置（±0.2–0.3 m）。這樣足以分辨「拉回正確位置」和「錯一格椅子」，但只能當參考。

### 路線 B：重現（主要做法）
1. 同一個房間，擺法和 11-18 15:07 那輪一樣（兩排打亂、一排原樣），照第一節布好檢查點與 tag。迴環點附近的牆上要有 tag 在視野內。
2. 用上面的指令錄 5–6 分鐘，迴環成功時照「錄製中」標記 `slc1`。
3. 評估報告裡每次跳動都有 `correct` / `wrong` / `partial` 的判斷。至少累積 **3 次成功的迴環**才下結論；被拒絕的次數和原因看 `slc_summary.txt`。
4. 這幾輪同時是 roadmap 步驟 1「收尾驗證」和 `fix/slc-false-match-and-duplicates` 修改的實機驗證。

## 五、四種場景

| 場景（`ACTIVE_SLAM_SCENE`） | 擺法 | 主要指標 | 注意 |
| --- | --- | --- | --- |
| `many_objects` | 10–15 個物體，椅子＋餐桌＋電視混著擺 | SLC 成功率、誤判次數、地標誤差 | 不要擺一排等距、長得一樣的椅子；讓桌子、電視和椅子能同時被看到 |
| `few_objects_3`、`few_objects_0` | 剛好 3 個物體；0–2 個物體 | SLC 會不會觸發；只有 VIO 時的漂移 | 比對少於 3 個物體就直接失敗（`measurement_processing.cpp` 的 `num_objs < 3`），所以 0–2 個那組是之後 RAVEN 特徵點迴環備援的對照組 |
| `loop` | 走一個比小房間大的迴圈，回到起點十字、對準朝向 | 回到起點的位置與 yaw 誤差 | 起點一定要有 tag；回到起點後停 2–3 秒再標 `start` |
| `corridor` | 白牆、少紋理的走廊 | VIO 漂移（每公尺幾公分） | **tag 本身是很強的特徵**，只貼在走廊兩端，中段不要貼 |

每種至少 3 輪，相同場景的每一輪 IR emitter、地標類別、`ig_weight`、起點和房間範圍都要一樣（`run_metadata.yaml` 的 `key_settings` 可以直接比對）。

## 六、待辦（這版工具還沒做）
- 地標位置誤差、物體間距離誤差：需要錄地標 topic，或離線重播 `process_cloud_node` 後再和場景檔的 `objects` 比較。
- `apriltag_ros` 還沒加進 Docker image（`docker/Dockerfile`），目前每次手動安裝。
- `pose covariance trace` 這項指標還沒放進評估報告。
