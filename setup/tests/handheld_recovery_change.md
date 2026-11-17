# 手持模式 A* 逾時與失敗恢復修正（2026-11-12）

## 觸發與證據

影片對應 20261112_143226。14:35:25.195526：局部 A* 超過 0.2 秒，34260節點；14:35:26.201466：0.2秒、35621節點。局部搜尋解析度0.02m，storage地圖解析度0.1m；起點raw/inflated均FREE，目標raw/inflated均UNKNOWN，兩者都在box內。第一輪局部起點約(2.156,-1.201,0.276)m，目標(-1.424,2.379,1.096)m，距離約5.13m；第二輪局部目標約(-2.050,3.467,1.101)m，距離約6.05m。

局部未知目標與沿途障礙意味著需要搜索繞行；網格細分增加分支／節點負擔，0.2秒是計算截止而非「已證明無路」。無當時完整occupancy快照，不能證明僅加時間就必然找到路，也不能宣稱所有失敗都只由解析度造成。

真正造成持續卡住的是plan_fail_cnt>=2後返回RANDOM_ROTATE，手持FSM將其視為COP等待；只在FAIL且計數>3時跳過目標，因此永遠無法從該條件恢復。日誌370次RANDOM_ROTATE均有對應的舊版失敗旋轉guard訊息。

## 最終變更

- algorithm.xml僅在handheld_auto=true時使用0.1m A*網格，與目前局部occupancy解析度一致；false仍0.02m。搜尋預算保持0.2秒；未放寬地圖碰撞膨脹、速度／加速度或yaw限制。Kino、GCOPTER與後續可行性檢查保留。
- 手持模式不進入舊版「失敗兩次就先旋轉」快速返回；可繼續真正執行局部規劃，連續四次失敗則略過本tour中的該目標。
- 每次局部規劃以目標token（tour世代+目標ID）識別計數；新目標／新tour清除前目標失敗計數，同目標正常保留重試計數。
- skipHandheldGoal只接受手持模式、當前世代與當前目標；成功略過後重設計數，未增加已觀察／完成數。舊token不能修改目前目標計數。
- 真正空tour、已有COP請求待結果的兩個分支，在手持模式回傳WAIT_PLAN；FSM只對WAIT_PLAN顯示COP等待。意外RANDOM_ROTATE改提示重新觀察，保持1Hz重試，不假稱等待COP、不發出UAV控制指令。

## 驗證

- 建置：handheld_recovery_build.log、handheld_recovery_final_build.log。
- 啟動參數：handheld_recovery_auto_params.yaml與handheld_recovery_manual_params.yaml，已檢查解析度與保留安全參數。
- 實際A*離線測試：handheld_astar_regression.cpp。相同10cm occupancy上測2cm/10cm自由路徑、10cm牆面通道繞行、沿輸出每段以5mm間距獨立檢查碰撞、封閉通道後拒絕通路。此人工地圖非原始房間occupancy重播。
- 真實manager bookkeeping測試新增同目標4次失敗計數保留、略過不計完成、下一目標歸零、過期token不改計數、新世代歸零及手動模式拒絕skip。
- 原有到達／SLC真實回饋、COP結果驗證、座標轉換、CLI等回歸一起跑，結果見各regression.log。

尚未重新完成實機手持長時間測試。新程式需停止原流程再啟動，現有執行中的節點不會因重新編譯自動更新。建議短程驗證路線成功更新以及失敗後可恢復，再做長距離。即使修正後仍可能逾時或遇到真正無法通行的目標，不會強行輸出軌跡。
