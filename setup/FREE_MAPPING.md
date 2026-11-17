# 自由建圖（Planning-only）

自動選目標及持續更新路線請使用 `start_auto_handheld_exploration.sh`，詳見 `AUTO_HANDHELD_EXPLORATION.md`。以下為保留的手動單次對照模式。

啟動：`bash ~/Desktop/ActiveSLAM_move2Laptop/setup/start_free_mapping.sh`

相機與作者 RViz 開啟後準備 15 秒。提示固定相機後，5 秒才啟動全新的 VINS、SLOAM、語意辨識、點雲處理、COP 與舊版規劃器。定位就緒後再靜止 10 秒；看到「自由建圖已開始」即可自由慢走。沿用 emitter off、語意辨識單執行緒/nice 10 與既有校正、避障、轉向限制。

沒有固定步行路線、分段距離或步行倒數。不會自動觸發規劃。準備好規劃時，停在遠離障礙物的位置，保持相機高度與朝向，在原終端輸入 `p` 再按 Enter。檢查 5 秒定位與地圖邊界後，最多送出一次舊版 FSM Planning-only 觸發並等待最終結果。定位檢查未通過而未送出時可再次嘗試；觸發已送出後，本輪不再接受重複觸發。此檢查不是碰撞可行性的保證。

輸入 `q` 再按 Enter（或 Ctrl+C）保存、停止本輪節點。請等待程序退出才拔線。RViz 及建圖在規劃結束後仍繼續運行，直到結束本輪。

每輪存於 setup/vins_full_pipeline_tests/時間戳。free_mapping_session.json 保存自由建圖起迄與規劃嘗試。原始感測資料持續分檔錄製，每檔約 1024 MB，保留本輪最近 4 檔；超出時只刪除本輪最舊的分檔，不影響舊測試資料。正常結束後各袋檔有 .info.txt。vins.log 保留規劃與定位診斷。

目前地圖邊界是 X -8～8 m、Y -3～14 m，Z -0.1～2.5 m。依 12×11 m 場地、起點在寬度中央且離端牆約 1 m，以及錄下的前進方向主要為 +Y 設定。若換了初始化朝向或起點，要重新確認世界座標與場地的對應。自由建圖不代表無限地圖；沒有更改座標原點、解析度或避障限制。舊設定備份：setup/mapper_sunny.before_room_bounds_20261109.yaml。

驗證：shell/Python 語法通過；隔離 CLI 測試確認 p/p/q 只送一次觸發並保存結束資料。完整 ROS 實機啟動需在桌面終端執行。
