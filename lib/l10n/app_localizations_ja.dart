// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get addTitle => 'コレクションに追加';

  @override
  String get noPhoto => '写真なし';

  @override
  String get selectPhoto => '写真を選択';

  @override
  String get removePhoto => '写真を削除';

  @override
  String get actressNameRequired => '女優名（必須）';

  @override
  String get saveCard => 'カードを保存';

  @override
  String get changePhoto => '写真を変更';

  @override
  String get deletePhoto => '写真を削除';

  @override
  String get noAttributesSet => '属性未設定';

  @override
  String get bodyInfo => '詳細情報';

  @override
  String get heightCm => '身長（cm）';

  @override
  String get weightKg => '体重（kg）';

  @override
  String get cup => 'カップ';

  @override
  String get measurements => 'スリーサイズ';

  @override
  String get privateNotes => '非公開メモ';

  @override
  String get noNotes => 'メモなし';

  @override
  String get confirmDeleteTitle => '削除しますか？';

  @override
  String get deleteWarningWithPhoto => 'この操作は元に戻せません。写真ファイルも削除されます。';

  @override
  String get cancel => 'キャンセル';

  @override
  String get confirmDelete => '削除';

  @override
  String get edit => '編集';

  @override
  String get delete => '削除';

  @override
  String get appTitle => 'AVACA コレクションライブラリ';

  @override
  String get search => '検索';

  @override
  String get filterAndSort => '絞り込み・並べ替え';

  @override
  String get filterSection => '絞り込み';

  @override
  String get sortSection => '並べ替え';

  @override
  String get sortCreatedDesc => '追加日（新しい順）';

  @override
  String get sortCreatedAsc => '追加日（古い順）';

  @override
  String get sortModifiedDesc => '更新日（新しい順）';

  @override
  String get sortModifiedAsc => '更新日（古い順）';

  @override
  String get sortAgeAsc => '年齢（低い順）';

  @override
  String get sortAgeDesc => '年齢（高い順）';

  @override
  String get birthDate => '生年月日';

  @override
  String get setBirthDate => '生年月日を設定';

  @override
  String get clear => 'クリア';

  @override
  String get done => '完了';

  @override
  String ageWithBirthDate(int age, String date) {
    return '$age歳  $date';
  }

  @override
  String get add => '追加';

  @override
  String get settings => '設定';

  @override
  String get themeAndColors => 'テーマと色';

  @override
  String get interfaceSettings => 'インターフェース';

  @override
  String loadFailed(String error) {
    return '読み込みに失敗しました: $error';
  }

  @override
  String get noData => 'データなし';

  @override
  String get searchNameHint => '名前を入力してすばやく検索...';

  @override
  String get applySettings => '設定を適用';

  @override
  String get themeMode => 'テーマモード';

  @override
  String get followSystem => 'システム設定に従う';

  @override
  String get lightTheme => 'ライト';

  @override
  String get darkTheme => 'ダーク';

  @override
  String get customTheme => 'カスタムテーマ';

  @override
  String get pureBlackAmoled => 'ピュアブラック AMOLED';

  @override
  String get pureBlackOnlyDark => 'ダークテーマでのみ有効です';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => 'カード背景';

  @override
  String get colorOnSurface => 'メインテキスト';

  @override
  String get colorOnSurfaceVariant => 'サブテキスト';

  @override
  String get colorPrimary => 'メインアクセント';

  @override
  String get colorOnPrimary => 'アクセント上のテキスト';

  @override
  String get colorOutline => '境界線 / 区切り線';

  @override
  String get colorSnackbarBackground => 'スナックバーの背景';

  @override
  String adjustColorTitle(String colorLabel) {
    return '$colorLabelを調整';
  }

  @override
  String get apply => '適用';

  @override
  String get imageReadFailedUnsupportedFormat =>
      '画像を読み込めませんでした。対応していない形式の可能性があります。';

  @override
  String get enterName => '名前を入力してください';

  @override
  String get collectionAdded => 'コレクションに追加しました';

  @override
  String get alreadyInCollection => 'すでにコレクションに登録されています';

  @override
  String get dataDeleted => 'データを完全に削除しました';

  @override
  String get deleteFailed => '削除に失敗しました';

  @override
  String get photoCroppedRememberSave => '写真を切り抜きました。忘れずに保存してください。';

  @override
  String get detailSaved => '詳細を保存しました';

  @override
  String get saveFailedDuplicateName => '保存に失敗しました。同じ名前がすでに存在する可能性があります。';

  @override
  String get dataNotFound => 'データが見つかりません';

  @override
  String get attrCensored => 'モザイクあり';

  @override
  String get attrUncensored => '無修正';

  @override
  String get attrWestern => '洋物';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '国内';

  @override
  String get filterAll => 'すべて';

  @override
  String get imageCropLoadErrorTitle => '画像の読み込みエラー';

  @override
  String get close => '閉じる';

  @override
  String get imageDecodeFailed => '画像のデコードに失敗しました';

  @override
  String get cropZoom => '拡大・縮小';

  @override
  String get cropPanX => '水平方向に移動';

  @override
  String get cropPanY => '垂直方向に移動';

  @override
  String get confirmCrop => '切り抜く';

  @override
  String get language => '言語';

  @override
  String get worksPageSize => '作品ページのサイズ';

  @override
  String get worksPageSizeSmall => '小';

  @override
  String get worksPageSizeLarge => '大';

  @override
  String get traditionalChineseTaiwan => '繁体字中国語（台湾）';

  @override
  String get english => '英語';

  @override
  String get simplifiedChinese => '簡体字中国語';

  @override
  String get japanese => '日本語';

  @override
  String get works => '作品';

  @override
  String get aliases => '別名';

  @override
  String get manageAliases => '別名を管理';

  @override
  String get aliasInputHint => '別名を入力';

  @override
  String get addAlias => '別名を追加';

  @override
  String get saveAliases => '別名を保存';

  @override
  String get noAliases => '別名はありません';

  @override
  String get deleteWorks => '作品を削除';

  @override
  String get deleteWorksTitle => '選択した作品を削除しますか？';

  @override
  String get deleteWorksWarning => '選択した作品を全体から削除し、他の女優からの作品リンクも削除します。';

  @override
  String worksDeleted(int count) {
    return '$count 件の作品を削除しました';
  }

  @override
  String get loadFailedGeneric => '読み込みに失敗しました';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressNameの出演作品';
  }

  @override
  String get searchWorks => '作品を検索';

  @override
  String get workCodeSearchHint => '品番を入力して検索...';

  @override
  String get noMatchingWorks => '一致する作品がありません';

  @override
  String get scrapeWorks => '作品情報を取得';

  @override
  String get scrapeSettings => '取得設定';

  @override
  String get syncActressDetails => 'プロフィール詳細を同期';

  @override
  String get replaceActressImage => '女優画像を差し替える';

  @override
  String get maxActressCountLabel => 'この人数を超える女優の作品は取得しない';

  @override
  String get maxActressCountHint => '0 は制限なし';

  @override
  String get maxActressCountInvalid => '0以上の整数を入力してください';

  @override
  String get scrapeAvatarUnavailable => '利用可能な女優画像が見つかりませんでした。';

  @override
  String get scrapeAvatarFailed => '女優画像の差し替えに失敗したため、元の画像を保持しました。';

  @override
  String get fillMissingOnly => '再取得時は未入力の情報のみ補完';

  @override
  String get excludedCodePrefixes => '除外する品番プレフィックス';

  @override
  String get codePrefixHint => '品番プレフィックスを入力';

  @override
  String get addPrefix => '追加';

  @override
  String get startScrape => '取得を開始';

  @override
  String get noWorks => '作品はまだありません';

  @override
  String durationMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String get studio => 'メーカー';

  @override
  String get publisher => 'レーベル';

  @override
  String get series => 'シリーズ';

  @override
  String scrapeComplete(int saved, int excluded, int failed) {
    return '取得完了: 保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String scrapeCancelled(int saved, int excluded, int failed) {
    return '取得をキャンセルしました: 保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String get scrapeFailed => '取得に失敗しました。もう一度お試しください。';

  @override
  String get javBusVerificationTitle => 'JavBus の確認';

  @override
  String get javBusVerificationInstructions =>
      'JavBus では地域別の年齢確認を手動で行う必要があります。同じ安全なセッションで取得を続けるには、すべての質問に回答してください。';

  @override
  String get javBusVerificationSubmit => '確認を送信';

  @override
  String get settingsDataTransferTitle => 'データの入出力';

  @override
  String get settingsDataTransferSubtitle =>
      '女優、作品、詳細情報、画像を ZIP でバックアップまたは復元します。';

  @override
  String get dataTransferExportTitle => 'データをエクスポート';

  @override
  String get dataTransferExportSubtitle => '完全な ZIP バックアップの保存先を選択します。';

  @override
  String get dataTransferImportTitle => 'データをインポート';

  @override
  String get dataTransferImportSubtitle => 'ZIP バックアップを選択してすぐに復元します。';

  @override
  String get dataTransferPreparing => 'データを準備中…';

  @override
  String get dataTransferDuplicateProgress => '重複する女優の選択を待っています…';

  @override
  String get dataTransferWriting => 'データと画像を書き込み中…';

  @override
  String get dataTransferExportSuccess => 'エクスポートが完了しました。';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return 'エクスポート完了。使用できない画像を $count 枚スキップしました。';
  }

  @override
  String get dataTransferImportSuccess => 'インポートが完了しました。データをすぐに使用できます。';

  @override
  String get dataTransferDuplicateTitle => '重複する女優が見つかりました';

  @override
  String get dataTransferDuplicateExplanation =>
      '画像と作品数を比較して、使用する女優の詳細情報を選択してください。既存の作品と関連付けは保持されます。';

  @override
  String get dataTransferKeepExisting => '現在の詳細を保持';

  @override
  String get dataTransferUseImported => 'インポートした詳細を使用';

  @override
  String get dataTransferContinue => '続行';

  @override
  String dataTransferWorkCount(int count) {
    return '作品数: $count';
  }

  @override
  String get dataTransferArchiveTooLarge => 'ZIP が対応サイズを超えています。';

  @override
  String get dataTransferUnsafeArchive => 'ZIP に安全でないファイルパスが含まれています。';

  @override
  String get dataTransferCorruptArchive => 'ZIP が壊れているか、画像のチェックサムに失敗しました。';

  @override
  String get dataTransferFileUnreadable => '選択したファイルを読み取れませんでした。';

  @override
  String get dataTransferActorNameConflict => 'インポートした女優名が別のデータと競合しています。';

  @override
  String get dataTransferBusy => '別のデータ転送が進行中です。';

  @override
  String get dataTransferFailed => 'データ転送に失敗しました。既存データは変更されていません。';

  @override
  String get otherSettings => 'その他';

  @override
  String get scrapeSources => '取得元';

  @override
  String get softwareUpdate => 'ソフトウェア更新';

  @override
  String get softwareUpdateDescription => 'AVACA の最新バージョンを確認してインストールします。';

  @override
  String get currentVersion => '現在のバージョン';

  @override
  String get latestVersion => '最新バージョン';

  @override
  String get autoCheckUpdates => '更新を自動的に確認';

  @override
  String get checkForUpdates => '更新を確認';

  @override
  String get checkingForUpdates => '更新を確認中…';

  @override
  String get downloadingUpdate => '更新をダウンロード中…';

  @override
  String get verifyingUpdate => '更新を検証中…';

  @override
  String get installingUpdate => 'インストールを開始中…';

  @override
  String get updateAvailable => '新しいバージョンがあります';

  @override
  String get upToDate => 'AVACA は最新です。';

  @override
  String get updateNow => '今すぐ更新';

  @override
  String get updateLater => '後で';

  @override
  String get updateUnavailable => 'このデバイスに対応する更新ファイルがありません。';

  @override
  String get updateCheckFailed => '更新を確認できませんでした。後でもう一度お試しください。';

  @override
  String get updateDownloadFailed => '更新のダウンロードに失敗しました。既存データは変更されていません。';

  @override
  String get updateIntegrityFailed => '更新ファイルの検証に失敗したため、更新を停止しました。';

  @override
  String get updateNotSupported => 'このデバイスでは自動更新に対応していません。';

  @override
  String get updateInstallPermissionRequired =>
      '先に AVACA に提供元不明のアプリのインストールを許可してください。';

  @override
  String get updatePortableFolderNotWritable =>
      'portable アプリフォルダーに書き込めないため、更新を停止しました。';

  @override
  String get updateInstallerFailed => '更新プログラムを開始できませんでした。現在のバージョンを保持しています。';

  @override
  String get updateDataPreserved => 'データと設定は保持されます。';
}

