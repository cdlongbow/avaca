# AVACA 0.9.16

## 更新內容

- 新增可選的 AV-Wiki 作品目錄來源，支援精確搜尋、分頁、作品 metadata、平台番號 identity evidence、連線健康檢查與安全的 transport failure 分類。
- Works 抓取流程改為先合併所有啟用的作品目錄，再依 typed identity 選取 detail；跨來源保留 evidence、去重 canonical work，並維持正確的 source progress。
- 清理 reuse classifier V4 的舊有主動語義：新作品只依具體 provenance evidence 判定，未知狀態保持待檢視，不再以 prefix、managed family、出演者數量或泛用 edition heuristic 作為決策依據。
- 補上 AV-Wiki fixtures、V4 classifier corpus、identity／provenance／catalog union 回歸測試，以及作品來源與設定頁本地化。

## Release Assets

- `avaca-0.9.16-arm64-v8a.apk`
- `avaca-0.9.16-arm64-v8a.apk.sha256`
- `avaca-0.9.16.zip`
- `avaca-0.9.16.zip.sha256`
