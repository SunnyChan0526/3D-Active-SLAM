# 原論文與目前規劃模式對照（2026-11-11）

來源：~/Downloads/3D_Active_Metric-Semantic_SLAM.pdf，3D Active Metric-Semantic SLAM，DOI 10.1109/LRA.2024.3363542。依本機 PDF 內容核對；本文件不是宣稱已完成論文復現。

## 論文規劃迴路

Fig. 2 與 Sections VI-A–D：frontier → 可見未知區域的資訊增益/觀察點 → COP 全域排序與 travel budget → Algorithm 1 插入主動語意迴環觀察點以降低不確定性 → 局部動態可行軌跡 → 實際執行與感測 → 再規劃。

Section VI-B 明定全域探索路線在任一條件滿足時重規劃：frontier 變化比例達門檻 fr1，或 refined tour 已執行比例超過 fr2；文中實驗為 fr1=15%、fr2=10%。COP 與其餘系統非同步，更新完成前仍執行目前 refined tour。局部軌跡持續重規劃，不等同每隔固定時間重跑一次全域 COP。

Section VI-C–D：SLC 目標來自已到訪的 key pose、語意 landmark 群集與量測範圍；透過虛擬 odometry/loop-closure factors 預估 covariance trace 降低，評估後移除虛擬 factors；預期 SLC 並不是直接把真實定位校正當成已發生。到 SLC 位置後原系統用原地全景旋轉建立量測。

## 目前已確認差異

1. real_robot_planning_sunny.launch 強制 planning_only=true，隔離 UAV tracker/service topics。
2. triggerCallback 只接受 WAIT_TRIGGER；必須收到 waypoints 訊息才首次規劃。
3. planning-only 下 SUCCEED/FAIL 等結果都轉 FINISH，沒有連續執行/重規劃。
4. start_free_mapping.sh 的 p 只是觸發這個單次流程；不是論文式自動探索。
5. EXEC_TRAJ 用已規劃軌跡的時間判斷執行進度，updateStartState 非靜止分支使用預測軌跡狀態。手持相機沒有 controller 時不能把時間流逝當成已按軌跡移動，否則會虛構起點與目標完成。
6. ms_exploration_manager.cpp PLAN_RECV 中「不需全域重規劃」條件為 frontier_changed<0.15 OR remaining_ratio>0.9。相較於論文「任一重規劃條件成立」的敘述，此 no-replan 條件應仔細檢查是否需要 AND；分母 init_tour_len_ 以及 refined/SLC 目標數與實際到達狀態也需一致。
7. evaFrontierChanged 目前遍歷 live frontiers，而規劃前又先 searchFrontiers/removeOutDatedFrontiers；需以計畫快照為基準檢查變化比例，不能直接假定現有比例忠實反映論文 fr1。

## 實作前必要區分

A. 手持 D435i：可以取消人工 p，使用真實 odometry/地圖事件自動啟動與更新規劃；只能在實際到達並滿足觀察條件後記為完成。SLC 全景仍須實際移動相機並成功量測。這是人代替執行器的實機規劃驗證，不是無人機自主執行的完全復現。

B. 具控制器的機器人/模擬：恢復實際 execution feedback、局部重規劃、SLC 全景動作與碰撞處理，才能驗證完整閉迴路。不能只關閉 planning_only 就聲稱恢復完成，須核對控制介面、真實反饋與測試場景。

本次僅讀論文與程式、整理差異；未啟用控制器、未送出規劃或移動命令，尚待確認目前採用 A 或 B，再做相應實作。

## 後續實作

使用者已確認採 A（手持相機、人執行移動）。已新增 AUTO_HANDHELD_EXPLORATION.md 所述模式。上方差異是變更前的稽核快照；新模式修正手動觸發、一次即停、預測執行進度與重規劃條件，並以真實回饋處理 SLC。原單次模式仍保留作對照。
