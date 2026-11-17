# 手持相機自動探索規劃

啟動：

```bash
bash ~/Desktop/ActiveSLAM_move2Laptop/setup/start_auto_handheld_exploration.sh
```

舊流程若仍運行，先 Ctrl+C。啟動後先開相機和作者 RViz、準備 15 秒；提示固定後等 5 秒才啟動新的 VINS/建圖，定位就緒後再保持靜止 10 秒。腳本自動呼叫啟用服務，不必按 p，也不依固定路線倒數。輸入 q 再按 Enter 保存並結束。

## 如何走

- 先等終端顯示規劃或掃描提示。沒有探索目標時，可慢慢掃描目前位置周圍，讓相機建立可用地圖。
- RViz `Planning / handheld_local_path` 的青色線是已通過位置/轉向規劃的本段路線；`handheld_next_goal` 的橘色箭頭是目前觀察點及朝向。深綠色原作者 global_tour 是 COP 目標順序連線，不應直接當成穿越障礙物的通路。
- 由人依實際環境移動相機。目標仍是三維座標；只到它的地面投影，不會被算成真正到達。若目標高度無法實際到達，先停下並保留紀錄，不要把定位或高度數值改成假到達。
- 距離目標 0.5 m 內、朝向誤差 0.2 rad 內且持續約 1 秒，才確認普通觀察點已實際到達。
- 若選中語意迴環目標，接近後終端會提示保持位置、緩慢原地轉一圈。程式只請 SLOAM 處理真實語意量測，不會命令相機/飛行器旋轉；只有 action 回報真實成功才計入完成。失敗或 45 秒逾時會跳過且不計完成。

## 與論文對應

沿用原程式 frontier/資訊增益、COP travel budget/排序、語意 key-pose 候選、EvaluateLoopClosure 資訊增益與 SLC 插入，再生成動態可行的局部位置和 yaw 軌跡。

論文 VI-B 的兩個全域重規劃條件採 OR：計畫快照中的 frontier 變化比例達 15%，或已觀察完成的 refined tour 目標比例達 10%，任一成立即更新 COP。完成比例以真實到達的觀察點/SLC 數量衡量，沿用作者程式以目標數近似 tour 進度的作法，分母改為 refined tour（含 SLC）的目標數。frontier 比例以計畫時保存的 frontier 格子群與目前 map 判斷，不使用已刪除舊 frontier 後的空變化比例。

局部路線在真實移動至少約 0.5 m、轉向約 0.35 rad、目前路線出現碰撞，或需要新全域路線/目標時更新；上限節流約每秒一次，等待 COP 時每 0.2 秒檢查。COP 非同步更新時保留當前目標，回覆依 request id 與 tour generation 核對；舊回覆不能覆蓋新請求或完成新目標。

本模式不使用 EXEC_TRAJ 的計畫時間來宣稱人已走到終點，也不以預測軌跡狀態代替真實 odometry。`planning_only=true` 保持；原本發送 tracker/goTo/transition 的 FSM 分支不進入。允許的 active closure action 只處理真實語意量測。手持模式的 SLC 位置保留歷史 key pose 高度，不強制改成 0.9 m。

這是原演算法搭配人代替執行器的自動規劃驗證，不等同原論文無人機自主飛行實驗的完整復現。尚須實機確認自動首輪規劃、真實到達、途中換路及 SLC 量測。

## 保留與暫停

保留既有相機校正、避障距離、動態限制、語意辨識單執行緒/nice 10、IR emitter off。地圖仍為 X [-8,8]、Y [-3,14]、Z [-0.1,2.5] m。定位過舊、非有限數值、速度異常、越界或起點落在膨脹障礙物內會暫停規劃並清除當前可行軌跡顯示；不會因此虛構目標進度。

每輪資料仍在 setup/vins_full_pipeline_tests/時間戳。free_mapping_session.json 標記 automatic_planning=true，保存狀態事件及結束時間；vins.log 記錄 Handheld Plan Result、Handheld Observed/Skipped；原始感測與自動規劃 topic 滾動保留最近約 4 GB。