/// The translations for Japanese, as used in Japan (`ja_JP`).
class AppLocalizationsJaJp extends AppLocalizationsJa {
  AppLocalizationsJaJp() : super('ja_JP');

  @override
  String get addTitle => 'コレクションに追加';

  @override
  String get noPhoto => '写真なし';

  @override
  String get selectPhoto => '写真を選択';

  @override
  String get removePhoto => '写真を削除';

  @override
  String get actressNameRequired => '女優名（必須）';

  @override
  String get saveCard => 'カードを保存';

  @override
  String get changePhoto => '写真を変更';

  @override
  String get deletePhoto => '写真を削除';

  @override
  String get noAttributesSet => '属性未設定';

  @override
  String get bodyInfo => '詳細情報';

  @override
  String get heightCm => '身長（cm）';

  @override
  String get weightKg => '体重（kg）';

  @override
  String get cup => 'カップ';

  @override
  String get measurements => 'スリーサイズ';

  @override
  String get privateNotes => '非公開メモ';

  @override
  String get noNotes => 'メモなし';

  @override
  String get confirmDeleteTitle => '削除しますか？';

  @override
  String get deleteWarningWithPhoto => 'この操作は元に戻せません。写真ファイルも削除されます。';

  @override
  String get cancel => 'キャンセル';

