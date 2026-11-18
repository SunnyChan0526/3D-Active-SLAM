# 可用論文整理（Tao → RAVEN 路線）

整理日期：2026-11-17。這份文件整理先前查過、對本專案有用的論文。
本專案的路線：以 Tao 為基線，先用手持（筆電 + D435i）驗證語意 SLAM 和 loop closure，再加入 RAVEN 的想法，最後上 UAV（室內、低空、GNSS 拒止）。
✅ 表示讀過 arXiv 全文或摘要頁，確認過平台和場景。⚠️ 表示只看過搜尋摘要，或網站擋掉自動讀取。
搭配 [SYSTEM_OVERVIEW.md](SYSTEM_OVERVIEW.md)（系統說明）和 [NEXT_STEPS_ROADMAP.md](NEXT_STEPS_ROADMAP.md)（待辦）一起看。

> 2026-11-17 從 Claude web 專案移進 repo。內容未改，只整理成 Markdown 標題與表格，並更新檔名參照與第七節第 3 點。

## 一、主線（一定要讀）

### 1. ✅ 3D Active Metric-Semantic SLAM（Tao 等，RA-L 2024）：基線

作者是賓州大學 GRASP Lab（Vijay Kumar 組）。

- 平台：Falcon 250 四旋翼，機上電腦是 Intel NUC（i7-10710U），感測器是 D435i，用 VOXL 做 VIO。
- 場景：多樓層室內，不用 GPS。
- 方法：
  - 用 YOLOv8 偵測物件，建語意物件地圖。
  - 用 DBSCAN 把物件分群，每群至少 3 個物件，飛回去原地轉一圈拍全景，做語意 loop closure。
  - 用 COP 在預算內規劃探索路線。
  - 資訊增益是「加入虛擬 loop 因子後，協方差 trace 減少多少」。
- 結果：有加 loop closure 時，位置誤差降低超過 90%，偏航誤差約降 75%。
- 弱點，也就是之後的改進點：
  - 沒有物件就做不了 loop closure。
  - 飛行軌跡不考慮定位品質。
  - 探索和定位之間的取捨不能調整。
  - 原地轉圈拍全景很耗時間和電量。

### 2. ✅ RAVEN（HKUST 沈劭劼組，T-RO 2026 已有條件接受）：改進方向

- 平台：自製 1.3 kg 四旋翼，機上電腦是 i7-1260P，感測器是 D435i，用 VINS 做 VIO，所有運算都在機上。
- 場景：室內飛行場、純白牆的走廊、地下停車場，全程不用 GPS。OptiTrack 只用來算誤差。

可以借用的三個想法，以及要改的程式位置：

| RAVEN 的想法 | 對應的 Tao 弱點 | 要改的程式位置 | 手持階段能不能驗證 |
|---|---|---|---|
| 特徵點 loop closure 候選，當語意的備援 | 少物件的環境沒辦法做 loop closure | `loop_closure_submap_node.py`、`generic_sloam/loop_closure/` | ✅ 可以，用 rosbag 重播 |
| λ∈[0,1] 可調優先順序，探索和定位分開評估 | 效用計算單位不一致（frontier ÷ 距離，closure × 6） | `ms_exploration_manager.cpp` 的 `planActiveLoopClosurePath` | 部分可以，要在模擬中比較 |
| 感知導向軌跡（線上 Fisher information field） | 相機對著白牆時 VIO 會漂移 | `plan_manage/`、GCOPTER | ❌ 留到上 UAV 前再做 |

限制：
- 程式碼還沒公開。論文寫「將會釋出」，但 HKUST-Aerial-Robotics 的 GitHub 上還找不到。
- 實驗沒有跟 Tao 比較，而是跟 FALCON、REAL、ExplORB-SLAM 比。
- 寫文獻回顧時要注意：RAVEN 把 Tao 的資訊增益歸類為 T-optimality，但 Tao 原文寫的是協方差 trace 的減少量，比較接近 A-optimality。請以原文為準。

## 二、針對特定問題的參考

| 論文 | 平台 / 場景 | 可以拿來做什麼 |
|---|---|---|
| ✅ Perception-Aware Autonomous Exploration in Feature-Limited Environments（RA-L 2026） | 雙目相機 UAV，用 OpenVINS 做 VIO，Jetson Orin NX；在無紋理的黑牆房間測試 | 處理低紋理環境裡相機朝向的問題。手持時可以改成提示「相機別對著白牆」；上 UAV 時，它也是 Jetson 上跑 VIO 加探索的參考配置 |
| ✅ Region Based SLAM-Aware Exploration（Amazon Lab126，2025） | 家用輪式機器人，雙目相機、IMU、輪速計；在住家和辦公室測試 | 主動 loop closure 的觸發規則寫得很清楚（用 D-optimality），場景又最接近手持。可以參考它來寫手持模式的 loop closure 觸發 |
| ✅ SlideSLAM（T-RO 2025） | UAV 和地面車，GPS 拒止；在室內多樓層、停車場測試 | 同一個團隊，語意 SLAM 的架構和 Tao 相近。可以參考它的物件地圖和多機語意 loop closure |
| ✅ RT-GuIDE（RA-L 2025） | 地面車 Jackal，用 LiDAR 定位 | 想把地圖換成 3D 高斯潑濺時，參考它的資訊增益和視角選擇。它假設定位準確，算力需求也高（RTX 4000），不適合直接上 UAV |
| ✅ SCREP（IROS 2026） | GPS 拒止的室內飛行，只做了硬體在環驗證 | 感知導向的視覺定位：讓相機朝定位可靠的方向看 |
| ✅ Perception-aware Planning for Quadrotor Flight in Unknown and Feature-limited Environments（LA-Planner 的論文） | 四旋翼，低紋理環境 | 感知導向規劃，有開源程式碼（見第六節） |

