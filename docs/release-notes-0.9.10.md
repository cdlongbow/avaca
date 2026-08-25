# AVACA 0.9.10

## 更新內容

- 新增以具體作品 lineage 與來源 provenance facts 為基礎的作品分類，區分原始作品、合集／拆分／重製等 derived work，未知證據保留待檢視。
- 強化 AvBase 與 JavBus 的作品 metadata、來源證據與跨來源刮削；未能由主要來源判定的作品才升級查詢次要來源，避免不必要的請求。
- 新增精確 deny 規則、provenance verdict、手動規則衝突檢查與可停用的自動 derived-work 過濾，保留明確允許例外。
- 更新 Works／Settings 的抓取政策設定、多語系文字與回歸測試，涵蓋政策持久化、來源升級、合併結果與 UI goldens。

## Release Assets

- `avaca-0.9.10-arm64-v8a.apk`
- `avaca-0.9.10-arm64-v8a.apk.sha256`
- `avaca-0.9.10.zip`
- `avaca-0.9.10.zip.sha256`