  @override
  String get confirmDelete => '削除';

  @override
  String get edit => '編集';

  @override
  String get delete => '削除';

  @override
  String get appTitle => 'AVACA';

  @override
  String get search => '検索';

  @override
  String get filterAndSort => '絞り込み・並べ替え';

  @override
  String get filterSection => '絞り込み';

  @override
  String get sortSection => '並べ替え';

  @override
  String get sortCreatedDesc => '追加日（新しい順）';

  @override
  String get sortCreatedAsc => '追加日（古い順）';

  @override
  String get sortModifiedDesc => '更新日（新しい順）';

  @override
  String get sortModifiedAsc => '更新日（古い順）';

  @override
  String get sortAgeAsc => '年齢（低い順）';

  @override
  String get sortAgeDesc => '年齢（高い順）';

  @override
  String get birthDate => '生年月日';

  @override
  String get setBirthDate => '生年月日を設定';

  @override
  String get clear => 'クリア';

  @override
  String get done => '完了';

  @override
  String ageWithBirthDate(int age, String date) {
    return '$age歳  $date';
  }

  @override
  String get add => '追加';

  @override
  String get settings => '設定';

  @override
  String get themeAndColors => 'テーマと色';

  @override
  String get interfaceSettings => 'インターフェース';

  @override
  String loadFailed(String error) {
    return '読み込みに失敗しました: $error';
  }

