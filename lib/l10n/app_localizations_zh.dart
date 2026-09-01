// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get addTitle => '新增收藏';

  @override
  String get noPhoto => '尚無照片';

  @override
  String get selectPhoto => '選擇照片';

  @override
  String get removePhoto => '移除照片';

  @override
  String get actressNameRequired => '女優姓名 (必填)';

  @override
  String get saveCard => '儲存卡片';

  @override
  String get changePhoto => '更換照片';

  @override
  String get deletePhoto => '刪除照片';

  @override
  String get noAttributesSet => '尚未設定屬性';

  @override
  String get bodyInfo => '詳細資料';

  @override
  String get heightCm => '身高 (cm)';

  @override
  String get weightKg => '體重 (kg)';

  @override
  String get cup => '罩杯';

  @override
  String get measurements => '三圍';

  @override
  String get privateNotes => '私人筆記';

  @override
  String get noNotes => '尚無筆記';

  @override
  String get confirmDeleteTitle => '確認刪除？';

  @override
  String get deleteWarningWithPhoto => '刪除後將無法復原，連同照片檔案也會被清除。';

  @override
  String get cancel => '取消';

  @override
  String get reload => '重新載入';

  @override
  String get confirmDelete => '確定刪除';

  @override
  String get edit => '編輯';

  @override
  String get delete => '刪除';

  @override
  String get appTitle => 'AVACA 收藏庫';

  @override
  String get search => '搜尋';

  @override
  String get filterAndSort => '篩選與排序';

  @override
  String get filterSection => '篩選';

  @override
  String get sortSection => '排序';

  @override
  String get sortCreatedDesc => '新增時間（新到舊）';

  @override
  String get sortCreatedAsc => '新增時間（舊到新）';

  @override
  String get sortModifiedDesc => '修改時間（新到舊）';

  @override
  String get sortModifiedAsc => '修改時間（舊到新）';

  @override
  String get sortAgeAsc => '年齡（低到高）';

  @override
  String get sortAgeDesc => '年齡（高到低）';

  @override
  String get birthDate => '生日';

  @override
  String get setBirthDate => '設定生日';

  @override
  String get clear => '清除';

  @override
  String get done => '完成';

  @override
  String ageWithBirthDate(int age, String date) {
    return '$age歲  $date';
  }

  @override
  String get add => '新增';

  @override
  String get settings => '設定';

  @override
  String get themeAndColors => '主題與色彩';

  @override
  String get interfaceSettings => '介面';

  @override
  String loadFailed(String error) {
    return '載入失敗：$error';
  }

  @override
  String get noData => '尚無資料';

  @override
  String get searchNameHint => '輸入名稱快速搜尋...';

  @override
  String get applySettings => '套用設定';

  @override
  String get themeMode => '主題模式';

  @override
  String get followSystem => '跟隨系統';

  @override
  String get lightTheme => '淺色';

  @override
  String get darkTheme => '深色';

  @override
  String get customTheme => '自訂主題';

  @override
  String get pureBlackAmoled => '純黑 AMOLED';

  @override
  String get pureBlackOnlyDark => '僅深色主題有效';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => '卡片背景';

  @override
  String get colorOnSurface => '主要文字';

  @override
  String get colorOnSurfaceVariant => '次要文字';

  @override
  String get colorPrimary => '互動主色';

  @override
  String get colorOnPrimary => '主色文字';

  @override
  String get colorOutline => '邊框 / 分隔線';

  @override
  String get colorSnackbarBackground => '提示訊息背景';

  @override
  String adjustColorTitle(String colorLabel) {
    return '調整 $colorLabel';
  }

  @override
  String get apply => '套用';

  @override
  String get imageReadFailedUnsupportedFormat => '圖片讀取失敗，可能格式不支援';

  @override
  String get enterName => '請輸入姓名';

  @override
  String get collectionAdded => '收藏成功';

  @override
  String get alreadyInCollection => '已經在收藏庫中';

  @override
  String get dataDeleted => '資料已徹底刪除';

  @override
  String get deleteFailed => '刪除失敗';

  @override
  String get photoCroppedRememberSave => '照片裁切完成，請記得按下儲存！';

  @override
  String get detailSaved => '詳細資料已儲存！';

  @override
  String get saveFailedDuplicateName => '儲存失敗，可能是姓名與他人重複';

  @override
  String get dataNotFound => '找不到資料';

  @override
  String get attrCensored => '有碼';

  @override
  String get attrUncensored => '無碼';

  @override
  String get attrWestern => '歐美';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '國產';

  @override
  String get filterAll => '全部';

  @override
  String get imageCropLoadErrorTitle => '圖片讀取錯誤';

  @override
  String get close => '關閉';

  @override
  String get imageDecodeFailed => '圖片解碼失敗';

  @override
  String get cropZoom => '放大縮小';

  @override
  String get cropPanX => '左右平移';

  @override
  String get cropPanY => '上下平移';

  @override
  String get confirmCrop => '確定裁切';

  @override
  String get language => '語言';

  @override
  String get worksPageSize => '作品頁大小';

  @override
  String get worksPageSizeSmall => '小';

  @override
  String get worksPageSizeLarge => '大';

  @override
  String get traditionalChineseTaiwan => '繁體中文（台灣）';

  @override
  String get english => '英文';

  @override
  String get simplifiedChinese => '簡體中文';

  @override
  String get japanese => '日文';

  @override
  String get works => '作品';

  @override
  String get relatedActresses => '關聯演員';

  @override
  String get workStorageTitle => '作品儲存記錄';

  @override
  String get workStorageSaved => '已儲存';

  @override
  String get workStorageNotSaved => '未儲存';

  @override
  String get workStorageQuality => '畫質';

  @override
  String get workStorageFrameRate => '幀率';

  @override
  String get workStorageSave => '儲存';

  @override
  String get workStorageUpdated => '作品儲存記錄已更新';

  @override
  String get workStorageUpdateFailed => '作品儲存記錄更新失敗';

  @override
  String get workStorageFilterStored => '已儲存';

  @override
  String get workStorageFilterNotStored => '未儲存';

  @override
  String get workStorageFilterAll => '全部';

  @override
  String get aliases => '別名';

  @override
  String get manageAliases => '管理別名';

  @override
  String get aliasInputHint => '輸入其他名稱';

  @override
  String get addAlias => '新增別名';

  @override
  String get saveAliases => '儲存別名';

  @override
  String get noAliases => '尚無別名';

  @override
  String get deleteWorks => '刪除作品';

  @override
  String get deleteWorksTitle => '刪除選取的作品？';

  @override
  String get deleteWorksWarning => '選取的作品會從資料庫中全域移除，也會移除其他女優的作品連結。';

  @override
  String get libraryCollectionDeleteUnavailable => 'Library 收藏項目不提供刪除功能。';

  @override
  String worksDeleted(int count) {
    return '已刪除 $count 部作品';
  }

  @override
  String get loadFailedGeneric => '載入失敗';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressName演出的作品';
  }

  @override
  String get searchWorks => '搜尋作品';

  @override
  String get workCodeSearchHint => '輸入番號搜尋...';

  @override
  String get noMatchingWorks => '找不到符合的作品';

  @override
  String get noWorks => '尚無作品';

  @override
  String durationMinutes(int minutes) {
    return '$minutes 分鐘';
  }

  @override
  String get studio => '製作商';

  @override
  String get publisher => '發行商';

  @override
  String get series => '系列';

  @override
  String get javBusVerificationTitle => 'JavBus 驗證';

  @override
  String get javBusVerificationInstructions =>
      'JavBus 要求手動完成地區成年驗證。請回答所有題目，App 會在同一安全工作階段繼續刮削。';

  @override
  String get javBusVerificationSubmit => '送出驗證';

  @override
  String get settingsDataTransferTitle => '資料匯入與匯出';

  @override
  String get settingsDataTransferSubtitle => '以 ZIP 備份或還原演員、作品、詳細資料與圖片。';

  @override
  String get dataTransferExportTitle => '匯出資料';

  @override
  String get dataTransferExportSubtitle => '選擇位置儲存完整 ZIP 備份。';

  @override
  String get dataTransferImportTitle => '匯入資料';

  @override
  String get dataTransferImportSubtitle => '選擇 ZIP 備份並直接還原到目前資料庫。';

  @override
  String get dataTransferPreparing => '準備資料中…';

  @override
  String get dataTransferDuplicateProgress => '等待重複演員選擇…';

  @override
  String get dataTransferWriting => '寫入資料與圖片中…';

  @override
  String get dataTransferExportSuccess => '匯出完成。';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return '匯出完成，略過 $count 張無法使用的圖片。';
  }

  @override
  String get dataTransferImportSuccess => '匯入完成，資料已可直接使用。';

  @override
  String get dataTransferDuplicateTitle => '發現重複演員';

  @override
  String get dataTransferDuplicateExplanation =>
      '請比較頭像與作品數，選擇要採用哪一份演員詳細資料。既有作品與關聯會保留。';

  @override
  String get dataTransferKeepExisting => '保留目前資料';

  @override
  String get dataTransferUseImported => '使用匯入資料';

  @override
  String get dataTransferContinue => '繼續';

  @override
  String dataTransferWorkCount(int count) {
    return '作品數：$count';
  }

  @override
  String get dataTransferArchiveTooLarge => 'ZIP 檔案超過可支援的大小。';

  @override
  String get dataTransferUnsafeArchive => 'ZIP 含有不安全的檔案路徑。';

  @override
  String get dataTransferCorruptArchive => 'ZIP 檔案損毀或圖片校驗失敗。';

  @override
  String get dataTransferFileUnreadable => '無法讀取所選檔案。';

  @override
  String get dataTransferActorNameConflict => '匯入演員名稱與其他資料衝突。';

  @override
  String get dataTransferBusy => '已有另一個資料傳輸作業正在進行。';

  @override
  String get dataTransferFailed => '資料傳輸失敗，未變更既有資料。';

  @override
  String get otherSettings => '其他';

  @override
  String get about => '關於';

  @override
  String get github => 'github';

  @override
  String get feedbackSuggestions => '回饋建議';

  @override
  String get softwareUpdate => '軟體更新';

  @override
  String get softwareUpdateDescription => '檢查並安裝 AVACA 的最新版本。';

  @override
  String get currentVersion => '目前版本';

  @override
  String get latestVersion => '最新版本';

  @override
  String get autoCheckUpdates => '自動檢查更新';

  @override
  String get checkForUpdates => '檢查更新';

  @override
  String get checkingForUpdates => '正在檢查更新…';

  @override
  String get downloadingUpdate => '正在下載更新…';

  @override
  String get verifyingUpdate => '正在驗證更新…';

  @override
  String get installingUpdate => '正在啟動安裝…';

  @override
  String get updateAvailable => '有新版本可用';

  @override
  String get upToDate => '目前已是最新版本。';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateLater => '稍後';

  @override
  String get updateUnavailable => '此版本沒有此裝置的更新檔。';

  @override
  String get updateCheckFailed => '檢查更新失敗，請稍後再試。';

  @override
  String get updateDownloadFailed => '更新下載失敗，原有資料未變更。';

  @override
  String get updateIntegrityFailed => '更新檔驗證失敗，已停止更新。';

  @override
  String get updateNotSupported => '此裝置不支援自動更新。';

  @override
  String get updateInstallPermissionRequired => '請先允許 AVACA 安裝未知來源的應用程式。';

  @override
  String get updatePortableFolderNotWritable => 'portable 程式資料夾無法寫入，已停止更新。';

  @override
  String get updateInstallerFailed => '更新程式無法啟動，原有版本仍保留。';

  @override
  String get updateDataPreserved => '使用者資料與設定會保留。';

  @override
  String get prefixRouteRulesTitle => '作品圖片 Prefix 路由規則';

  @override
  String get prefixRouteRulesSubtitle => '查看並管理由實際驗證下載結果學習的圖片 family。';

  @override
  String prefixRouteRuleCount(int count) {
    return '已學習 $count 條 Prefix 規則';
  }

  @override
  String get prefixRouteSearchHint => '搜尋 Prefix';

  @override
  String get prefixRouteNoRules => '尚未學習任何 Prefix 路由規則。';

  @override
  String get prefixRouteNoSearchResults => '沒有符合搜尋條件的 Prefix 規則。';

  @override
  String get prefixRouteBestFamily => '目前優先 family';

  @override
  String get prefixRouteNotAvailable => '無';

  @override
  String get prefixRouteCandidates => '已知候選路由';

  @override
  String prefixRouteSuccessCount(int count) {
    return '成功：$count 次';
  }

  @override
  String prefixRouteFailureCount(int count) {
    return '失敗：$count 次';
  }

  @override
  String prefixRouteLastSuccess(String time) {
    return '最後成功：$time';
  }

  @override
  String prefixRouteLastFailure(String time) {
    return '最後失敗：$time';
  }

  @override
  String get prefixRouteStatusVerified => '已驗證';

  @override
  String get prefixRouteStatusExceptions => '有例外';

  @override
  String get prefixRouteStatusPending => '待重新驗證';

  @override
  String get prefixRouteStatusProbeFailed => '探測失敗';

  @override
  String get prefixRouteManualOverride => '手動指定 route';

  @override
  String get prefixRouteAutomatic => '自動';

  @override
  String get prefixRouteAutomaticDescription => '優先使用已學習候選，必要時再探測目前支援的 family。';

  @override
  String get prefixRouteManualDescription => '會優先嘗試此 family；原有學習統計仍會保留。';

  @override
  String get prefixRouteFamilyDmmStandard => 'DMM Standard';

  @override
  String get prefixRouteFamilyDmmLeadingOne => 'DMM Leading One';

  @override
  String get prefixRouteFamilyDmmH1711 => 'DMM H1711';

  @override
  String get prefixRouteFamilyDmmRebeccaH346 => 'DMM Rebecca H346';

  @override
  String get prefixRouteFamilyMgstagePrestige => 'MGStage Prestige';

  @override
  String get prefixRouteFamilyMgstageSeikyouiku => 'MGStage Seikyouiku';

  @override
  String get prefixRouteExport => '匯出規則';

  @override
  String get prefixRouteImport => '匯入規則';

  @override
  String get prefixRouteExportDialogTitle => '匯出 Prefix 規則';

  @override
  String get prefixRouteExportRulesOnly => '僅規則';

  @override
  String get prefixRouteExportRulesOnlyDescription => '匯出 family，不包含驗證統計。';

  @override
  String get prefixRouteExportWithStatistics => '規則與統計';

  @override
  String get prefixRouteExportWithStatisticsDescription => '包含成功、失敗與時間資料。';

  @override
  String get prefixRouteExportSuccess => 'Prefix 規則已匯出。';

  @override
  String get prefixRouteImportDialogTitle => '匯入 Prefix 規則';

  @override
  String prefixRouteImportPreview(int rules, int conflicts) {
    return '找到 $rules 條規則。手動指定衝突：$conflicts。';
  }

  @override
  String get prefixRouteImportMerge => '合併';

  @override
  String get prefixRouteImportReplace => '取代';

  @override
  String prefixRouteImportSuccess(int count) {
    return '已匯入 $count 條 Prefix 規則。';
  }

  @override
  String get prefixRouteOperationFailed => 'Prefix 路由操作失敗，既有規則未變更。';

  @override
  String get prefixRouteLoadFailed => '無法載入 Prefix 路由規則。';

  @override
  String get prefixRouteClearAutomatic => '清除自動學習';

  @override
  String get prefixRouteClearAutomaticTitle => '清除自動學習？';

  @override
  String get prefixRouteClearAutomaticMessage => '將清除已學習候選與統計；手動指定與已下載圖片會保留。';

  @override
  String get prefixRouteClearAutomaticSuccess => '已清除 Prefix 自動學習資料。';

  @override
  String get prefixRouteReset => '重設此 Prefix 學習';

  @override
  String get prefixRouteResetTitle => '重設此 Prefix 的學習資料？';

  @override
  String get prefixRouteResetMessage => '將清除候選與統計；如果有手動指定 route，會保留。';

  @override
  String get prefixRouteForget => '移除此 Prefix 規則';

  @override
  String get prefixRouteForgetTitle => '移除此 Prefix 規則？';

  @override
  String get prefixRouteForgetMessage =>
      '將移除此 Prefix 的學習資料與手動指定；不會變更已下載圖片或作品資料。';

  @override
  String get workFieldProvenanceTitle => '欄位來源';

  @override
  String get workFieldProvenanceSource => '來源';

  @override
  String get workFieldProvenanceObservedAt => '觀測時間';

  @override
  String get workFieldProvenanceUnknown => '未知來源';

  @override
  String get dataHealthTitle => '資料健康度';

  @override
  String get dataHealthSubtitle => '检查数量、作品字段与图片缺漏、字段来源及待清理文件。';

  @override
  String dataHealthSectionUnavailable(String section) {
    return '此区段无法加载：$section';
  }

  @override
  String get dataHealthRefresh => '重新整理';

  @override
  String get dataHealthActresses => '女優';

  @override
  String get dataHealthWorks => '作品';

  @override
  String get dataHealthStored => '已收藏影片';

  @override
  String get dataHealthNotStored => '未收藏影片';

  @override
  String get dataHealthMetadataIssues => '缺少作品欄位';

  @override
  String get dataHealthMissingImages => '缺少圖片引用';

  @override
  String get dataHealthMissingProvenance => '缺少欄位來源';

  @override
  String get dataHealthPendingDeletions => '待清理檔案';

  @override
  String get settingsDataHealthTitle => '資料健康度';

  @override
  String get settingsDataHealthSubtitle => '查看資料完整性與欄位來源。';

  @override
  String get libraryImportTitle => '資料夾刮削與媒體入庫';

  @override
  String get libraryImportOpen => '匯入影片';

  @override
  String get libraryImportSelectFolder => '選擇刮削資料夾';

  @override
  String get libraryImportSelectRoot => '選擇收藏資料夾';

  @override
  String get libraryImportScan => '掃描資料夾';

  @override
  String get libraryImportConfirm => '確認並開始刮削';

  @override
  String get libraryImportPhase1ReadOnly => '目前階段只讀取檔名與檔案資訊，不會修改來源影片。';

  @override
  String get libraryImportNoFolder => '請先選擇刮削資料夾。';

  @override
  String get libraryImportNoRoot => '請先選擇收藏資料夾。';

  @override
  String get libraryImportMediaAccessRequired => '請允許 AVACA 讀取所選資料夾中的影片，再重新掃描。';

  @override
  String get libraryImportManualCode => '手動修正番號';

  @override
  String get libraryImportStatusReady => '可處理';

  @override
  String get libraryImportStatusNeedsCorrection => '需要修正番號';

  @override
  String libraryImportSelected(int count) {
    return '已選取 $count 個檔案';
  }

  @override
  String libraryImportResult(int succeeded, int duplicate, int failed) {
    return '匯入結果：成功 $succeeded、重複 $duplicate、失敗 $failed';
  }

  @override
  String libraryImportProgress(
    int index,
    int total,
    String code,
    String filename,
    String phase,
  ) {
    return '項目 $index/$total · $code · $filename · $phase';
  }

  @override
  String libraryImportProgressPhase(String phase) {
    String _temp0 = intl.Intl.selectLogic(phase, {
      'resolving': '解析中',
      'hashing': '計算雜湊',
      'probing': '讀取媒體資訊',
      'preflight': '預檢查',
      'staging': '建立暫存',
      'copying': '複製中',
      'verifying': '驗證中',
      'portableCommit': '建立 Library 媒體',
      'indexing': '寫入索引',
      'linking': '建立連結',
      'sourceCleanup': '清理來源',
      'succeeded': '成功',
      'duplicate': '重複',
      'failed': '失敗',
      'cancelled': '已取消',
      'repairRequired': '需要修復',
      'other': '處理中',
    });
    return '$_temp0';
  }

  @override
  String get libraryImportNoPending => '目前沒有待處理的匯入項目。';

  @override
  String get libraryImportSource => '來源資料夾';

  @override
  String get libraryImportDestination => '目的地 LibraryRoot';

  @override
  String get libraryImportSelectAll => '選取所有可辨識檔案';

  @override
  String get libraryImportClearAll => '清除全部';

  @override
  String get libraryImportReview => '檢查已選取項目';

  @override
  String get libraryImportBackToScan => '返回掃描';

  @override
  String get libraryImportCommit => '正式匯入 Library';

  @override
  String get libraryImportReviewTitle => '檢查匯入內容';

  @override
  String get libraryImportPrimaryPerformer => '主女優';

  @override
  String get libraryImportChoosePrimary => '選擇主女優';

  @override
  String get libraryImportPrimaryRequired => '正式匯入前必須選擇主女優。';

  @override
  String get libraryImportReviewNoItems => '沒有可供檢查的已選取媒體。';

  @override
  String get libraryImportReviewWork => '作品';

  @override
  String get libraryImportReviewMedia => '媒體';

  @override
  String get libraryImportReviewDestination => '目的地';

  @override
  String get libraryImportReviewIssues => '檢查問題';

  @override
  String get libraryImportCommitBlocked => '所有已選取項目準備完成前，不能正式匯入。';

  @override
  String get libraryImportNoRecognizable => '找不到可辨識的影片檔案。';

  @override
  String get libraryMediaTitle => '媒體檔案';

  @override
  String get libraryMediaPlay => '播放媒體';

  @override
  String get libraryMediaUnavailable => '媒體檔案無法使用，請修復 Library 項目。';

  @override
  String get libraryMediaPart => '分段';

  @override
  String get libraryMediaResolution => '解析度';

  @override
  String get libraryMediaFrameRate => '影格率';

  @override
  String get dataHealthLibraryWorks => 'Library 作品';

  @override
  String get dataHealthLibraryMediaIssues => 'Library 媒體問題';

  @override
  String get dataHealthImportRepairs => '匯入待修復';

  @override
  String get dataHealthLibraryLinks => '女優連結問題';

  @override
  String get playbackSettings => '播放設定';

  @override
  String get playbackSeekSeconds => '跳轉間隔';

  @override
  String get playbackHoldSpeed => '長按播放速度';

  @override
  String get seconds => '秒';

  @override
  String get playerBack => '返回';

  @override
  String get playerPlay => '播放';

  @override
  String get playerPause => '暫停';

  @override
  String get playerSpeed => '速度';

  @override
  String get playerSubtitles => '字幕';

  @override
  String get playerFullscreen => '全螢幕';

  @override
  String get playerExitFullscreen => '退出全螢幕';

  @override
  String get playerSubtitleOff => '關閉';

  @override
  String get playerHoldSpeed => '長按速度';

  @override
  String get playerPosition => '播放進度';

  @override
  String get playerPlaybackError => '無法播放這部影片';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn() : super('zh_CN');

  @override
  String get addTitle => '新增收藏';

  @override
  String get noPhoto => '尚无照片';

  @override
  String get selectPhoto => '选择照片';

  @override
  String get removePhoto => '移除照片';

  @override
  String get actressNameRequired => '女优姓名 (必填)';

  @override
  String get saveCard => '保存卡片';

  @override
  String get changePhoto => '更换照片';

  @override
  String get deletePhoto => '删除照片';

  @override
  String get noAttributesSet => '尚未设置属性';

  @override
  String get bodyInfo => '详细资料';

  @override
  String get heightCm => '身高 (cm)';

  @override
  String get weightKg => '体重 (kg)';

  @override
  String get cup => '罩杯';

  @override
  String get measurements => '三围';

  @override
  String get privateNotes => '私人笔记';

  @override
  String get noNotes => '尚无笔记';

  @override
  String get confirmDeleteTitle => '确认删除？';

  @override
  String get deleteWarningWithPhoto => '删除后将无法恢复，连同照片文件也会被清除。';

  @override
  String get cancel => '取消';

  @override
  String get reload => '重新加载';

  @override
  String get confirmDelete => '确定删除';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get appTitle => 'AVACA';

  @override
  String get search => '搜索';

  @override
  String get filterAndSort => '筛选与排序';

  @override
  String get filterSection => '筛选';

  @override
  String get sortSection => '排序';

  @override
  String get sortCreatedDesc => '新增时间（新到旧）';

  @override
  String get sortCreatedAsc => '新增时间（旧到新）';

  @override
  String get sortModifiedDesc => '修改时间（新到旧）';

  @override
  String get sortModifiedAsc => '修改时间（旧到新）';

  @override
  String get sortAgeAsc => '年龄（低到高）';

  @override
  String get sortAgeDesc => '年龄（高到低）';

  @override
  String get birthDate => '生日';

  @override
  String get setBirthDate => '设置生日';

  @override
  String get clear => '清除';

  @override
  String get done => '完成';

  @override
  String ageWithBirthDate(int age, String date) {
    return '$age岁  $date';
  }

  @override
  String get add => '新增';

  @override
  String get settings => '设置';

  @override
  String get themeAndColors => '主题与色彩';

  @override
  String get interfaceSettings => '界面';

  @override
  String loadFailed(String error) {
    return '加载失败：$error';
  }

  @override
  String get noData => '尚无资料';

  @override
  String get searchNameHint => '输入名称快速搜索...';

  @override
  String get applySettings => '应用设置';

  @override
  String get themeMode => '主题模式';

  @override
  String get followSystem => '跟随系统';

  @override
  String get lightTheme => '浅色';

  @override
  String get darkTheme => '深色';

  @override
  String get customTheme => '自定义主题';

  @override
  String get pureBlackAmoled => '纯黑 AMOLED';

  @override
  String get pureBlackOnlyDark => '仅深色主题有效';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => '卡片背景';

  @override
  String get colorOnSurface => '主要文字';

  @override
  String get colorOnSurfaceVariant => '次要文字';

  @override
  String get colorPrimary => '交互主色';

  @override
  String get colorOnPrimary => '主色文字';

  @override
  String get colorOutline => '边框 / 分隔线';

  @override
  String get colorSnackbarBackground => '提示条背景';

  @override
  String adjustColorTitle(String colorLabel) {
    return '调整 $colorLabel';
  }

  @override
  String get apply => '应用';

  @override
  String get imageReadFailedUnsupportedFormat => '图片读取失败，可能格式不支持';

  @override
  String get enterName => '请输入姓名';

  @override
  String get collectionAdded => '收藏成功';

  @override
  String get alreadyInCollection => '已经在收藏库中';

  @override
  String get dataDeleted => '资料已彻底删除';

  @override
  String get deleteFailed => '删除失败';

  @override
  String get photoCroppedRememberSave => '照片裁切完成，请记得按下保存！';

  @override
  String get detailSaved => '详细资料已保存！';

  @override
  String get saveFailedDuplicateName => '保存失败，可能是姓名与他人重复';

  @override
  String get dataNotFound => '找不到资料';

  @override
  String get attrCensored => '有码';

  @override
  String get attrUncensored => '无码';

  @override
  String get attrWestern => '欧美';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '国产';

  @override
  String get filterAll => '全部';

  @override
  String get imageCropLoadErrorTitle => '图片读取错误';

  @override
  String get close => '关闭';

  @override
  String get imageDecodeFailed => '图片解码失败';

  @override
  String get cropZoom => '放大缩小';

  @override
  String get cropPanX => '左右平移';

  @override
  String get cropPanY => '上下平移';

  @override
  String get confirmCrop => '确定裁切';

  @override
  String get language => '语言';

  @override
  String get worksPageSize => '作品页大小';

  @override
  String get worksPageSizeSmall => '小';

  @override
  String get worksPageSizeLarge => '大';

  @override
  String get traditionalChineseTaiwan => '繁体中文（台湾）';

  @override
  String get english => '英文';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get japanese => '日语';

  @override
  String get works => '作品';

  @override
  String get relatedActresses => '关联演员';

  @override
  String get workStorageTitle => '作品存储记录';

  @override
  String get workStorageSaved => '已保存';

  @override
  String get workStorageNotSaved => '未保存';

  @override
  String get workStorageQuality => '画质';

  @override
  String get workStorageFrameRate => '帧率';

  @override
  String get workStorageSave => '保存';

  @override
  String get workStorageUpdated => '作品存储记录已更新';

  @override
  String get workStorageUpdateFailed => '作品存储记录更新失败';

  @override
  String get workStorageFilterStored => '已保存';

  @override
  String get workStorageFilterNotStored => '未保存';

  @override
  String get workStorageFilterAll => '全部';

  @override
  String get aliases => '别名';

  @override
  String get manageAliases => '管理别名';

  @override
  String get aliasInputHint => '输入其他名称';

  @override
  String get addAlias => '新增别名';

  @override
  String get saveAliases => '保存别名';

  @override
  String get noAliases => '暂无别名';

  @override
  String get deleteWorks => '删除作品';

  @override
  String get deleteWorksTitle => '删除选中的作品？';

  @override
  String get deleteWorksWarning => '选中的作品会从数据库中全局移除，也会移除其他女优的作品关联。';

  @override
  String get libraryCollectionDeleteUnavailable => 'Library 收藏项目不提供删除功能。';

  @override
  String worksDeleted(int count) {
    return '已删除 $count 部作品';
  }

  @override
  String get loadFailedGeneric => '加载失败';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressName出演的作品';
  }

  @override
  String get searchWorks => '搜索作品';

  @override
  String get workCodeSearchHint => '输入番号搜索...';

  @override
  String get noMatchingWorks => '找不到匹配的作品';

  @override
  String get noWorks => '暂无作品';

  @override
  String durationMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get studio => '制作商';

  @override
  String get publisher => '发行商';

  @override
  String get series => '系列';

  @override
  String get javBusVerificationTitle => 'JavBus 验证';

  @override
  String get javBusVerificationInstructions =>
      'JavBus 要求手动完成地区成年验证。请回答所有题目，App 会在同一安全会话继续刮削。';

  @override
  String get javBusVerificationSubmit => '提交验证';

  @override
  String get settingsDataTransferTitle => '数据导入与导出';

  @override
  String get settingsDataTransferSubtitle => '使用 ZIP 备份或还原女优、作品、详细资料和图片。';

  @override
  String get dataTransferExportTitle => '导出数据';

  @override
  String get dataTransferExportSubtitle => '选择位置保存完整 ZIP 备份。';

  @override
  String get dataTransferImportTitle => '导入数据';

  @override
  String get dataTransferImportSubtitle => '选择 ZIP 备份并直接还原到当前数据库。';

  @override
  String get dataTransferPreparing => '正在准备数据…';

  @override
  String get dataTransferDuplicateProgress => '等待重复女优选择…';

  @override
  String get dataTransferWriting => '正在写入数据和图片…';

  @override
  String get dataTransferExportSuccess => '导出完成。';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return '导出完成，跳过 $count 张无法使用的图片。';
  }

  @override
  String get dataTransferImportSuccess => '导入完成，数据已可直接使用。';

  @override
  String get dataTransferDuplicateTitle => '发现重复女优';

  @override
  String get dataTransferDuplicateExplanation =>
      '请比较头像和作品数，选择要采用哪一份女优详细资料。现有作品和关联会保留。';

  @override
  String get dataTransferKeepExisting => '保留当前资料';

  @override
  String get dataTransferUseImported => '使用导入资料';

  @override
  String get dataTransferContinue => '继续';

  @override
  String dataTransferWorkCount(int count) {
    return '作品数：$count';
  }

  @override
  String get dataTransferArchiveTooLarge => 'ZIP 文件超过支持的大小。';

  @override
  String get dataTransferUnsafeArchive => 'ZIP 含有不安全的文件路径。';

  @override
  String get dataTransferCorruptArchive => 'ZIP 文件损坏或图片校验失败。';

  @override
  String get dataTransferFileUnreadable => '无法读取所选文件。';

  @override
  String get dataTransferActorNameConflict => '导入女优名称与其他资料冲突。';

  @override
  String get dataTransferBusy => '已有另一个数据传输作业正在进行。';

  @override
  String get dataTransferFailed => '数据传输失败，现有资料未变更。';

  @override
  String get otherSettings => '其他';

  @override
  String get about => '关于';

  @override
  String get github => 'github';

  @override
  String get feedbackSuggestions => '反馈建议';

  @override
  String get softwareUpdate => '软件更新';

  @override
  String get softwareUpdateDescription => '检查并安装 AVACA 的最新版本。';

  @override
  String get currentVersion => '当前版本';

  @override
  String get latestVersion => '最新版本';

  @override
  String get autoCheckUpdates => '自动检查更新';

  @override
  String get checkForUpdates => '检查更新';

  @override
  String get checkingForUpdates => '正在检查更新…';

  @override
  String get downloadingUpdate => '正在下载更新…';

  @override
  String get verifyingUpdate => '正在验证更新…';

  @override
  String get installingUpdate => '正在启动安装…';

  @override
  String get updateAvailable => '有新版本可用';

  @override
  String get upToDate => '当前已经是最新版本。';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateLater => '稍后';

  @override
  String get updateUnavailable => '此版本没有适用于此设备的更新文件。';

  @override
  String get updateCheckFailed => '检查更新失败，请稍后再试。';

  @override
  String get updateDownloadFailed => '更新下载失败，现有资料未变更。';

  @override
  String get updateIntegrityFailed => '更新文件验证失败，已停止更新。';

  @override
  String get updateNotSupported => '此设备不支持自动更新。';

  @override
  String get updateInstallPermissionRequired => '请先允许 AVACA 安装未知来源的应用。';

  @override
  String get updatePortableFolderNotWritable => 'portable 程序文件夹无法写入，已停止更新。';

  @override
  String get updateInstallerFailed => '更新程序无法启动，原有版本仍会保留。';

  @override
  String get updateDataPreserved => '用户资料与设置会保留。';

  @override
  String get prefixRouteRulesTitle => '作品图片 Prefix 路由规则';

  @override
  String get prefixRouteRulesSubtitle => '查看并管理由实际验证下载结果学习的图片 family。';

  @override
  String prefixRouteRuleCount(int count) {
    return '已学习 $count 条 Prefix 规则';
  }

  @override
  String get prefixRouteSearchHint => '搜索 Prefix';

  @override
  String get prefixRouteNoRules => '尚未学习任何 Prefix 路由规则。';

  @override
  String get prefixRouteNoSearchResults => '没有符合搜索条件的 Prefix 规则。';

  @override
  String get prefixRouteBestFamily => '当前优先 family';

  @override
  String get prefixRouteNotAvailable => '无';

  @override
  String get prefixRouteCandidates => '已知候选路由';

  @override
  String prefixRouteSuccessCount(int count) {
    return '成功：$count 次';
  }

  @override
  String prefixRouteFailureCount(int count) {
    return '失败：$count 次';
  }

  @override
  String prefixRouteLastSuccess(String time) {
    return '最后成功：$time';
  }

  @override
  String prefixRouteLastFailure(String time) {
    return '最后失败：$time';
  }

  @override
  String get prefixRouteStatusVerified => '已验证';

  @override
  String get prefixRouteStatusExceptions => '有例外';

  @override
  String get prefixRouteStatusPending => '待重新验证';

  @override
  String get prefixRouteStatusProbeFailed => '探测失败';

  @override
  String get prefixRouteManualOverride => '手动指定 route';

  @override
  String get prefixRouteAutomatic => '自动';

  @override
  String get prefixRouteAutomaticDescription => '优先使用已学习候选，必要时再探测当前支持的 family。';

  @override
  String get prefixRouteManualDescription => '会优先尝试此 family；原有学习统计仍会保留。';

  @override
  String get prefixRouteFamilyDmmStandard => 'DMM Standard';

  @override
  String get prefixRouteFamilyDmmLeadingOne => 'DMM Leading One';

  @override
  String get prefixRouteFamilyDmmH1711 => 'DMM H1711';

  @override
  String get prefixRouteFamilyDmmRebeccaH346 => 'DMM Rebecca H346';

  @override
  String get prefixRouteFamilyMgstagePrestige => 'MGStage Prestige';

  @override
  String get prefixRouteFamilyMgstageSeikyouiku => 'MGStage Seikyouiku';

  @override
  String get prefixRouteExport => '导出规则';

  @override
  String get prefixRouteImport => '导入规则';

  @override
  String get prefixRouteExportDialogTitle => '导出 Prefix 规则';

  @override
  String get prefixRouteExportRulesOnly => '仅规则';

  @override
  String get prefixRouteExportRulesOnlyDescription => '导出 family，不包含验证统计。';

  @override
  String get prefixRouteExportWithStatistics => '规则与统计';

  @override
  String get prefixRouteExportWithStatisticsDescription => '包含成功、失败与时间资料。';

  @override
  String get prefixRouteExportSuccess => 'Prefix 规则已导出。';

  @override
  String get prefixRouteImportDialogTitle => '导入 Prefix 规则';

  @override
  String prefixRouteImportPreview(int rules, int conflicts) {
    return '找到 $rules 条规则。手动指定冲突：$conflicts。';
  }

  @override
  String get prefixRouteImportMerge => '合并';

  @override
  String get prefixRouteImportReplace => '替换';

  @override
  String prefixRouteImportSuccess(int count) {
    return '已导入 $count 条 Prefix 规则。';
  }

  @override
  String get prefixRouteOperationFailed => 'Prefix 路由操作失败，现有规则未变更。';

  @override
  String get prefixRouteLoadFailed => '无法加载 Prefix 路由规则。';

  @override
  String get prefixRouteClearAutomatic => '清除自动学习';

  @override
  String get prefixRouteClearAutomaticTitle => '清除自动学习？';

  @override
  String get prefixRouteClearAutomaticMessage => '将清除已学习候选与统计；手动指定与已下载图片会保留。';

  @override
  String get prefixRouteClearAutomaticSuccess => '已清除 Prefix 自动学习资料。';

  @override
  String get prefixRouteReset => '重设此 Prefix 学习';

  @override
  String get prefixRouteResetTitle => '重设此 Prefix 的学习资料？';

  @override
  String get prefixRouteResetMessage => '将清除候选与统计；如果有手动指定 route，会保留。';

  @override
  String get prefixRouteForget => '移除此 Prefix 规则';

  @override
  String get prefixRouteForgetTitle => '移除此 Prefix 规则？';

  @override
  String get prefixRouteForgetMessage =>
      '将移除此 Prefix 的学习资料与手动指定；不会变更已下载图片或作品资料。';

  @override
  String get workFieldProvenanceTitle => '字段来源';

  @override
  String get workFieldProvenanceSource => '来源';

  @override
  String get workFieldProvenanceObservedAt => '观测时间';

  @override
  String get workFieldProvenanceUnknown => '未知来源';

  @override
  String get dataHealthTitle => '数据健康度';

  @override
  String get dataHealthSubtitle => '检查数量、作品字段与图片缺漏、字段来源及待清理文件。';

  @override
  String dataHealthSectionUnavailable(String section) {
    return '此区段无法加载：$section';
  }

  @override
  String get dataHealthRefresh => '刷新';

  @override
  String get dataHealthActresses => '女优';

  @override
  String get dataHealthWorks => '作品';

  @override
  String get dataHealthStored => '已收藏影片';

  @override
  String get dataHealthNotStored => '未收藏影片';

  @override
  String get dataHealthMetadataIssues => '缺少作品字段';

  @override
  String get dataHealthMissingImages => '缺少图片引用';

  @override
  String get dataHealthMissingProvenance => '缺少字段来源';

  @override
  String get dataHealthPendingDeletions => '待清理文件';

  @override
  String get settingsDataHealthTitle => '数据健康度';

  @override
  String get settingsDataHealthSubtitle => '查看数据完整性与字段来源。';

  @override
  String get libraryImportTitle => '文件夹刮削与媒体入库';

  @override
  String get libraryImportOpen => '导入影片';

  @override
  String get libraryImportSelectFolder => '选择刮削文件夹';

  @override
  String get libraryImportSelectRoot => '选择收藏文件夹';

  @override
  String get libraryImportScan => '扫描文件夹';

  @override
  String get libraryImportConfirm => '确认并开始刮削';

  @override
  String get libraryImportPhase1ReadOnly => '当前阶段只读取文件名和文件信息，不会修改来源视频。';

  @override
  String get libraryImportNoFolder => '请先选择刮削文件夹。';

  @override
  String get libraryImportNoRoot => '请先选择收藏文件夹。';

  @override
  String get libraryImportMediaAccessRequired =>
      '请允许 AVACA 读取所选文件夹中的视频，然后重新扫描。';

  @override
  String get libraryImportManualCode => '手动修正番号';

  @override
  String get libraryImportStatusReady => '可处理';

  @override
  String get libraryImportStatusNeedsCorrection => '需要修正番号';

  @override
  String libraryImportSelected(int count) {
    return '已选择 $count 个文件';
  }

  @override
  String libraryImportResult(int succeeded, int duplicate, int failed) {
    return '导入结果：成功 $succeeded、重复 $duplicate、失败 $failed';
  }

  @override
  String libraryImportProgress(
    int index,
    int total,
    String code,
    String filename,
    String phase,
  ) {
    return '项目 $index/$total · $code · $filename · $phase';
  }

  @override
  String libraryImportProgressPhase(String phase) {
    String _temp0 = intl.Intl.selectLogic(phase, {
      'resolving': '解析中',
      'hashing': '计算哈希',
      'probing': '读取媒体信息',
      'preflight': '预检',
      'staging': '建立暂存',
      'copying': '复制中',
      'verifying': '验证中',
      'portableCommit': '建立 Library 媒体',
      'indexing': '写入索引',
      'linking': '建立链接',
      'sourceCleanup': '清理来源',
      'succeeded': '成功',
      'duplicate': '重复',
      'failed': '失败',
      'cancelled': '已取消',
      'repairRequired': '需要修复',
      'other': '处理中',
    });
    return '$_temp0';
  }

  @override
  String get libraryImportNoPending => '目前没有待处理的导入项目。';

  @override
  String get libraryMediaTitle => '媒体文件';

  @override
  String get libraryMediaPlay => '播放媒体';

  @override
  String get libraryMediaUnavailable => '媒体文件不可用，请修复 Library 项目。';

  @override
  String get libraryMediaPart => '分段';

  @override
  String get libraryMediaResolution => '分辨率';

  @override
  String get libraryMediaFrameRate => '帧率';

  @override
  String get dataHealthLibraryWorks => 'Library 作品';

  @override
  String get dataHealthLibraryMediaIssues => 'Library 媒体问题';

  @override
  String get dataHealthImportRepairs => '待修复导入';

  @override
  String get dataHealthLibraryLinks => '女优链接问题';

  @override
  String get playbackSettings => '播放';

  @override
  String get playbackSeekSeconds => '跳转间隔';

  @override
  String get playbackHoldSpeed => '长按播放速度';

  @override
  String get seconds => '秒';

  @override
  String get playerBack => '返回';

  @override
  String get playerPlay => '播放';

  @override
  String get playerPause => '暂停';

  @override
  String get playerSpeed => '速度';

  @override
  String get playerSubtitles => '字幕';

  @override
  String get playerFullscreen => '全屏';

  @override
  String get playerExitFullscreen => '退出全屏';

  @override
  String get playerSubtitleOff => '关闭';

  @override
  String get playerHoldSpeed => '长按速度';

  @override
  String get playerPosition => '播放进度';

  @override
  String get playerPlaybackError => '无法播放此视频';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get addTitle => '新增收藏';

  @override
  String get noPhoto => '尚無照片';

  @override
  String get selectPhoto => '選擇照片';

  @override
  String get removePhoto => '移除照片';

  @override
  String get actressNameRequired => '女優姓名 (必填)';

  @override
  String get saveCard => '儲存卡片';

  @override
  String get changePhoto => '更換照片';

  @override
  String get deletePhoto => '刪除照片';

  @override
  String get noAttributesSet => '尚未設定屬性';

  @override
  String get bodyInfo => '詳細資料';

  @override
  String get heightCm => '身高 (cm)';

  @override
  String get weightKg => '體重 (kg)';

  @override
  String get cup => '罩杯';

  @override
  String get measurements => '三圍';

  @override
  String get privateNotes => '私人筆記';

  @override
  String get noNotes => '尚無筆記';

  @override
  String get confirmDeleteTitle => '確認刪除？';

  @override
  String get deleteWarningWithPhoto => '刪除後將無法復原，連同照片檔案也會被清除。';

  @override
  String get cancel => '取消';

  @override
  String get reload => '重新載入';

  @override
  String get confirmDelete => '確定刪除';

  @override
  String get edit => '編輯';

  @override
  String get delete => '刪除';

  @override
  String get appTitle => 'AVACA';

  @override
  String get search => '搜尋';

  @override
  String get filterAndSort => '篩選與排序';

  @override
  String get filterSection => '篩選';

  @override
  String get sortSection => '排序';

  @override
  String get sortCreatedDesc => '新增時間（新到舊）';

  @override
  String get sortCreatedAsc => '新增時間（舊到新）';

  @override
  String get sortModifiedDesc => '修改時間（新到舊）';

  @override
  String get sortModifiedAsc => '修改時間（舊到新）';

  @override
  String get sortAgeAsc => '年齡（低到高）';

  @override
  String get sortAgeDesc => '年齡（高到低）';

  @override
  String get birthDate => '生日';

  @override
  String get setBirthDate => '設定生日';

  @override
  String get clear => '清除';

  @override
  String get done => '完成';

  @override
  String ageWithBirthDate(int age, String date) {
    return '$age歲  $date';
  }

  @override
  String get add => '新增';

  @override
  String get settings => '設定';

  @override
  String get themeAndColors => '主題與色彩';

  @override
  String get interfaceSettings => '介面';

  @override
  String loadFailed(String error) {
    return '載入失敗：$error';
  }

  @override
  String get noData => '尚無資料';

  @override
  String get searchNameHint => '輸入名稱快速搜尋...';

  @override
  String get applySettings => '套用設定';

  @override
  String get themeMode => '主題模式';

  @override
  String get followSystem => '跟隨系統';

  @override
  String get lightTheme => '淺色';

  @override
  String get darkTheme => '深色';

  @override
  String get customTheme => '自訂主題';

  @override
  String get pureBlackAmoled => '純黑 AMOLED';

  @override
  String get pureBlackOnlyDark => '僅深色主題有效';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => '卡片背景';

  @override
  String get colorOnSurface => '主要文字';

  @override
  String get colorOnSurfaceVariant => '次要文字';

  @override
  String get colorPrimary => '互動主色';

  @override
  String get colorOnPrimary => '主色文字';

  @override
  String get colorOutline => '邊框 / 分隔線';

  @override
  String get colorSnackbarBackground => '提示訊息背景';

  @override
  String adjustColorTitle(String colorLabel) {
    return '調整 $colorLabel';
  }

  @override
  String get apply => '套用';

  @override
  String get imageReadFailedUnsupportedFormat => '圖片讀取失敗，可能格式不支援';

  @override
  String get enterName => '請輸入姓名';

  @override
  String get collectionAdded => '收藏成功';

  @override
  String get alreadyInCollection => '已經在收藏庫中';

  @override
  String get dataDeleted => '資料已徹底刪除';

  @override
  String get deleteFailed => '刪除失敗';

  @override
  String get photoCroppedRememberSave => '照片裁切完成，請記得按下儲存！';

  @override
  String get detailSaved => '詳細資料已儲存！';

  @override
  String get saveFailedDuplicateName => '儲存失敗，可能是姓名與他人重複';

  @override
  String get dataNotFound => '找不到資料';

  @override
  String get attrCensored => '有碼';

  @override
  String get attrUncensored => '無碼';

  @override
  String get attrWestern => '歐美';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '國產';

  @override
  String get filterAll => '全部';

  @override
  String get imageCropLoadErrorTitle => '圖片讀取錯誤';

  @override
  String get close => '關閉';

  @override
  String get imageDecodeFailed => '圖片解碼失敗';

  @override
  String get cropZoom => '放大縮小';

  @override
  String get cropPanX => '左右平移';

  @override
  String get cropPanY => '上下平移';

  @override
  String get confirmCrop => '確定裁切';

  @override
  String get language => '語言';

  @override
  String get worksPageSize => '作品頁大小';

  @override
  String get worksPageSizeSmall => '小';

  @override
  String get worksPageSizeLarge => '大';

  @override
  String get traditionalChineseTaiwan => '繁體中文（台灣）';

  @override
  String get english => '英文';

  @override
  String get simplifiedChinese => '簡體中文';

  @override
  String get japanese => '日文';

  @override
  String get works => '作品';

  @override
  String get relatedActresses => '關聯演員';

  @override
  String get workStorageTitle => '作品儲存記錄';

  @override
  String get workStorageSaved => '已儲存';

  @override
  String get workStorageNotSaved => '未儲存';

  @override
  String get workStorageQuality => '畫質';

  @override
  String get workStorageFrameRate => '幀率';

  @override
  String get workStorageSave => '儲存';

  @override
  String get workStorageUpdated => '作品儲存記錄已更新';

  @override
  String get workStorageUpdateFailed => '作品儲存記錄更新失敗';

  @override
  String get workStorageFilterStored => '已儲存';

  @override
  String get workStorageFilterNotStored => '未儲存';

  @override
  String get workStorageFilterAll => '全部';

  @override
  String get aliases => '別名';

  @override
  String get manageAliases => '管理別名';

  @override
  String get aliasInputHint => '輸入其他名稱';

  @override
  String get addAlias => '新增別名';

  @override
  String get saveAliases => '儲存別名';

  @override
  String get noAliases => '尚無別名';

  @override
  String get deleteWorks => '刪除作品';

  @override
  String get deleteWorksTitle => '刪除選取的作品？';

  @override
  String get deleteWorksWarning => '選取的作品會從資料庫中全域移除，也會移除其他女優的作品連結。';

  @override
  String get libraryCollectionDeleteUnavailable => 'Library 收藏項目不提供刪除功能。';

  @override
  String worksDeleted(int count) {
    return '已刪除 $count 部作品';
  }

  @override
  String get loadFailedGeneric => '載入失敗';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressName演出的作品';
  }

  @override
  String get searchWorks => '搜尋作品';

  @override
  String get workCodeSearchHint => '輸入番號搜尋...';

  @override
  String get noMatchingWorks => '找不到符合的作品';

  @override
  String get noWorks => '尚無作品';

  @override
  String durationMinutes(int minutes) {
    return '$minutes 分鐘';
  }

  @override
  String get studio => '製作商';

  @override
  String get publisher => '發行商';

  @override
  String get series => '系列';

  @override
  String get javBusVerificationTitle => 'JavBus 驗證';

  @override
  String get javBusVerificationInstructions =>
      'JavBus 要求手動完成地區成年驗證。請回答所有題目，App 會在同一安全工作階段繼續刮削。';

  @override
  String get javBusVerificationSubmit => '送出驗證';

  @override
  String get settingsDataTransferTitle => '資料匯入與匯出';

  @override
  String get settingsDataTransferSubtitle => '以 ZIP 備份或還原演員、作品、詳細資料與圖片。';

  @override
  String get dataTransferExportTitle => '匯出資料';

  @override
  String get dataTransferExportSubtitle => '選擇位置儲存完整 ZIP 備份。';

  @override
  String get dataTransferImportTitle => '匯入資料';

  @override
  String get dataTransferImportSubtitle => '選擇 ZIP 備份並直接還原到目前資料庫。';

  @override
  String get dataTransferPreparing => '準備資料中…';

  @override
  String get dataTransferDuplicateProgress => '等待重複演員選擇…';

  @override
  String get dataTransferWriting => '寫入資料與圖片中…';

  @override
  String get dataTransferExportSuccess => '匯出完成。';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return '匯出完成，略過 $count 張無法使用的圖片。';
  }

  @override
  String get dataTransferImportSuccess => '匯入完成，資料已可直接使用。';

  @override
  String get dataTransferDuplicateTitle => '發現重複演員';

  @override
  String get dataTransferDuplicateExplanation =>
      '請比較頭像與作品數，選擇要採用哪一份演員詳細資料。既有作品與關聯會保留。';

  @override
  String get dataTransferKeepExisting => '保留目前資料';

  @override
  String get dataTransferUseImported => '使用匯入資料';

  @override
  String get dataTransferContinue => '繼續';

  @override
  String dataTransferWorkCount(int count) {
    return '作品數：$count';
  }

  @override
  String get dataTransferArchiveTooLarge => 'ZIP 檔案超過可支援的大小。';

  @override
  String get dataTransferUnsafeArchive => 'ZIP 含有不安全的檔案路徑。';

  @override
  String get dataTransferCorruptArchive => 'ZIP 檔案損毀或圖片校驗失敗。';

  @override
  String get dataTransferFileUnreadable => '無法讀取所選檔案。';

  @override
  String get dataTransferActorNameConflict => '匯入演員名稱與其他資料衝突。';

  @override
  String get dataTransferBusy => '已有另一個資料傳輸作業正在進行。';

  @override
  String get dataTransferFailed => '資料傳輸失敗，未變更既有資料。';

  @override
  String get otherSettings => '其他';

  @override
  String get about => '關於';

  @override
  String get github => 'github';

  @override
  String get feedbackSuggestions => '回饋建議';

  @override
  String get softwareUpdate => '軟體更新';

  @override
  String get softwareUpdateDescription => '檢查並安裝 AVACA 的最新版本。';

  @override
  String get currentVersion => '目前版本';

  @override
  String get latestVersion => '最新版本';

  @override
  String get autoCheckUpdates => '自動檢查更新';

  @override
  String get checkForUpdates => '檢查更新';

  @override
  String get checkingForUpdates => '正在檢查更新…';

  @override
  String get downloadingUpdate => '正在下載更新…';

  @override
  String get verifyingUpdate => '正在驗證更新…';

  @override
  String get installingUpdate => '正在啟動安裝…';

  @override
  String get updateAvailable => '有新版本可用';

  @override
  String get upToDate => '目前已是最新版本。';

  @override
  String get updateNow => '立即更新';

  @override
  String get updateLater => '稍後';

  @override
  String get updateUnavailable => '此版本沒有此裝置的更新檔。';

  @override
  String get updateCheckFailed => '檢查更新失敗，請稍後再試。';

  @override
  String get updateDownloadFailed => '更新下載失敗，原有資料未變更。';

  @override
  String get updateIntegrityFailed => '更新檔驗證失敗，已停止更新。';

  @override
  String get updateNotSupported => '此裝置不支援自動更新。';

  @override
  String get updateInstallPermissionRequired => '請先允許 AVACA 安裝未知來源的應用程式。';

  @override
  String get updatePortableFolderNotWritable => 'portable 程式資料夾無法寫入，已停止更新。';

  @override
  String get updateInstallerFailed => '更新程式無法啟動，原有版本仍保留。';

  @override
  String get updateDataPreserved => '使用者資料與設定會保留。';

  @override
  String get prefixRouteRulesTitle => '作品圖片 Prefix 路由規則';

  @override
  String get prefixRouteRulesSubtitle => '查看並管理由實際驗證下載結果學習的圖片 family。';

  @override
  String prefixRouteRuleCount(int count) {
    return '已學習 $count 條 Prefix 規則';
  }

  @override
  String get prefixRouteSearchHint => '搜尋 Prefix';

  @override
  String get prefixRouteNoRules => '尚未學習任何 Prefix 路由規則。';

  @override
  String get prefixRouteNoSearchResults => '沒有符合搜尋條件的 Prefix 規則。';

  @override
  String get prefixRouteBestFamily => '目前優先 family';

  @override
  String get prefixRouteNotAvailable => '無';

  @override
  String get prefixRouteCandidates => '已知候選路由';

  @override
  String prefixRouteSuccessCount(int count) {
    return '成功：$count 次';
  }

  @override
  String prefixRouteFailureCount(int count) {
    return '失敗：$count 次';
  }

  @override
  String prefixRouteLastSuccess(String time) {
    return '最後成功：$time';
  }

  @override
  String prefixRouteLastFailure(String time) {
    return '最後失敗：$time';
  }

  @override
  String get prefixRouteStatusVerified => '已驗證';

  @override
  String get prefixRouteStatusExceptions => '有例外';

  @override
  String get prefixRouteStatusPending => '待重新驗證';

  @override
  String get prefixRouteStatusProbeFailed => '探測失敗';

  @override
  String get prefixRouteManualOverride => '手動指定 route';

  @override
  String get prefixRouteAutomatic => '自動';

  @override
  String get prefixRouteAutomaticDescription => '優先使用已學習候選，必要時再探測目前支援的 family。';

  @override
  String get prefixRouteManualDescription => '會優先嘗試此 family；原有學習統計仍會保留。';

  @override
  String get prefixRouteFamilyDmmStandard => 'DMM Standard';

  @override
  String get prefixRouteFamilyDmmLeadingOne => 'DMM Leading One';

  @override
  String get prefixRouteFamilyDmmH1711 => 'DMM H1711';

  @override
  String get prefixRouteFamilyDmmRebeccaH346 => 'DMM Rebecca H346';

  @override
  String get prefixRouteFamilyMgstagePrestige => 'MGStage Prestige';

  @override
  String get prefixRouteFamilyMgstageSeikyouiku => 'MGStage Seikyouiku';

  @override
  String get prefixRouteExport => '匯出規則';

  @override
  String get prefixRouteImport => '匯入規則';

  @override
  String get prefixRouteExportDialogTitle => '匯出 Prefix 規則';

  @override
  String get prefixRouteExportRulesOnly => '僅規則';

  @override
  String get prefixRouteExportRulesOnlyDescription => '匯出 family，不包含驗證統計。';

  @override
  String get prefixRouteExportWithStatistics => '規則與統計';

  @override
  String get prefixRouteExportWithStatisticsDescription => '包含成功、失敗與時間資料。';

  @override
  String get prefixRouteExportSuccess => 'Prefix 規則已匯出。';

  @override
  String get prefixRouteImportDialogTitle => '匯入 Prefix 規則';

  @override
  String prefixRouteImportPreview(int rules, int conflicts) {
    return '找到 $rules 條規則。手動指定衝突：$conflicts。';
  }

  @override
  String get prefixRouteImportMerge => '合併';

  @override
  String get prefixRouteImportReplace => '取代';

  @override
  String prefixRouteImportSuccess(int count) {
    return '已匯入 $count 條 Prefix 規則。';
  }

  @override
  String get prefixRouteOperationFailed => 'Prefix 路由操作失敗，既有規則未變更。';

  @override
  String get prefixRouteLoadFailed => '無法載入 Prefix 路由規則。';

  @override
  String get prefixRouteClearAutomatic => '清除自動學習';

  @override
  String get prefixRouteClearAutomaticTitle => '清除自動學習？';

  @override
  String get prefixRouteClearAutomaticMessage => '將清除已學習候選與統計；手動指定與已下載圖片會保留。';

  @override
  String get prefixRouteClearAutomaticSuccess => '已清除 Prefix 自動學習資料。';

  @override
  String get prefixRouteReset => '重設此 Prefix 學習';

  @override
  String get prefixRouteResetTitle => '重設此 Prefix 的學習資料？';

  @override
  String get prefixRouteResetMessage => '將清除候選與統計；如果有手動指定 route，會保留。';

  @override
  String get prefixRouteForget => '移除此 Prefix 規則';

  @override
  String get prefixRouteForgetTitle => '移除此 Prefix 規則？';

  @override
  String get prefixRouteForgetMessage =>
      '將移除此 Prefix 的學習資料與手動指定；不會變更已下載圖片或作品資料。';

  @override
  String get workFieldProvenanceTitle => '欄位來源';

  @override
  String get workFieldProvenanceSource => '來源';

  @override
  String get workFieldProvenanceObservedAt => '觀測時間';

  @override
  String get workFieldProvenanceUnknown => '未知來源';

  @override
  String get dataHealthTitle => '資料健康度';

  @override
  String get dataHealthSubtitle => '檢查數量、作品欄位與圖片缺漏、欄位來源及待清理檔案。';

  @override
  String dataHealthSectionUnavailable(String section) {
    return '此區段無法載入：$section';
  }

  @override
  String get dataHealthRefresh => '重新整理';

  @override
  String get dataHealthActresses => '女優';

  @override
  String get dataHealthWorks => '作品';

  @override
  String get dataHealthStored => '已收藏影片';

  @override
  String get dataHealthNotStored => '未收藏影片';

  @override
  String get dataHealthMetadataIssues => '缺少作品欄位';

  @override
  String get dataHealthMissingImages => '缺少圖片引用';

  @override
  String get dataHealthMissingProvenance => '缺少欄位來源';

  @override
  String get dataHealthPendingDeletions => '待清理檔案';

  @override
  String get settingsDataHealthTitle => '資料健康度';

  @override
  String get settingsDataHealthSubtitle => '查看資料完整性與欄位來源。';

  @override
  String get libraryImportTitle => '資料夾刮削與媒體入庫';

  @override
  String get libraryImportOpen => '匯入影片';

  @override
  String get libraryImportSelectFolder => '選擇刮削資料夾';

  @override
  String get libraryImportSelectRoot => '選擇收藏資料夾';

  @override
  String get libraryImportScan => '掃描資料夾';

  @override
  String get libraryImportConfirm => '確認並開始刮削';

  @override
  String get libraryImportPhase1ReadOnly => '目前階段只讀取檔名與檔案資訊，不會修改來源影片。';

  @override
  String get libraryImportNoFolder => '請先選擇刮削資料夾。';

  @override
  String get libraryImportNoRoot => '請先選擇收藏資料夾。';

  @override
  String get libraryImportMediaAccessRequired => '請允許 AVACA 讀取所選資料夾中的影片，再重新掃描。';

  @override
  String get libraryImportManualCode => '手動修正番號';

  @override
  String get libraryImportStatusReady => '可處理';

  @override
  String get libraryImportStatusNeedsCorrection => '需要修正番號';

  @override
  String libraryImportSelected(int count) {
    return '已選取 $count 個檔案';
  }

  @override
  String libraryImportResult(int succeeded, int duplicate, int failed) {
    return '匯入結果：成功 $succeeded、重複 $duplicate、失敗 $failed';
  }

  @override
  String libraryImportProgress(
    int index,
    int total,
    String code,
    String filename,
    String phase,
  ) {
    return '項目 $index/$total · $code · $filename · $phase';
  }

  @override
  String libraryImportProgressPhase(String phase) {
    String _temp0 = intl.Intl.selectLogic(phase, {
      'resolving': '解析中',
      'hashing': '計算雜湊',
      'probing': '讀取媒體資訊',
      'preflight': '預檢查',
      'staging': '建立暫存',
      'copying': '複製中',
      'verifying': '驗證中',
      'portableCommit': '建立 Library 媒體',
      'indexing': '寫入索引',
      'linking': '建立連結',
      'sourceCleanup': '清理來源',
      'succeeded': '成功',
      'duplicate': '重複',
      'failed': '失敗',
      'cancelled': '已取消',
      'repairRequired': '需要修復',
      'other': '處理中',
    });
    return '$_temp0';
  }

  @override
  String get libraryImportNoPending => '目前沒有待處理的匯入項目。';

  @override
  String get libraryImportSource => '來源資料夾';

  @override
  String get libraryImportDestination => '目的地 LibraryRoot';

  @override
  String get libraryImportSelectAll => '選取所有可辨識檔案';

  @override
  String get libraryImportClearAll => '清除全部';

  @override
  String get libraryImportReview => '檢查已選取項目';

  @override
  String get libraryImportBackToScan => '返回掃描';

  @override
  String get libraryImportCommit => '正式匯入 Library';

  @override
  String get libraryImportReviewTitle => '檢查匯入內容';

  @override
  String get libraryImportPrimaryPerformer => '主女優';

  @override
  String get libraryImportChoosePrimary => '選擇主女優';

  @override
  String get libraryImportPrimaryRequired => '正式匯入前必須選擇主女優。';

  @override
  String get libraryImportReviewNoItems => '沒有可供檢查的已選取媒體。';

  @override
  String get libraryImportReviewWork => '作品';

  @override
  String get libraryImportReviewMedia => '媒體';

  @override
  String get libraryImportReviewDestination => '目的地';

  @override
  String get libraryImportReviewIssues => '檢查問題';

  @override
  String get libraryImportCommitBlocked => '所有已選取項目準備完成前，不能正式匯入。';

  @override
  String get libraryImportNoRecognizable => '找不到可辨識的影片檔案。';

  @override
  String get libraryMediaTitle => '媒體檔案';

  @override
  String get libraryMediaPlay => '播放媒體';

  @override
  String get libraryMediaUnavailable => '媒體檔案無法使用，請修復 Library 項目。';

  @override
  String get libraryMediaPart => '分段';

  @override
  String get libraryMediaResolution => '解析度';

  @override
  String get libraryMediaFrameRate => '影格率';

  @override
  String get dataHealthLibraryWorks => 'Library 作品';

  @override
  String get dataHealthLibraryMediaIssues => 'Library 媒體問題';

  @override
  String get dataHealthImportRepairs => '匯入待修復';

  @override
  String get dataHealthLibraryLinks => '女優連結問題';

  @override
  String get playbackSettings => '播放設定';

  @override
  String get playbackSeekSeconds => '跳轉間隔';

  @override
  String get playbackHoldSpeed => '長按播放速度';

  @override
  String get seconds => '秒';

  @override
  String get playerBack => '返回';

  @override
  String get playerPlay => '播放';

  @override
  String get playerPause => '暫停';

  @override
  String get playerSpeed => '速度';

  @override
  String get playerSubtitles => '字幕';

  @override
  String get playerFullscreen => '全螢幕';

  @override
  String get playerExitFullscreen => '退出全螢幕';

  @override
  String get playerSubtitleOff => '關閉';

  @override
  String get playerHoldSpeed => '長按速度';

  @override
  String get playerPosition => '播放進度';

  @override
  String get playerPlaybackError => '無法播放這部影片';
}
