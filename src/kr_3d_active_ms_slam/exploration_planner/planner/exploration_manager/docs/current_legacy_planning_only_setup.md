# 本機確認版本：舊 FSM 單次 Planning-only

依來源機交接資訊整理於 2026-11-05；來源機更新後原始手冊尚未另外複製到本機。
確認使用 `real_robot_planning_sunny.launch`、`real_robot_rviz.launch`。
多段 `real_robot_planning_preview.launch` 是另一個模式，不是本次指定版本。

## 已完成的本機建置

完整原始碼移植包已還原；ROS Noetic、RealSense、VINS、主工作區和 Python 環境已安裝並在本機建置。
不必重複複製 570 MB 移植包，也不要使用其他機器的 build/devel。

## 啟動

若多段 Preview 仍在運行，先在先前的一鍵啟動終端按 Ctrl+C。
若另開了迴圈閉合服務終端且準備重新初始化整套系統，也停止該終端，避免沿用上一輪原點相關資料。
將相機置於預計掃描的高度，再執行：

```bash
bash ~/Desktop/ActiveSLAM_move2Laptop/setup/start_legacy_planning_only.sh
```

此腳本啟動相機、VINS、SLOAM、語意辨識、點雲處理、COP、迴圈閉合服務、舊 FSM 和作者 RViz。
已有的同名程序會沿用；腳本不發布任何規劃觸發訊息。
檢測到 `/planning_preview_node` 時會停止切換，避免兩個模式同時發布地圖等共用 topic。

每個新終端可使用：

```bash
source ~/Desktop/ActiveSLAM_move2Laptop/setup/source_active_slam.bash
```

## 掃描與檢查

確認相機 IMU、左右 IR 和 `/vins_estimator/odometry` 有資料，VINS 已完成初始化。
保持接近初始化高度慢速掃描，確認 RViz 地圖與軌跡。

```bash
rosparam get /exploration_node/fsm/planning_only
```

必須輸出 `true`。不可為了通過檢查而放寬地圖邊界或修改相機校正。

## 單次規劃觸發

正確 topic：`/sunny_mapping_test/disabled_waypoints`，型別為 `nav_msgs/Path`。
本機原始碼的 triggerCallback 要求非空 poses，且第一個 pose 的 z 不小於 -0.1；FSM 也須位於 WAIT_TRIGGER。
RViz 的 2D Nav Goal 不會觸發此版本；不要使用多段 Preview 的 preview_control.py。
待使用者確認地圖並明確要求單次規劃後，再發布觸發訊息。

## 本機紀錄

啟動紀錄保存在 `~/Desktop/ActiveSLAM_move2Laptop/setup/runs/`。
`real_robot_rviz.launch` 載入作者 `config/real_robot.rviz`；作者原檔保留。
先前另建的 `real_robot_d435i.rviz` 是顯示設定變體，本成功版本不會自動選用它。