  @override
  String get noData => 'データなし';

  @override
  String get searchNameHint => '名前を入力してすばやく検索...';

  @override
  String get applySettings => '設定を適用';

  @override
  String get themeMode => 'テーマモード';

  @override
  String get followSystem => 'システム設定に従う';

  @override
  String get lightTheme => 'ライト';

  @override
  String get darkTheme => 'ダーク';

  @override
  String get customTheme => 'カスタムテーマ';

  @override
  String get pureBlackAmoled => 'ピュアブラック AMOLED';

  @override
  String get pureBlackOnlyDark => 'ダークテーマでのみ有効です';

  @override
  String get colorSurface => '背景';

  @override
  String get colorSurfaceContainer => 'カード背景';

  @override
  String get colorOnSurface => 'メインテキスト';

  @override
  String get colorOnSurfaceVariant => 'サブテキスト';

  @override
  String get colorPrimary => 'メインアクセント';

  @override
  String get colorOnPrimary => 'アクセント上のテキスト';

  @override
  String get colorOutline => '境界線 / 区切り線';

  @override
  String get colorSnackbarBackground => 'スナックバーの背景';

  @override
  String adjustColorTitle(String colorLabel) {
    return '$colorLabelを調整';
  }

  @override
  String get apply => '適用';

  @override
  String get imageReadFailedUnsupportedFormat =>
      '画像を読み込めませんでした。対応していない形式の可能性があります。';

  @override
  String get enterName => '名前を入力してください';

  @override
  String get collectionAdded => 'コレクションに追加しました';

  @override
  String get alreadyInCollection => 'すでにコレクションに登録されています';

  @override
  String get dataDeleted => 'データを完全に削除しました';

  @override
  String get deleteFailed => '削除に失敗しました';

  @override
  String get photoCroppedRememberSave => '写真を切り抜きました。忘れずに保存してください。';

