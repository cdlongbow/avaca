import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh', 'TW'),
    Locale('zh', 'CN'),
    Locale('ja', 'JP'),
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @addTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'新增收藏'**
  String get addTitle;

  /// No description provided for @noPhoto.
  ///
  /// In zh_TW, this message translates to:
  /// **'尚無照片'**
  String get noPhoto;

  /// No description provided for @selectPhoto.
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇照片'**
  String get selectPhoto;

  /// No description provided for @removePhoto.
  ///
  /// In zh_TW, this message translates to:
  /// **'移除照片'**
  String get removePhoto;

  /// No description provided for @actressNameRequired.
  ///
  /// In zh_TW, this message translates to:
  /// **'女優姓名 (必填)'**
  String get actressNameRequired;

  /// No description provided for @saveCard.
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存卡片'**
  String get saveCard;

  /// No description provided for @changePhoto.
  ///
  /// In zh_TW, this message translates to:
  /// **'更換照片'**
  String get changePhoto;

  /// No description provided for @deletePhoto.
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除照片'**
  String get deletePhoto;

  /// No description provided for @noAttributesSet.
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未設定屬性'**
  String get noAttributesSet;

  /// No description provided for @bodyInfo.
  ///
  /// In zh_TW, this message translates to:
  /// **'詳細資料'**
  String get bodyInfo;

  /// No description provided for @heightCm.
  ///
  /// In zh_TW, this message translates to:
  /// **'身高 (cm)'**
  String get heightCm;

  /// No description provided for @weightKg.
  ///
  /// In zh_TW, this message translates to:
  /// **'體重 (kg)'**
  String get weightKg;

  /// No description provided for @cup.
  ///
  /// In zh_TW, this message translates to:
  /// **'罩杯'**
  String get cup;

  /// No description provided for @measurements.
  ///
  /// In zh_TW, this message translates to:
  /// **'三圍'**
  String get measurements;

  /// No description provided for @privateNotes.
  ///
  /// In zh_TW, this message translates to:
  /// **'私人筆記'**
  String get privateNotes;

  /// No description provided for @noNotes.
  ///
  /// In zh_TW, this message translates to:
  /// **'尚無筆記'**
  String get noNotes;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'確認刪除？'**
  String get confirmDeleteTitle;

  /// No description provided for @deleteWarningWithPhoto.
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除後將無法復原，連同照片檔案也會被清除。'**
  String get deleteWarningWithPhoto;

  /// No description provided for @cancel.
  ///
  /// In zh_TW, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirmDelete.
  ///
  /// In zh_TW, this message translates to:
  /// **'確定刪除'**
  String get confirmDelete;

  /// No description provided for @appTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'AVACA'**
  String get appTitle;

  /// No description provided for @search.
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋'**
  String get search;

  /// No description provided for @filterAndSort.
  ///
  /// In zh_TW, this message translates to:
  /// **'篩選與排序'**
  String get filterAndSort;

  /// No description provided for @filterSection.
  ///
  /// In zh_TW, this message translates to:
  /// **'篩選'**
  String get filterSection;

  /// No description provided for @sortSection.
  ///
  /// In zh_TW, this message translates to:
  /// **'排序'**
  String get sortSection;

  /// No description provided for @sortCreatedDesc.
  ///
  /// In zh_TW, this message translates to:
  /// **'新增時間（新到舊）'**
  String get sortCreatedDesc;

  /// No description provided for @sortCreatedAsc.
  ///
  /// In zh_TW, this message translates to:
  /// **'新增時間（舊到新）'**
  String get sortCreatedAsc;

  /// No description provided for @sortModifiedDesc.
  ///
  /// In zh_TW, this message translates to:
  /// **'修改時間（新到舊）'**
  String get sortModifiedDesc;

  /// No description provided for @sortModifiedAsc.
  ///
  /// In zh_TW, this message translates to:
  /// **'修改時間（舊到新）'**
  String get sortModifiedAsc;

  /// No description provided for @sortAgeAsc.
  ///
  /// In zh_TW, this message translates to:
  /// **'年齡（低到高）'**
  String get sortAgeAsc;

  /// No description provided for @sortAgeDesc.
  ///
  /// In zh_TW, this message translates to:
  /// **'年齡（高到低）'**
  String get sortAgeDesc;

  /// No description provided for @birthDate.
  ///
  /// In zh_TW, this message translates to:
  /// **'生日'**
  String get birthDate;

  /// No description provided for @setBirthDate.
  ///
  /// In zh_TW, this message translates to:
  /// **'設定生日'**
  String get setBirthDate;

  /// No description provided for @clear.
  ///
  /// In zh_TW, this message translates to:
  /// **'清除'**
  String get clear;

  /// No description provided for @done.
  ///
  /// In zh_TW, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @ageWithBirthDate.
  ///
  /// In zh_TW, this message translates to:
  /// **'{age}歲  {date}'**
  String ageWithBirthDate(int age, String date);

  /// No description provided for @add.
  ///
  /// In zh_TW, this message translates to:
  /// **'新增'**
  String get add;

  /// No description provided for @settings.
  ///
  /// In zh_TW, this message translates to:
  /// **'設定'**
  String get settings;

  /// No description provided for @themeAndColors.
  ///
  /// In zh_TW, this message translates to:
  /// **'主題與色彩'**
  String get themeAndColors;

  /// No description provided for @interfaceSettings.
  ///
  /// In zh_TW, this message translates to:
  /// **'介面'**
  String get interfaceSettings;

  /// No description provided for @loadFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'載入失敗：{error}'**
  String loadFailed(String error);

  /// No description provided for @noData.
  ///
  /// In zh_TW, this message translates to:
  /// **'尚無資料'**
  String get noData;

  /// No description provided for @searchNameHint.
  ///
  /// In zh_TW, this message translates to:
  /// **'輸入名稱快速搜尋...'**
  String get searchNameHint;

  /// No description provided for @applySettings.
  ///
  /// In zh_TW, this message translates to:
  /// **'套用設定'**
  String get applySettings;

  /// No description provided for @themeMode.
  ///
  /// In zh_TW, this message translates to:
  /// **'主題模式'**
  String get themeMode;

  /// No description provided for @followSystem.
  ///
  /// In zh_TW, this message translates to:
  /// **'跟隨系統'**
  String get followSystem;

  /// No description provided for @lightTheme.
  ///
  /// In zh_TW, this message translates to:
  /// **'淺色'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In zh_TW, this message translates to:
  /// **'深色'**
  String get darkTheme;

  /// No description provided for @customTheme.
  ///
  /// In zh_TW, this message translates to:
  /// **'自訂主題'**
  String get customTheme;

  /// No description provided for @pureBlackAmoled.
  ///
  /// In zh_TW, this message translates to:
  /// **'純黑 AMOLED'**
  String get pureBlackAmoled;

  /// No description provided for @pureBlackOnlyDark.
  ///
  /// In zh_TW, this message translates to:
  /// **'僅深色主題有效'**
  String get pureBlackOnlyDark;

  /// No description provided for @colorSurface.
  ///
  /// In zh_TW, this message translates to:
  /// **'背景'**
  String get colorSurface;

  /// No description provided for @colorSurfaceContainer.
  ///
  /// In zh_TW, this message translates to:
  /// **'卡片背景'**
  String get colorSurfaceContainer;

  /// No description provided for @colorOnSurface.
  ///
  /// In zh_TW, this message translates to:
  /// **'主要文字'**
  String get colorOnSurface;

  /// No description provided for @colorOnSurfaceVariant.
  ///
  /// In zh_TW, this message translates to:
  /// **'次要文字'**
  String get colorOnSurfaceVariant;

  /// No description provided for @colorPrimary.
  ///
  /// In zh_TW, this message translates to:
  /// **'互動主色'**
  String get colorPrimary;

  /// No description provided for @colorOnPrimary.
  ///
  /// In zh_TW, this message translates to:
  /// **'主色文字'**
  String get colorOnPrimary;

  /// No description provided for @colorOutline.
  ///
  /// In zh_TW, this message translates to:
  /// **'邊框 / 分隔線'**
  String get colorOutline;

  /// No description provided for @adjustColorTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'調整 {colorLabel}'**
  String adjustColorTitle(String colorLabel);

  /// No description provided for @apply.
  ///
  /// In zh_TW, this message translates to:
  /// **'套用'**
  String get apply;

  /// No description provided for @imageReadFailedUnsupportedFormat.
  ///
  /// In zh_TW, this message translates to:
  /// **'圖片讀取失敗，可能格式不支援'**
  String get imageReadFailedUnsupportedFormat;

  /// No description provided for @enterName.
  ///
  /// In zh_TW, this message translates to:
  /// **'請輸入姓名'**
  String get enterName;

  /// No description provided for @collectionAdded.
  ///
  /// In zh_TW, this message translates to:
  /// **'收藏成功'**
  String get collectionAdded;

  /// No description provided for @alreadyInCollection.
  ///
  /// In zh_TW, this message translates to:
  /// **'已經在收藏庫中'**
  String get alreadyInCollection;

  /// No description provided for @dataDeleted.
  ///
  /// In zh_TW, this message translates to:
  /// **'資料已徹底刪除'**
  String get dataDeleted;

  /// No description provided for @deleteFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除失敗'**
  String get deleteFailed;

  /// No description provided for @photoCroppedRememberSave.
  ///
  /// In zh_TW, this message translates to:
  /// **'照片裁切完成，請記得按下儲存！'**
  String get photoCroppedRememberSave;

  /// No description provided for @detailSaved.
  ///
  /// In zh_TW, this message translates to:
  /// **'詳細資料已儲存！'**
  String get detailSaved;

  /// No description provided for @saveFailedDuplicateName.
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存失敗，可能是姓名與他人重複'**
  String get saveFailedDuplicateName;

  /// No description provided for @dataNotFound.
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到資料'**
  String get dataNotFound;

  /// No description provided for @attrCensored.
  ///
  /// In zh_TW, this message translates to:
  /// **'有碼'**
  String get attrCensored;

  /// No description provided for @attrUncensored.
  ///
  /// In zh_TW, this message translates to:
  /// **'無碼'**
  String get attrUncensored;

  /// No description provided for @attrWestern.
  ///
  /// In zh_TW, this message translates to:
  /// **'歐美'**
  String get attrWestern;

  /// No description provided for @attrFc2.
  ///
  /// In zh_TW, this message translates to:
  /// **'FC2'**
  String get attrFc2;

  /// No description provided for @attrDomestic.
  ///
  /// In zh_TW, this message translates to:
  /// **'國產'**
  String get attrDomestic;

  /// No description provided for @filterAll.
  ///
  /// In zh_TW, this message translates to:
  /// **'全部'**
  String get filterAll;

  /// No description provided for @imageCropLoadErrorTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'圖片讀取錯誤'**
  String get imageCropLoadErrorTitle;

  /// No description provided for @close.
  ///
  /// In zh_TW, this message translates to:
  /// **'關閉'**
  String get close;

  /// No description provided for @imageDecodeFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'圖片解碼失敗'**
  String get imageDecodeFailed;

  /// No description provided for @cropZoom.
  ///
  /// In zh_TW, this message translates to:
  /// **'放大縮小'**
  String get cropZoom;

  /// No description provided for @cropPanX.
  ///
  /// In zh_TW, this message translates to:
  /// **'左右平移'**
  String get cropPanX;

  /// No description provided for @cropPanY.
  ///
  /// In zh_TW, this message translates to:
  /// **'上下平移'**
  String get cropPanY;

  /// No description provided for @confirmCrop.
  ///
  /// In zh_TW, this message translates to:
  /// **'確定裁切'**
  String get confirmCrop;

  /// No description provided for @language.
  ///
  /// In zh_TW, this message translates to:
  /// **'語言'**
  String get language;

  /// No description provided for @traditionalChineseTaiwan.
  ///
  /// In zh_TW, this message translates to:
  /// **'繁體中文（台灣）'**
  String get traditionalChineseTaiwan;

  /// No description provided for @english.
  ///
  /// In zh_TW, this message translates to:
  /// **'英文'**
  String get english;

  /// No description provided for @simplifiedChinese.
  ///
  /// In zh_TW, this message translates to:
  /// **'簡體中文'**
  String get simplifiedChinese;

  /// No description provided for @japanese.
  ///
  /// In zh_TW, this message translates to:
  /// **'日文'**
  String get japanese;

  /// No description provided for @works.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品'**
  String get works;

  /// No description provided for @loadFailedGeneric.
  ///
  /// In zh_TW, this message translates to:
  /// **'載入失敗'**
  String get loadFailedGeneric;

  /// No description provided for @actressWorksTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'{actressName}演出的作品'**
  String actressWorksTitle(String actressName);

  /// No description provided for @scrapeWorks.
  ///
  /// In zh_TW, this message translates to:
  /// **'刮削作品'**
  String get scrapeWorks;

  /// No description provided for @scrapeSettings.
  ///
  /// In zh_TW, this message translates to:
  /// **'刮削設定'**
  String get scrapeSettings;

  /// No description provided for @syncActressDetails.
  ///
  /// In zh_TW, this message translates to:
  /// **'同步詳細資料'**
  String get syncActressDetails;

  /// No description provided for @replaceActressImage.
  ///
  /// In zh_TW, this message translates to:
  /// **'更換女優頭像'**
  String get replaceActressImage;

  /// No description provided for @maxActressCountLabel.
  ///
  /// In zh_TW, this message translates to:
  /// **'多於此數量的女優不刮削'**
  String get maxActressCountLabel;

  /// No description provided for @maxActressCountHint.
  ///
  /// In zh_TW, this message translates to:
  /// **'留空表示不限制'**
  String get maxActressCountHint;

  /// No description provided for @maxActressCountInvalid.
  ///
  /// In zh_TW, this message translates to:
  /// **'請輸入大於等於 1 的整數'**
  String get maxActressCountInvalid;

  /// No description provided for @scrapeAvatarUnavailable.
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到可用的女優頭像。'**
  String get scrapeAvatarUnavailable;

  /// No description provided for @scrapeAvatarFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'女優頭像替換失敗，已保留原頭像。'**
  String get scrapeAvatarFailed;

  /// No description provided for @fillMissingOnly.
  ///
  /// In zh_TW, this message translates to:
  /// **'二次刮削只補齊缺少的資訊'**
  String get fillMissingOnly;

  /// No description provided for @excludedCodePrefixes.
  ///
  /// In zh_TW, this message translates to:
  /// **'不刮削的番號開頭'**
  String get excludedCodePrefixes;

  /// No description provided for @codePrefixHint.
  ///
  /// In zh_TW, this message translates to:
  /// **'輸入番號前綴'**
  String get codePrefixHint;

  /// No description provided for @addPrefix.
  ///
  /// In zh_TW, this message translates to:
  /// **'新增'**
  String get addPrefix;

  /// No description provided for @startScrape.
  ///
  /// In zh_TW, this message translates to:
  /// **'開始刮削'**
  String get startScrape;

  /// No description provided for @noWorks.
  ///
  /// In zh_TW, this message translates to:
  /// **'尚無作品'**
  String get noWorks;

  /// No description provided for @durationMinutes.
  ///
  /// In zh_TW, this message translates to:
  /// **'{minutes} 分鐘'**
  String durationMinutes(int minutes);

  /// No description provided for @studio.
  ///
  /// In zh_TW, this message translates to:
  /// **'製作商'**
  String get studio;

  /// No description provided for @publisher.
  ///
  /// In zh_TW, this message translates to:
  /// **'發行商'**
  String get publisher;

  /// No description provided for @series.
  ///
  /// In zh_TW, this message translates to:
  /// **'系列'**
  String get series;

  /// No description provided for @scrapeComplete.
  ///
  /// In zh_TW, this message translates to:
  /// **'刮削完成：儲存 {saved}、排除 {excluded}、失敗 {failed}'**
  String scrapeComplete(int saved, int excluded, int failed);

  /// No description provided for @scrapeCancelled.
  ///
  /// In zh_TW, this message translates to:
  /// **'已取消刮削：儲存 {saved}、排除 {excluded}、失敗 {failed}'**
  String scrapeCancelled(int saved, int excluded, int failed);

  /// No description provided for @scrapeFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'刮削失敗，請稍後再試。'**
  String get scrapeFailed;

  /// No description provided for @javBusVerificationTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'JavBus 驗證'**
  String get javBusVerificationTitle;

  /// No description provided for @javBusVerificationInstructions.
  ///
  /// In zh_TW, this message translates to:
  /// **'JavBus 要求手動完成地區成年驗證。請回答所有題目，App 會在同一安全工作階段繼續刮削。'**
  String get javBusVerificationInstructions;

  /// No description provided for @javBusVerificationSubmit.
  ///
  /// In zh_TW, this message translates to:
  /// **'送出驗證'**
  String get javBusVerificationSubmit;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'ja':
      {
        switch (locale.countryCode) {
          case 'JP':
            return AppLocalizationsJaJp();
        }
        break;
      }
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'CN':
            return AppLocalizationsZhCn();
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
