# AVACA 0.10.1

## 更新內容

- 將正常收藏庫重新定義為真實存在、可定位、可播放的 Library 媒體；沒有實體媒體的 metadata-only Work / Actress 不會進入正常收藏或直接路由。
- 完成影片資料夾遞迴掃描、實際檔名解析、選取、番號修正、Review，以及多人作品明確選擇主女優的兩階段匯入流程。
- Commit 前加入 plan fingerprint、revision、preflight errors、destination collision、TOCTOU、hash、DB indexing、source cleanup 與 recovery 防護。
- 以 `mediaPortableId + relativePath + LibraryRoot` 建立本地定位契約，Work detail 與現有 Player Core 皆先經過 fail-closed locator。
- 移除正常流程中的手動新增女優入口；performer resolution 由已匯入 Work 建立或關聯 Actress。
- Remote 維持 fail-closed，未以 fake、plaintext 或 accept-all TLS 替代 production-safe provider。

## 驗證狀態

- 最新完整 Flutter suite：373 tests，372 passed；唯一失敗為 Windows DPAPI system code 2，已在 base commit `a1b918a` 隔離重現，確認為環境問題而非本 recovery diff。
- `dart analyze`：`No issues found!`。
- `git diff --check`：passed。
- 真實 Windows / Android action-level Scan → Review → Commit → Collection → Player 證據仍待具備可用 UI/runtime 環境後補齊；本分支不宣稱 `PASS_UI` 或 `SOL_REVIEW_PASS`。
