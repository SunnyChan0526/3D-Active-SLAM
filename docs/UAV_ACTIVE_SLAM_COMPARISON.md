# 無人機 Active SLAM 論文比較

> 整理日期：2026-11-25
> 範圍：2021–2026 年，無人機平台、嚴格意義的 Active SLAM（規劃時明確權衡探索與定位／SLAM 不確定性）。
> 篩選方式：arXiv 關鍵字搜尋，再以 Semantic Scholar 引用網路（前向＋後向、兩層）補漏，共篩約 300 篇；表中數據取自各論文全文。

## 收錄論文

| 簡稱 | 論文 | 連結 |
|---|---|---|
| REAL | REAL: Rapid Exploration with Active Loop-Closing toward Large-Scale 3D Mapping using UAVs | [arXiv:2108.02590](https://arxiv.org/abs/2108.02590) |
| Zhang22 | Exploration with Global Consistency Using Real-Time Re-integration and Active Loop Closure | [arXiv:2204.02693](https://arxiv.org/abs/2204.02693) |
| AMS-SLAM | 3D Active Metric-Semantic SLAM | [arXiv:2309.06950](https://arxiv.org/abs/2309.06950) |
| RAVEN | RAVEN: A Unified Active SLAM System for Rapid Autonomous Visual Exploration with Aerial Robots under Localization Uncertainty | [arXiv:2610.37111](https://arxiv.org/abs/2610.37111) |
| FU-MPC | FU-MPC: Frontier- and Uncertainty-Aware Model Predictive Control for Efficient and Accurate UAV Exploration with Motorized LiDAR | [arXiv:2605.14920](https://arxiv.org/abs/2605.14920) |

## 表一：基本資料與硬體

| | REAL | Zhang22 | AMS-SLAM | RAVEN | FU-MPC |
|---|---|---|---|---|---|
| 出處 | IROS 2021 | ICRA 2022 | RA-L 2024 | TRO（有條件接受，2026） | 2026 預印本（IEEE/ASME TMech 排版） |
| 團隊 | KAIST（Myung） | HKUST（Shen） | UPenn（Kumar） | HKUST（Shen） | NTU（Lihua Xie） |
| 定位前端 | 模擬：VINS-Stereo；實機：Intel T265（雙目魚眼＋IMU） | VINS-Fusion＋loop closure | ModalAI VOXL VIO＋IMU（UKF 融合） | VINS＋loop closure | 旋轉 LiDAR 的 LIO |
| 建圖感測器 | D435i（RGB-D） | D435i（深度） | D435i（RGB 做實例分割、深度做建圖） | D435i（雙目＋深度） | 主動旋轉 LiDAR |
| 只靠雙目＋IMU 定位 | ✅ | ✅ | ❌ | ✅ | ❌ |
| 機載電腦 | 機載（型號未寫） | DJI Manifold 2-C（i7-8550U） | Intel NUC（i7-10710U） | Mini PC（i7-1260P），起飛重 1.3 kg | Intel N305 |

## 表二：Active SLAM 方法

| | REAL | Zhang22 | AMS-SLAM | RAVEN | FU-MPC |
|---|---|---|---|---|---|
| 主動定位手段 | 主動 loop closure | 主動 loop closure | 主動語意 loop closure | 主動 loop closure＋perception-aware 軌跡 | 主動控制 LiDAR 旋轉方向與轉速（沒有 loop closure） |
| loop closure 候選 | 歐氏距離近、但沿軌跡的測地距離遠的節點，選似然最大者 | 把歷史視角分群，作為候選 | 從既有的 key pose 和語意子地圖配對取樣 | frontier 與主動 loop closure 候選一起生成全域路線，並預估每個 loop closure 的成功機率 | — |
| 不確定性度量 | 啟發式似然（無顯式 covariance） | 無，以繞路成本門檻決定 | 共變異矩陣的 trace 下降量（A-optimality）；在因子圖中加入虛擬因子來預測 | 圖的 D-optimality（Fisher 資訊）；另用線上 Fisher information field 評估視覺可定位性 | 以 Fisher 資訊為基礎的方向性定位不確定性代理模型（A-optimality） |
| 探索與定位怎麼取捨 | 啟發式切換 | 繞路成本不超過原路線的 (1+ε) 倍才去 loop closure（ε=0.2） | COP（有預算的定向問題）規劃探索路徑，再沿路插入 loop closure 點，使總資訊增益最大 | 效用向量分開評分，用參數 λ∈[0,1] 明確調整偏好 | 局部 MPC 同時優化 frontier 增益與定位不確定性 |
| 全域規劃 | 圖搜尋＋Peacock 軌跡 | ATSP 全域路線（基於 FUEL） | COP | 全域路線候選集 | 拓撲感知的 viewpoint 排序 |
| 地圖修正 | — | TSDF 即時重新整合，用 set cover 篩除冗餘影格 | 語意因子圖（GTSAM） | 依 loop closure 結果修正 | — |

## 表三：實驗與結果

| | REAL | Zhang22 | AMS-SLAM | RAVEN | FU-MPC |
|---|---|---|---|---|---|
| 實機場景 | 地下空間 38×19×3 m | 教室 20×14×3 m | 多樓層室內 | 飛行場 8.5×9×2 m、走廊 17×10×2 m、停車場 28.5×16×2 m | 戶外：停車場通道、類工業建築 |
| 室外／室內 | 地下室內 | 室內 | 室內 | 室內加半戶外 | 戶外 |
| 飛行速度 | 0.5 m/s | 實機未寫（模擬 2.0 m/s） | — | — | 0.5 m/s |
| 比較對象 | NBVP、GBP、MBP、AEP | Voxblox、C-blox、FUEL | 消融實驗（有無 SLC） | SRE、REAL、ExplORB、FALCON | EPIC、FUEL、ERRT，以及固定轉速掃描 |
| 主要結果 | 探索速度與定位精度皆優於比較方法 | 嚴重漂移時地圖 RMSE 0.087 m（Voxblox 0.266 m）；主動 loop closure 只多花 8% 時間 | 位置誤差降低超過 90%、yaw 誤差降低約 75%、不確定性降低超過 70% | 停車場 ATE/NND：λ=0 時 0.48 m，λ=1 時 0.18 m；代價是時間從 175 s 增加到 242 s | 探索時間減少 37–62%；Sinkhole 場景 RMSE 1.03 m，EPIC 發散到 59 m |
| 開源 | 只有影片和模擬地圖 | 宣稱會開源 | 專案頁有程式碼 | 宣稱會釋出 | 有專案頁 |

## 重點觀察

1. **只有 RAVEN 能明確調整探索與定位的偏好**（λ 參數），且用 Fisher 資訊同時處理 loop closure 選擇與軌跡優化，是目前最完整的框架。
2. **不確定性的量化方式從啟發式走向資訊理論**：REAL、Zhang22 靠啟發式 → AMS-SLAM 用共變異 trace → RAVEN 用 D-optimality。
3. **實驗場景都很小**：最大為 REAL 的 38×19 m，飛行高度都在 3 m 以下。只有 FU-MPC 在戶外飛，但它用 LiDAR，且沒有 loop closure。
4. **研究缺口：雙目＋IMU 的低空戶外 Active SLAM 尚無人做。** 若以 RAVEN 為起點，主要挑戰在：
   - loop closure 成功率模型：戶外視角與光照變化大；
   - Fisher information field 在遠距、特徵稀疏的戶外是否仍適用；
   - 雙目深度範圍：D435i 有效深度約 10 m 以內，不足以支援較高的飛行高度。

## 相關但未列入比較

- **AEOS**（[arXiv:2509.09141](https://arxiv.org/abs/2509.09141)）：FU-MPC 同團隊前作，主動控制旋轉 LiDAR 以改善 LIO，屬主動定位、不含探索決策。
- **地面機器人的 Active SLAM（方法可參考）**：Graph-Based SLAM-Aware Exploration（[2308.16522](https://arxiv.org/abs/2308.16522)）、Lighthouses（[2306.10463](https://arxiv.org/abs/2306.10463)）、Active Semantic Mapping and Pose Graph Spectral Analysis（[2408.14726](https://arxiv.org/abs/2408.14726)）、Active Loop Closure for OSM-guided Mapping（[2407.17078](https://arxiv.org/abs/2407.17078)）、ExplORB-SLAM（[2209.03693](https://arxiv.org/abs/2209.03693)）。
- **無人機上被動處理漂移、有戶外實飛**：Scalable Outdoors Autonomous Drone Flight with VI-SLAM（[2403.09596](https://arxiv.org/abs/2403.09596)）。
- **綜述**：A Survey on Active SLAM: State of the Art and New Frontiers（[2207.00254](https://arxiv.org/abs/2207.00254)）。
