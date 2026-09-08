# Windows responsiveness acceptance

這份檢查針對原先「切換卡頓」及「正式匯入 library 後卡死」的路徑，要求每次回歸都保留 action-level 證據：

- Server 啟動：先顯示管理殼首幀，再非同步開啟 catalog；不得在 `runApp` 前同步等待 SQLite。

- Scan / Review：畫面可重繪，進度 banner 顯示 resolving、hashing、probing。
- Commit：不得第二次執行 buildPlan；使用已審閱 fingerprint，並顯示 preflight、copying、verifying、indexing。
- Busy：另一個程序持有 lock 超過 10 秒時，UI 收到 `LIBRARY_OPERATION_BUSY`，可回到 Review 或 Retry。
- Stale：source、selection、root 或 revision 變更時，Commit 回傳 `PLAN_STALE`，不執行任何 destructive mutation。
- Cancel / failure：staging tree、journal 與 source preservation 狀態可 recovery；不得留下無法辨識的半成品。
- Server folder import：按鈕只建立 async task，`setState` callback 不回傳 Future；掃描／解析／索引耗時與取消狀態可見，視窗 close 會先取消再等待安全邊界。

本次 source-level 改動已由 `flutter test`、Windows build 與獨立 app build 驗證；真機 action-level Windows/Android UI gate 仍需在可用的測試環境中另行收集，不能以靜態檢查冒充通過。