  @override
  String get detailSaved => '詳細を保存しました';

  @override
  String get saveFailedDuplicateName => '保存に失敗しました。同じ名前がすでに存在する可能性があります。';

  @override
  String get dataNotFound => 'データが見つかりません';

  @override
  String get attrCensored => 'モザイクあり';

  @override
  String get attrUncensored => '無修正';

  @override
  String get attrWestern => '洋物';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => '国内';

  @override
  String get filterAll => 'すべて';

  @override
  String get imageCropLoadErrorTitle => '画像の読み込みエラー';

  @override
  String get close => '閉じる';

  @override
  String get imageDecodeFailed => '画像のデコードに失敗しました';

  @override
  String get cropZoom => '拡大・縮小';

  @override
  String get cropPanX => '水平方向に移動';

  @override
  String get cropPanY => '垂直方向に移動';

  @override
  String get confirmCrop => '切り抜く';

  @override
  String get language => '言語';

  @override
  String get worksPageSize => '作品ページのサイズ';

  @override
  String get worksPageSizeSmall => '小';

  @override
  String get worksPageSizeLarge => '大';

  @override
  String get traditionalChineseTaiwan => '繁体字中国語（台湾）';

  @override
  String get english => '英語';

  @override
  String get simplifiedChinese => '簡体字中国語';

  @override
  String get japanese => '日本語';

  @override
  String get works => '作品';

  @override
  String get aliases => '別名';

  @override
  String get manageAliases => '別名を管理';

  @override
  String get aliasInputHint => '別名を入力';

  @override
  String get addAlias => '別名を追加';

  @override
  String get saveAliases => '別名を保存';

  @override
  String get noAliases => '別名はありません';

  @override
  String get deleteWorks => '作品を削除';

  @override
  String get deleteWorksTitle => '選択した作品を削除しますか？';

  @override
  String get deleteWorksWarning => '選択した作品を全体から削除し、他の女優からの作品リンクも削除します。';

  @override
  String worksDeleted(int count) {
    return '$count 件の作品を削除しました';
  }