## 三、背景與相關研究（寫論文時引用）

- ✅ SHIELD（2025）：LiDAR UAV，用 FAST-LIO2 定位，可以飛 0.8 m 寬的窄走廊。屬於 UAV 室內探索，但沒有處理定位不確定性。
- ✅ ResQDrone（ISPRS Archives 2025）：UAV 在室內災區探索，建出幾何、語意、熱影像三層地圖。我只讀了摘要。
- ✅ ActiveGS（RA-L 2025）：用 UAV 做高斯主動重建，但靠 OptiTrack 並假設定位完美。可以拿來當「沒有考慮定位不確定性」的對照例子。
- ✅ Active Semantic Mapping and Pose Graph Spectral Analysis for Robot Exploration（2024）：用位姿圖頻譜分析鼓勵 loop closure，只有模擬。
- ✅ PUL-SLAM（2025）：用深度強化學習做主動 SLAM，獎勵考慮位姿不確定性，是 2D LiDAR 地面機器人。
- ✅ Optimizing Exploration with a New Uncertainty Framework for Active SLAM（RAS 2025）：提出不確定性 frontier，只有模擬。
- ✅ Semantic Exploration and Dense Mapping with Panoramic LiDAR-Camera Fusion（RA-L 2025）：Spot 四足機器人做語意探索，loop closure 不在研究範圍內。
- ⚠️ Review and Frontier Exploration of Active SLAM（Du 等，IEEE 2025）：主動 SLAM 綜述，可以當背景文獻。連結是哈工大的論文頁面。
- 📌 A Survey on Active SLAM: State of the Art and New Frontiers（Placed 等，T-RO 2023）：這次查連結時順便找到的，是更常被引用的主動 SLAM 綜述，寫 related work 時建議優先引用這篇。
- ⚠️ A Survey on the Key Technologies of UAV Motion Planning（Drones 2025）：UAV 運動規劃綜述，涵蓋地圖表示、路徑規劃和軌跡最佳化。

## 四、還沒確認的（⚠️ 有空可以自己打開看）

- Perception-aware active SLAM for MAVs（Aerospace 2025）：用 Fisher 資訊做感知導向的主動 loop closure，主題很接近 RAVEN，值得優先確認。
- FAEM（Drones 2025）：以 FUEL 為基礎改良的 LiDAR UAV 快速探索。
- Mutual information-based hierarchical NBV decision for active semantic visual SLAM under dynamic environments（Scientific Reports 2026）：連結是 PMC 上的免費全文。
- Collaborative Active SLAM … Ground and Aerial Vehicles（M. F. Ahmed，博士論文 2024）：這次沒找到論文本身的連結。同一位作者的相關短文是 Active Collaborative Visual SLAM exploiting ORB Features（2024），講地空協作的主動 SLAM，也會引導機器人回到走過的位置做 loop closure。
- HALO（Tao 等，RA-L 2026）：之前以為 arXiv 上沒有，這次找到了。它是用單目相機的高空 UAV 語意探索，場景是戶外大範圍，跟室內 GNSS 拒止的關係不大。
- 地下、洞穴場景：
  - Prometheus（Oxford 礦坑 UAV）
  - Towards field deployment of MAVs in adaptive exploration of GPS-denied subterranean environments（Patel 等，RAS 2024）
  - Train of Autonomous Aerial Vehicles for Subterranean Exploration with SLAM Capabilities（Blanchard 等，AIAA SciTech 2025）

## 五、查過但不適用（避免重複查）

- Air-ground collaboration for language-specified missions：用 GNSS 定位，全部是戶外實驗。
- Atlas Navigator、Active Perception Game：地面機器人，方法偏語言任務或理論。
- 網路上有一說是 RT-GuIDE 用 Falcon 4 UAV，這個說法是錯的，它的 v1 和 v3 都是地面車 Jackal。

## 六、有開源程式碼、可以拿來當基線或參考實作

| 專案 | 用途 |
|---|---|
| FALCON | 純探索的基線。RAVEN 也跟它比較過，所以你的數據可以間接跟 RAVEN 對照 |
| LA-Planner | 感知導向規劃器，論文是 arXiv 2503.15273，處理低紋理環境。可以在 RAVEN 的 OFIF 釋出前當替代實作 |
| RAVEN | 持續關注 HKUST-Aerial-Robotics 的 GitHub，程式碼釋出後就能直接跟 Tao 比較 |

## 七、建議閱讀順序

1. Tao：已經複現，把弱點列清楚。
2. RAVEN：改進的主線，重點讀 loop closure 候選、λ 和 OFIF 三節。
3. Region Based SLAM-Aware Exploration：手持模式的 SLC 觸發已在 2026-11-17 實作完成（見 SYSTEM_OVERVIEW 第 2.5 節）。可以拿它的觸發規則來檢討目前的做法。
4. Perception-Aware Exploration in Feature-Limited Environments：上 UAV 和 Jetson 前讀。
5. 其他論文在寫 related work 時再查。