原手動模式保留：start_free_mapping.sh 仍接受 p，handheld_auto 預設 false。新自動模式忽略 p 和外部手動 waypoint trigger；只需 q 結束。

座標對應：自動模式訂閱真正的 `/factor_graph_atl/quadrotor/sloam_to_vio_odom`，收到新鮮且有效的變換才規劃。COP/語意迴環成本與觀察點進度使用 SLAM 地圖座標；GCOPTER 局部軌跡使用 VIO 與其局部地圖；顯示時將局部軌跡轉回 SLAM 地圖座標。保留的手動模式仍使用原有 `_fake` 佔位設定，不會因新模式更動而自動切換。

檢查項目：自動/手動 launch 參數與 RViz YAML；手持回饋門檻單元測試；真實 manager 的目標完成、過期 generation、SLC 成功回饋與跳過不計完成測試；SLOAM/VIO 座標轉換測試；啟動 CLI 使用 mock ROS 服務測試準備後啟用、忽略 p、q 暫停並保存，並回歸手動單次模式。離線測試不等同相機與現場 SLC 實機驗證。可重跑 `bash setup/tests/run_handheld_regressions.sh`。

### 磁碟空間保護

啟動前至少需有 6 GiB 可用空間，否則不會停止現有節點或建立新一輪紀錄。啟動後每秒檢查一次，低於 2 GiB 時停止本輪錄製與節點；rosbag 另設 2G 最低空間。這是預留空間保護，不能防止其他程序瞬間寫滿磁碟。每輪約 4 GiB 的滾動上限只限制當輪 bag，歷次紀錄仍須自行移存或清理，不會自動刪除。

### 2026-11-12：失敗恢復與搜尋網格

手持模式的 A* 網格改為 0.1 m，對齊目前局部地圖；時間預算保持 0.2 秒。局部規劃連續四次失敗時會略過該目標，並明確提示「不計為完成觀察」，再嘗試後續目標。失敗計數不再沿用到新目標。局部失敗／掃描提示與真正 COP 等待已分離，避免舊版旋轉恢復分支造成反覆假逾時。安全膨脹與動態限制保留；此變更不保證每個探索目標都可達。詳見 `tests/handheld_recovery_change.md`。

### 2026-11-17：接上語意迴環候選、可錄語意重播資料

- `all_legacy_planning_only.launch` 新增 `loop_closure_submap_node.py`（`start_loop_candidates`，預設跟隨 `start_loop`）。之前沒有啟動它，`/factor_graph_atl/loop_closure_submap` 沒有發布者，規劃器的 `loop_closure_ids_` 一直是空的，所以從來不會選中 SLC 目標。
- 候選參數改成 ROS param，預設值與原作者寫死的值相同（大樓多樓層尺度）。手持小場地可用環境變數調整，例如：
  `ACTIVE_SLAM_SLC_CLUSTER_MIN_SAMPLES=3 ACTIVE_SLAM_SLC_CLUSTER_DISTANCE=2.0 ACTIVE_SLAM_SLC_MAX_KEY_POSE_CLUSTER_DISTANCE=4.0`
  （論文寫每群至少 3 個物件，程式原值為 4）。
- 驗證：`rostopic echo -n1 /factor_graph_atl/loop_closure_submap`；vins.log 應出現 `Loop closure submap callback` 與 `[Plan Active Closure] Closure Utility`。
- 錄製選項（預設行為不變）：
  - `ACTIVE_SLAM_RECORD_SEMANTIC=true`：加錄 color、aligned depth 及其 camera_info，可離線重播 YOLO／點雲／SLOAM。約 25–45 MB/s。
  - `ACTIVE_SLAM_RECORD_FULL=true`：不滾動刪除，保留整輪（回起點漂移需要開頭資料）。注意磁碟空間。
- 實驗用範例：
  `ACTIVE_SLAM_RECORD_SEMANTIC=true ACTIVE_SLAM_RECORD_FULL=true bash ~/Desktop/ActiveSLAM_move2Laptop/setup/start_auto_handheld_exploration.sh`
- `planning_only=true`、避障與動態限制都未更動；尚未在實機上驗證。
