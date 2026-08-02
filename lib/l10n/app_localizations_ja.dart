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
  String get loadFailedGeneric => '読み込みに失敗しました';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressNameの出演作品';
  }

  @override
  String get scrapeWorks => '作品情報を取得';

  @override
  String get scrapeSettings => '取得設定';

  @override
  String get syncActressDetails => 'プロフィール詳細を同期';

  @override
  String get replaceActressImage => '女優画像を差し替える';

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
  String get loadFailedGeneric => '読み込みに失敗しました';

  @override
  String actressWorksTitle(String actressName) {
    return '$actressNameの出演作品';
  }

  @override
  String get scrapeWorks => '作品情報を取得';

  @override
  String get scrapeSettings => '取得設定';

  @override
  String get syncActressDetails => 'プロフィール詳細を同期';

  @override
  String get replaceActressImage => '女優画像を差し替える';

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
}
