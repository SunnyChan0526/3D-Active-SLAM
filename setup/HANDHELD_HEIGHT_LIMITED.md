# Handheld Testing Mode — 方案 A：限制觀察點高度

啟動（先實測相機高度再填）：

```bash
ACTIVE_SLAM_HANDHELD_Z_MIN=0.1 ACTIVE_SLAM_HANDHELD_Z_MAX=0.4 \
  bash ~/Desktop/ActiveSLAM_move2Laptop/setup/start_handheld_height_limited.sh
```

- Z 為 SLAM 地圖座標，原點是啟動時的相機位置；0.1/0.4 只是示範預設值。
- `ACTIVE_SLAM_HANDHELD_Z_SAMPLES`（預設 3）：在範圍內均勻取幾層高度。
- 其餘流程與 `start_auto_handheld_exploration.sh` 完全相同（到達判定 0.5 m / 0.2 rad、SLC 只計真實成功）。

## 改了什麼（全部預設關閉）

| 位置 | UAV / 原手持模式 | 高度限制模式 |
|---|---|---|
| `frontier_finder.cpp` `sampleViewpointsIGNoPred` | 取 frontier 平均高度，低於 0.9 m 拉到 0.9 m | 只在 [z_min, z_max] 取樣；取不到有效視角的 frontier 進 dormant |
| `ms_exploration_manager.cpp` `planActiveLoopClosurePath` | 所有 key pose 都可當 SLC 目標 | key pose 高度超出範圍者略過，不提供也不算完成 |

參數：`/exploration_node/handheld_height/{enable,z_min,z_max,z_samples}`。

## 要觀察的

`vins.log` 中 `[Handheld Height] new frontiers with reachable viewpoints: a/b, no viewpoint in z range (dormant): c`。
若 c 長期接近 b，代表高度範圍太窄或 frontier 多在高處（天花板、櫃頂），因相機只有 yaw、垂直 FOV 約 58°，低處看不到。可放寬範圍或增加取樣層數。

## 還原

修改前的原始檔備份於 `~/active_ms_slam_ws/src/kr_3d_active_ms_slam/backups/before_handheld_height_limit_20261112/`。
