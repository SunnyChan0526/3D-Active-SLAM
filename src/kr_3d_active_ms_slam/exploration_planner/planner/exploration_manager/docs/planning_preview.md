# D435i 多段路徑預覽（不控制 UAV）

舊的一次規劃模式仍使用 `real_robot_planning_sunny.launch`，啟動方式不變。
新的預覽使用獨立 `/planning_preview_node`，只發布 Marker、地圖快照與狀態。
不發布假 VINS、TF、UAV 軌跡命令，也不進入舊 FSM 的 EXEC_TRAJ。

## 目前系統已在建圖時

每個新終端先執行：

```bash
source /opt/ros/noetic/setup.bash
source /home/sunny/active_ms_slam_ws/devel/setup.bash
```

1. 啟動新預覽節點（可與舊的一次規劃節點並存；發布 topic 隔離）：

   ```bash
   roslaunch exploration_manager real_robot_planning_preview.launch
   ```

2. 另一個終端開啟專用 RViz：

   ```bash
   roslaunch exploration_manager planning_preview_rviz.launch
   ```

3. 緩慢掃描環境，使新節點累積自己的地圖。開始錄影前，固定相機。
   確認 VINS、SLOAM 穩定，且相機位於既有地圖範圍內。

4. 開始預覽（這一步才擷取地圖快照、要求一次 Global COP 並播放）：

   ```bash
   rosrun exploration_manager preview_control.py start
   ```

5. 控制播放：

   ```bash
   rosrun exploration_manager preview_control.py pause
   rosrun exploration_manager preview_control.py resume
   rosrun exploration_manager preview_control.py stop
   rosrun exploration_manager preview_control.py status
   ```

`stop` 保留最後畫面；再次 `start` 從當時真實相機位置擷取新快照並清除上一輪虛擬歷史。
若正在播放，請先 `stop` 再 `start`。
播放速度只改變顯示時間，不改變規劃器的動態限制：

```bash
roslaunch exploration_manager real_robot_planning_preview.launch playback_speed:=0.7
```

預設使用 COP 回傳的全部目標。若只展示前兩個，可於啟動時設定：

```bash
roslaunch exploration_manager real_robot_planning_preview.launch max_goals:=2
```

## 從零啟動上游

若相機、VINS、SLOAM 與 COP 已運行，跳過本節，勿重複啟動。
每條長時間命令使用不同終端。

1. 獨立 ROS master：

   ```bash
   source /opt/ros/noetic/setup.bash
   roscore
   ```

2. D435i：

   ```bash
   source /opt/ros/noetic/setup.bash
   source /home/sunny/realsense_ws/devel/setup.bash
   roslaunch realsense2_camera rs_camera.launch enable_color:=true color_width:=640 color_height:=480 color_fps:=30 enable_depth:=true depth_width:=640 depth_height:=480 depth_fps:=30 enable_infra:=true enable_infra1:=true enable_infra2:=true infra_width:=640 infra_height:=480 infra_fps:=30 enable_gyro:=true enable_accel:=true unite_imu_method:=linear_interpolation align_depth:=true
   ```

3. 固定相機並啟動 VINS，等待初始化。不要在這之後任意重啟 VINS；原點重設會使既有地圖失配。

   ```bash
   source /opt/ros/noetic/setup.bash
   source /home/sunny/vins_ws/devel/setup.bash
   rosrun vins vins_node /home/sunny/vins_ws/src/VINS-Fusion/config/realsense_d435i_sunny/realsense_stereo_imu_config.yaml
   ```

4. 以下各終端先 source active workspace，再各執行一條：

   ```bash
   source /opt/ros/noetic/setup.bash
   source /home/sunny/active_ms_slam_ws/devel/setup.bash
   ```

   ```bash
   roslaunch sloam run_indoor_large_scale_exploration_sunny.launch enable_rviz:=false
   ```

   ```bash
   roslaunch rgb_sem_segmentation rgb_segmentation_real_robot_sunny.launch
   ```

   ```bash
   roslaunch scan2shape_launch real_robot_process_cloud_node.launch odom_topic:=/vins_estimator/odometry
   ```

   ```bash
   roslaunch exploration_manager global_plan_server.launch
   ```

5. 接著依前節啟動 preview、RViz、掃描，再 `start`。

## 圖形與行為

- 綠線／綠點：固定的 Global Tour 與候選 viewpoints。
- 紫色方塊：快照中的 frontiers。
- 紅點：尚未抵達的原始目標，不會因單段規劃成功就移除。
- 橘點：這一段軌跡的實際終點。
- 藍線：這一段局部軌跡（含精確末端）。
- 灰線／藍箭頭：虛擬歷史與虛擬相機，並非真實 VINS 位姿。
- 文字：SIMULATED PREVIEW、狀態與距原始目標距離。

D435i 預覽會先套用既有 SLOAM 的光學座標到機體座標轉換，讓 VIO 深度投影與 SLAM 使用相同姿態定義。此選項只在新 preview Launch 開啟，舊模式預設不變。
地圖快照與顯示位姿使用啟動當下的 SLAM/VIO 剛體變換；播放期間不追隨實體相機。
平移段維持朝向，在觀測點以獨立原地轉向段達成目標 yaw。位置、yaw、碰撞限制未放寬。
只有位置及 yaw 都達標才切換目標。失敗、三段無進展、段數上限或使用者停止都會停止預覽。
未知體素的處理沿用原規劃器，不能把這個虛擬展示當成實體飛行安全認證。
這是在固定地圖上的規劃展示，不會合成新感測資料或真正探索未知空間。

若起點落在膨脹障礙內，會在開始前拒絕；請將相機緩慢抬高並遠離近距離障礙，固定後再執行 `start` 擷取新快照，不要改小膨脹半徑。
若紅點一直未到達，不會假裝成功或跳過。`status` 與 `/rosout` 會記錄停止原因。
不要為了 demo 擅自放寬碰撞、安全距離或動態限制。

## 備份與回復

舊版備份位於專案 `backups/before_planning_preview_20261029_162251/`。
保留原本尚未提交的修改及啟動檔。請先停止使用這些程式的節點，再從專案根目錄恢復：

```bash
tar -xzf backups/before_planning_preview_20261029_162251/original_mode.tar.gz -C .
source /opt/ros/noetic/setup.bash
catkin build exploration_manager --no-status -j2 -p1
```

平常只需關閉 preview 的兩個 Launch，就能繼續使用舊版模式，不必還原程式。

## 驗證

已有 ROS master 時可執行快照隔離測試（不發布感測或控制資料）：

```bash
rosrun exploration_manager preview_snapshot_check
```

預覽啟動後可唯讀檢查 topic 隔離、座標與標記數值：

```bash
rosrun exploration_manager check_preview_contract.py
```