  @override
  String get loadFailedGeneric => '読み込みに失敗しました';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressNameの出演作品';
  }

  @override
  String get searchWorks => '作品を検索';

  @override
  String get workCodeSearchHint => '品番を入力して検索...';

  @override
  String get noMatchingWorks => '一致する作品がありません';

  @override
  String get scrapeWorks => '作品情報を取得';

  @override
  String get scrapeSettings => '取得設定';

  @override
  String get syncActressDetails => 'プロフィール詳細を同期';

  @override
  String get replaceActressImage => '女優画像を差し替える';

  @override
  String get maxActressCountLabel => 'この人数を超える女優の作品は取得しない';

  @override
  String get maxActressCountHint => '0 は制限なし';

  @override
  String get maxActressCountInvalid => '0以上の整数を入力してください';

  @override
  String get scrapeAvatarUnavailable => '利用可能な女優画像が見つかりませんでした。';

  @override
  String get scrapeAvatarFailed => '女優画像の差し替えに失敗したため、元の画像を保持しました。';

  @override
  String get fillMissingOnly => '再取得時は未入力の情報のみ補完';

  @override
  String get excludedCodePrefixes => '除外する品番プレフィックス';

  @override
  String get codePrefixHint => '品番プレフィックスを入力';

  @override
  String get addPrefix => '追加';

  @override
  String get startScrape => '取得を開始';

  @override
  String get noWorks => '作品はまだありません';

  @override
  String durationMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String get studio => 'メーカー';

  @override
  String get publisher => 'レーベル';

  @override
  String get series => 'シリーズ';

  @override
  String scrapeComplete(int saved, int excluded, int failed) {
    return '取得完了: 保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String scrapeCancelled(int saved, int excluded, int failed) {
    return '取得をキャンセルしました: 保存 $saved件、除外 $excluded件、失敗 $failed件';
  }

  @override
  String get scrapeFailed => '取得に失敗しました。もう一度お試しください。';

  @override
  String get javBusVerificationTitle => 'JavBus の確認';

  @override
  String get javBusVerificationInstructions =>
      'JavBus では地域別の年齢確認を手動で行う必要があります。同じ安全なセッションで取得を続けるには、すべての質問に回答してください。';

  @override
  String get javBusVerificationSubmit => '確認を送信';

  @override
  String get settingsDataTransferTitle => 'データの入出力';

  @override
  String get settingsDataTransferSubtitle =>
      '女優、作品、詳細情報、画像を ZIP でバックアップまたは復元します。';

  @override
  String get dataTransferExportTitle => 'データをエクスポート';

  @override
  String get dataTransferExportSubtitle => '完全な ZIP バックアップの保存先を選択します。';

  @override
  String get dataTransferImportTitle => 'データをインポート';

  @override
  String get dataTransferImportSubtitle => 'ZIP バックアップを選択してすぐに復元します。';

  @override
  String get dataTransferPreparing => 'データを準備中…';

  @override
  String get dataTransferDuplicateProgress => '重複する女優の選択を待っています…';

  @override
  String get dataTransferWriting => 'データと画像を書き込み中…';

  @override
  String get dataTransferExportSuccess => 'エクスポートが完了しました。';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return 'エクスポート完了。使用できない画像を $count 枚スキップしました。';
  }

  @override
  String get dataTransferImportSuccess => 'インポートが完了しました。データをすぐに使用できます。';

  @override
  String get dataTransferDuplicateTitle => '重複する女優が見つかりました';

  @override
  String get dataTransferDuplicateExplanation =>
      '画像と作品数を比較して、使用する女優の詳細情報を選択してください。既存の作品と関連付けは保持されます。';

  @override
  String get dataTransferKeepExisting => '現在の詳細を保持';

  @override
  String get dataTransferUseImported => 'インポートした詳細を使用';

  @override
  String get dataTransferContinue => '続行';

  @override
  String dataTransferWorkCount(int count) {
    return '作品数: $count';
  }

  @override
  String get dataTransferArchiveTooLarge => 'ZIP が対応サイズを超えています。';

  @override
  String get dataTransferUnsafeArchive => 'ZIP に安全でないファイルパスが含まれています。';

  @override
  String get dataTransferCorruptArchive => 'ZIP が壊れているか、画像のチェックサムに失敗しました。';

  @override
  String get dataTransferFileUnreadable => '選択したファイルを読み取れませんでした。';

  @override
  String get dataTransferActorNameConflict => 'インポートした女優名が別のデータと競合しています。';

  @override
  String get dataTransferBusy => '別のデータ転送が進行中です。';

  @override
  String get dataTransferFailed => 'データ転送に失敗しました。既存データは変更されていません。';

  @override
  String get otherSettings => 'その他';

  @override
  String get scrapeSources => '取得元';

  @override
  String get softwareUpdate => 'ソフトウェア更新';

  @override
  String get softwareUpdateDescription => 'AVACA の最新バージョンを確認してインストールします。';

  @override
  String get currentVersion => '現在のバージョン';

  @override
  String get latestVersion => '最新バージョン';

  @override
  String get autoCheckUpdates => '更新を自動的に確認';

  @override
  String get checkForUpdates => '更新を確認';

  @override
  String get checkingForUpdates => '更新を確認中…';

  @override
  String get downloadingUpdate => '更新をダウンロード中…';

  @override
  String get verifyingUpdate => '更新を検証中…';

  @override
  String get installingUpdate => 'インストールを開始中…';

  @override
  String get updateAvailable => '新しいバージョンがあります';

  @override
  String get upToDate => 'AVACA は最新です。';

  @override
  String get updateNow => '今すぐ更新';

  @override
  String get updateLater => '後で';

  @override
  String get updateUnavailable => 'このデバイスに対応する更新ファイルがありません。';

  @override
  String get updateCheckFailed => '更新を確認できませんでした。後でもう一度お試しください。';

  @override
  String get updateDownloadFailed => '更新のダウンロードに失敗しました。既存データは変更されていません。';

  @override
  String get updateIntegrityFailed => '更新ファイルの検証に失敗したため、更新を停止しました。';

  @override
  String get updateNotSupported => 'このデバイスでは自動更新に対応していません。';

  @override
  String get updateInstallPermissionRequired =>
      '先に AVACA に提供元不明のアプリのインストールを許可してください。';

  @override
  String get updatePortableFolderNotWritable =>
      'portable アプリフォルダーに書き込めないため、更新を停止しました。';

  @override
  String get updateInstallerFailed => '更新プログラムを開始できませんでした。現在のバージョンを保持しています。';

  @override
  String get updateDataPreserved => 'データと設定は保持されます。';
}
