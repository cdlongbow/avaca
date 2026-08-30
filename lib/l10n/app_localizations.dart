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

  /// No description provided for @reload.
  ///
  /// In zh_TW, this message translates to:
  /// **'重新載入'**
  String get reload;

  /// No description provided for @confirmDelete.
  ///
  /// In zh_TW, this message translates to:
  /// **'確定刪除'**
  String get confirmDelete;

  /// No description provided for @edit.
  ///
  /// In zh_TW, this message translates to:
  /// **'編輯'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除'**
  String get delete;

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

  /// No description provided for @colorSnackbarBackground.
  ///
  /// In zh_TW, this message translates to:
  /// **'提示訊息背景'**
  String get colorSnackbarBackground;

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

  /// No description provided for @worksPageSize.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品頁大小'**
  String get worksPageSize;

  /// No description provided for @worksPageSizeSmall.
  ///
  /// In zh_TW, this message translates to:
  /// **'小'**
  String get worksPageSizeSmall;

  /// No description provided for @worksPageSizeLarge.
  ///
  /// In zh_TW, this message translates to:
  /// **'大'**
  String get worksPageSizeLarge;

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

  /// No description provided for @relatedActresses.
  ///
  /// In zh_TW, this message translates to:
  /// **'關聯演員'**
  String get relatedActresses;

  /// No description provided for @workStorageTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品儲存記錄'**
  String get workStorageTitle;

  /// No description provided for @workStorageSaved.
  ///
  /// In zh_TW, this message translates to:
  /// **'已儲存'**
  String get workStorageSaved;

  /// No description provided for @workStorageNotSaved.
  ///
  /// In zh_TW, this message translates to:
  /// **'未儲存'**
  String get workStorageNotSaved;

  /// No description provided for @workStorageQuality.
  ///
  /// In zh_TW, this message translates to:
  /// **'畫質'**
  String get workStorageQuality;

  /// No description provided for @workStorageFrameRate.
  ///
  /// In zh_TW, this message translates to:
  /// **'幀率'**
  String get workStorageFrameRate;

  /// No description provided for @workStorageSave.
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存'**
  String get workStorageSave;

  /// No description provided for @workStorageUpdated.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品儲存記錄已更新'**
  String get workStorageUpdated;

  /// No description provided for @workStorageUpdateFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品儲存記錄更新失敗'**
  String get workStorageUpdateFailed;

  /// No description provided for @workStorageFilterStored.
  ///
  /// In zh_TW, this message translates to:
  /// **'已儲存'**
  String get workStorageFilterStored;

  /// No description provided for @workStorageFilterNotStored.
  ///
  /// In zh_TW, this message translates to:
  /// **'未儲存'**
  String get workStorageFilterNotStored;

  /// No description provided for @workStorageFilterAll.
  ///
  /// In zh_TW, this message translates to:
  /// **'全部'**
  String get workStorageFilterAll;

  /// No description provided for @aliases.
  ///
  /// In zh_TW, this message translates to:
  /// **'別名'**
  String get aliases;

  /// No description provided for @manageAliases.
  ///
  /// In zh_TW, this message translates to:
  /// **'管理別名'**
  String get manageAliases;

  /// No description provided for @aliasInputHint.
  ///
  /// In zh_TW, this message translates to:
  /// **'輸入其他名稱'**
  String get aliasInputHint;

  /// No description provided for @addAlias.
  ///
  /// In zh_TW, this message translates to:
  /// **'新增別名'**
  String get addAlias;

  /// No description provided for @saveAliases.
  ///
  /// In zh_TW, this message translates to:
  /// **'儲存別名'**
  String get saveAliases;

  /// No description provided for @noAliases.
  ///
  /// In zh_TW, this message translates to:
  /// **'尚無別名'**
  String get noAliases;

  /// No description provided for @deleteWorks.
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除作品'**
  String get deleteWorks;

  /// No description provided for @deleteWorksTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'刪除選取的作品？'**
  String get deleteWorksTitle;

  /// No description provided for @deleteWorksWarning.
  ///
  /// In zh_TW, this message translates to:
  /// **'選取的作品會從資料庫中全域移除，也會移除其他女優的作品連結。'**
  String get deleteWorksWarning;

  /// No description provided for @worksDeleted.
  ///
  /// In zh_TW, this message translates to:
  /// **'已刪除 {count} 部作品'**
  String worksDeleted(int count);

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

  /// No description provided for @searchWorks.
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋作品'**
  String get searchWorks;

  /// No description provided for @workCodeSearchHint.
  ///
  /// In zh_TW, this message translates to:
  /// **'輸入番號搜尋...'**
  String get workCodeSearchHint;

  /// No description provided for @noMatchingWorks.
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到符合的作品'**
  String get noMatchingWorks;

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

  /// No description provided for @settingsDataTransferTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'資料匯入與匯出'**
  String get settingsDataTransferTitle;

  /// No description provided for @settingsDataTransferSubtitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'以 ZIP 備份或還原演員、作品、詳細資料與圖片。'**
  String get settingsDataTransferSubtitle;

  /// No description provided for @dataTransferExportTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯出資料'**
  String get dataTransferExportTitle;

  /// No description provided for @dataTransferExportSubtitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇位置儲存完整 ZIP 備份。'**
  String get dataTransferExportSubtitle;

  /// No description provided for @dataTransferImportTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入資料'**
  String get dataTransferImportTitle;

  /// No description provided for @dataTransferImportSubtitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇 ZIP 備份並直接還原到目前資料庫。'**
  String get dataTransferImportSubtitle;

  /// No description provided for @dataTransferPreparing.
  ///
  /// In zh_TW, this message translates to:
  /// **'準備資料中…'**
  String get dataTransferPreparing;

  /// No description provided for @dataTransferDuplicateProgress.
  ///
  /// In zh_TW, this message translates to:
  /// **'等待重複演員選擇…'**
  String get dataTransferDuplicateProgress;

  /// No description provided for @dataTransferWriting.
  ///
  /// In zh_TW, this message translates to:
  /// **'寫入資料與圖片中…'**
  String get dataTransferWriting;

  /// No description provided for @dataTransferExportSuccess.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯出完成。'**
  String get dataTransferExportSuccess;

  /// No description provided for @dataTransferExportSuccessWithSkippedImages.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯出完成，略過 {count} 張無法使用的圖片。'**
  String dataTransferExportSuccessWithSkippedImages(int count);

  /// No description provided for @dataTransferImportSuccess.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入完成，資料已可直接使用。'**
  String get dataTransferImportSuccess;

  /// No description provided for @dataTransferDuplicateTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'發現重複演員'**
  String get dataTransferDuplicateTitle;

  /// No description provided for @dataTransferDuplicateExplanation.
  ///
  /// In zh_TW, this message translates to:
  /// **'請比較頭像與作品數，選擇要採用哪一份演員詳細資料。既有作品與關聯會保留。'**
  String get dataTransferDuplicateExplanation;

  /// No description provided for @dataTransferKeepExisting.
  ///
  /// In zh_TW, this message translates to:
  /// **'保留目前資料'**
  String get dataTransferKeepExisting;

  /// No description provided for @dataTransferUseImported.
  ///
  /// In zh_TW, this message translates to:
  /// **'使用匯入資料'**
  String get dataTransferUseImported;

  /// No description provided for @dataTransferContinue.
  ///
  /// In zh_TW, this message translates to:
  /// **'繼續'**
  String get dataTransferContinue;

  /// No description provided for @dataTransferWorkCount.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品數：{count}'**
  String dataTransferWorkCount(int count);

  /// No description provided for @dataTransferArchiveTooLarge.
  ///
  /// In zh_TW, this message translates to:
  /// **'ZIP 檔案超過可支援的大小。'**
  String get dataTransferArchiveTooLarge;

  /// No description provided for @dataTransferUnsafeArchive.
  ///
  /// In zh_TW, this message translates to:
  /// **'ZIP 含有不安全的檔案路徑。'**
  String get dataTransferUnsafeArchive;

  /// No description provided for @dataTransferCorruptArchive.
  ///
  /// In zh_TW, this message translates to:
  /// **'ZIP 檔案損毀或圖片校驗失敗。'**
  String get dataTransferCorruptArchive;

  /// No description provided for @dataTransferFileUnreadable.
  ///
  /// In zh_TW, this message translates to:
  /// **'無法讀取所選檔案。'**
  String get dataTransferFileUnreadable;

  /// No description provided for @dataTransferActorNameConflict.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入演員名稱與其他資料衝突。'**
  String get dataTransferActorNameConflict;

  /// No description provided for @dataTransferBusy.
  ///
  /// In zh_TW, this message translates to:
  /// **'已有另一個資料傳輸作業正在進行。'**
  String get dataTransferBusy;

  /// No description provided for @dataTransferFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'資料傳輸失敗，未變更既有資料。'**
  String get dataTransferFailed;

  /// No description provided for @otherSettings.
  ///
  /// In zh_TW, this message translates to:
  /// **'其他'**
  String get otherSettings;

  /// No description provided for @about.
  ///
  /// In zh_TW, this message translates to:
  /// **'關於'**
  String get about;

  /// No description provided for @github.
  ///
  /// In zh_TW, this message translates to:
  /// **'github'**
  String get github;

  /// No description provided for @feedbackSuggestions.
  ///
  /// In zh_TW, this message translates to:
  /// **'回饋建議'**
  String get feedbackSuggestions;

  /// No description provided for @softwareUpdate.
  ///
  /// In zh_TW, this message translates to:
  /// **'軟體更新'**
  String get softwareUpdate;

  /// No description provided for @softwareUpdateDescription.
  ///
  /// In zh_TW, this message translates to:
  /// **'檢查並安裝 AVACA 的最新版本。'**
  String get softwareUpdateDescription;

  /// No description provided for @currentVersion.
  ///
  /// In zh_TW, this message translates to:
  /// **'目前版本'**
  String get currentVersion;

  /// No description provided for @latestVersion.
  ///
  /// In zh_TW, this message translates to:
  /// **'最新版本'**
  String get latestVersion;

  /// No description provided for @autoCheckUpdates.
  ///
  /// In zh_TW, this message translates to:
  /// **'自動檢查更新'**
  String get autoCheckUpdates;

  /// No description provided for @checkForUpdates.
  ///
  /// In zh_TW, this message translates to:
  /// **'檢查更新'**
  String get checkForUpdates;

  /// No description provided for @checkingForUpdates.
  ///
  /// In zh_TW, this message translates to:
  /// **'正在檢查更新…'**
  String get checkingForUpdates;

  /// No description provided for @downloadingUpdate.
  ///
  /// In zh_TW, this message translates to:
  /// **'正在下載更新…'**
  String get downloadingUpdate;

  /// No description provided for @verifyingUpdate.
  ///
  /// In zh_TW, this message translates to:
  /// **'正在驗證更新…'**
  String get verifyingUpdate;

  /// No description provided for @installingUpdate.
  ///
  /// In zh_TW, this message translates to:
  /// **'正在啟動安裝…'**
  String get installingUpdate;

  /// No description provided for @updateAvailable.
  ///
  /// In zh_TW, this message translates to:
  /// **'有新版本可用'**
  String get updateAvailable;

  /// No description provided for @upToDate.
  ///
  /// In zh_TW, this message translates to:
  /// **'目前已是最新版本。'**
  String get upToDate;

  /// No description provided for @updateNow.
  ///
  /// In zh_TW, this message translates to:
  /// **'立即更新'**
  String get updateNow;

  /// No description provided for @updateLater.
  ///
  /// In zh_TW, this message translates to:
  /// **'稍後'**
  String get updateLater;

  /// No description provided for @updateUnavailable.
  ///
  /// In zh_TW, this message translates to:
  /// **'此版本沒有此裝置的更新檔。'**
  String get updateUnavailable;

  /// No description provided for @updateCheckFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'檢查更新失敗，請稍後再試。'**
  String get updateCheckFailed;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'更新下載失敗，原有資料未變更。'**
  String get updateDownloadFailed;

  /// No description provided for @updateIntegrityFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'更新檔驗證失敗，已停止更新。'**
  String get updateIntegrityFailed;

  /// No description provided for @updateNotSupported.
  ///
  /// In zh_TW, this message translates to:
  /// **'此裝置不支援自動更新。'**
  String get updateNotSupported;

  /// No description provided for @updateInstallPermissionRequired.
  ///
  /// In zh_TW, this message translates to:
  /// **'請先允許 AVACA 安裝未知來源的應用程式。'**
  String get updateInstallPermissionRequired;

  /// No description provided for @updatePortableFolderNotWritable.
  ///
  /// In zh_TW, this message translates to:
  /// **'portable 程式資料夾無法寫入，已停止更新。'**
  String get updatePortableFolderNotWritable;

  /// No description provided for @updateInstallerFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'更新程式無法啟動，原有版本仍保留。'**
  String get updateInstallerFailed;

  /// No description provided for @updateDataPreserved.
  ///
  /// In zh_TW, this message translates to:
  /// **'使用者資料與設定會保留。'**
  String get updateDataPreserved;

  /// No description provided for @prefixRouteRulesTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品圖片 Prefix 路由規則'**
  String get prefixRouteRulesTitle;

  /// No description provided for @prefixRouteRulesSubtitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'查看並管理由實際驗證下載結果學習的圖片 family。'**
  String get prefixRouteRulesSubtitle;

  /// No description provided for @prefixRouteRuleCount.
  ///
  /// In zh_TW, this message translates to:
  /// **'已學習 {count} 條 Prefix 規則'**
  String prefixRouteRuleCount(int count);

  /// No description provided for @prefixRouteSearchHint.
  ///
  /// In zh_TW, this message translates to:
  /// **'搜尋 Prefix'**
  String get prefixRouteSearchHint;

  /// No description provided for @prefixRouteNoRules.
  ///
  /// In zh_TW, this message translates to:
  /// **'尚未學習任何 Prefix 路由規則。'**
  String get prefixRouteNoRules;

  /// No description provided for @prefixRouteNoSearchResults.
  ///
  /// In zh_TW, this message translates to:
  /// **'沒有符合搜尋條件的 Prefix 規則。'**
  String get prefixRouteNoSearchResults;

  /// No description provided for @prefixRouteBestFamily.
  ///
  /// In zh_TW, this message translates to:
  /// **'目前優先 family'**
  String get prefixRouteBestFamily;

  /// No description provided for @prefixRouteNotAvailable.
  ///
  /// In zh_TW, this message translates to:
  /// **'無'**
  String get prefixRouteNotAvailable;

  /// No description provided for @prefixRouteCandidates.
  ///
  /// In zh_TW, this message translates to:
  /// **'已知候選路由'**
  String get prefixRouteCandidates;

  /// No description provided for @prefixRouteSuccessCount.
  ///
  /// In zh_TW, this message translates to:
  /// **'成功：{count} 次'**
  String prefixRouteSuccessCount(int count);

  /// No description provided for @prefixRouteFailureCount.
  ///
  /// In zh_TW, this message translates to:
  /// **'失敗：{count} 次'**
  String prefixRouteFailureCount(int count);

  /// No description provided for @prefixRouteLastSuccess.
  ///
  /// In zh_TW, this message translates to:
  /// **'最後成功：{time}'**
  String prefixRouteLastSuccess(String time);

  /// No description provided for @prefixRouteLastFailure.
  ///
  /// In zh_TW, this message translates to:
  /// **'最後失敗：{time}'**
  String prefixRouteLastFailure(String time);

  /// No description provided for @prefixRouteStatusVerified.
  ///
  /// In zh_TW, this message translates to:
  /// **'已驗證'**
  String get prefixRouteStatusVerified;

  /// No description provided for @prefixRouteStatusExceptions.
  ///
  /// In zh_TW, this message translates to:
  /// **'有例外'**
  String get prefixRouteStatusExceptions;

  /// No description provided for @prefixRouteStatusPending.
  ///
  /// In zh_TW, this message translates to:
  /// **'待重新驗證'**
  String get prefixRouteStatusPending;

  /// No description provided for @prefixRouteStatusProbeFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'探測失敗'**
  String get prefixRouteStatusProbeFailed;

  /// No description provided for @prefixRouteManualOverride.
  ///
  /// In zh_TW, this message translates to:
  /// **'手動指定 route'**
  String get prefixRouteManualOverride;

  /// No description provided for @prefixRouteAutomatic.
  ///
  /// In zh_TW, this message translates to:
  /// **'自動'**
  String get prefixRouteAutomatic;

  /// No description provided for @prefixRouteAutomaticDescription.
  ///
  /// In zh_TW, this message translates to:
  /// **'優先使用已學習候選，必要時再探測目前支援的 family。'**
  String get prefixRouteAutomaticDescription;

  /// No description provided for @prefixRouteManualDescription.
  ///
  /// In zh_TW, this message translates to:
  /// **'會優先嘗試此 family；原有學習統計仍會保留。'**
  String get prefixRouteManualDescription;

  /// No description provided for @prefixRouteFamilyDmmStandard.
  ///
  /// In zh_TW, this message translates to:
  /// **'DMM Standard'**
  String get prefixRouteFamilyDmmStandard;

  /// No description provided for @prefixRouteFamilyDmmLeadingOne.
  ///
  /// In zh_TW, this message translates to:
  /// **'DMM Leading One'**
  String get prefixRouteFamilyDmmLeadingOne;

  /// No description provided for @prefixRouteFamilyDmmH1711.
  ///
  /// In zh_TW, this message translates to:
  /// **'DMM H1711'**
  String get prefixRouteFamilyDmmH1711;

  /// No description provided for @prefixRouteFamilyDmmRebeccaH346.
  ///
  /// In zh_TW, this message translates to:
  /// **'DMM Rebecca H346'**
  String get prefixRouteFamilyDmmRebeccaH346;

  /// No description provided for @prefixRouteFamilyMgstagePrestige.
  ///
  /// In zh_TW, this message translates to:
  /// **'MGStage Prestige'**
  String get prefixRouteFamilyMgstagePrestige;

  /// No description provided for @prefixRouteFamilyMgstageSeikyouiku.
  ///
  /// In zh_TW, this message translates to:
  /// **'MGStage Seikyouiku'**
  String get prefixRouteFamilyMgstageSeikyouiku;

  /// No description provided for @prefixRouteExport.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯出規則'**
  String get prefixRouteExport;

  /// No description provided for @prefixRouteImport.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入規則'**
  String get prefixRouteImport;

  /// No description provided for @prefixRouteExportDialogTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯出 Prefix 規則'**
  String get prefixRouteExportDialogTitle;

  /// No description provided for @prefixRouteExportRulesOnly.
  ///
  /// In zh_TW, this message translates to:
  /// **'僅規則'**
  String get prefixRouteExportRulesOnly;

  /// No description provided for @prefixRouteExportRulesOnlyDescription.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯出 family，不包含驗證統計。'**
  String get prefixRouteExportRulesOnlyDescription;

  /// No description provided for @prefixRouteExportWithStatistics.
  ///
  /// In zh_TW, this message translates to:
  /// **'規則與統計'**
  String get prefixRouteExportWithStatistics;

  /// No description provided for @prefixRouteExportWithStatisticsDescription.
  ///
  /// In zh_TW, this message translates to:
  /// **'包含成功、失敗與時間資料。'**
  String get prefixRouteExportWithStatisticsDescription;

  /// No description provided for @prefixRouteExportSuccess.
  ///
  /// In zh_TW, this message translates to:
  /// **'Prefix 規則已匯出。'**
  String get prefixRouteExportSuccess;

  /// No description provided for @prefixRouteImportDialogTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入 Prefix 規則'**
  String get prefixRouteImportDialogTitle;

  /// No description provided for @prefixRouteImportPreview.
  ///
  /// In zh_TW, this message translates to:
  /// **'找到 {rules} 條規則。手動指定衝突：{conflicts}。'**
  String prefixRouteImportPreview(int rules, int conflicts);

  /// No description provided for @prefixRouteImportMerge.
  ///
  /// In zh_TW, this message translates to:
  /// **'合併'**
  String get prefixRouteImportMerge;

  /// No description provided for @prefixRouteImportReplace.
  ///
  /// In zh_TW, this message translates to:
  /// **'取代'**
  String get prefixRouteImportReplace;

  /// No description provided for @prefixRouteImportSuccess.
  ///
  /// In zh_TW, this message translates to:
  /// **'已匯入 {count} 條 Prefix 規則。'**
  String prefixRouteImportSuccess(int count);

  /// No description provided for @prefixRouteOperationFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'Prefix 路由操作失敗，既有規則未變更。'**
  String get prefixRouteOperationFailed;

  /// No description provided for @prefixRouteLoadFailed.
  ///
  /// In zh_TW, this message translates to:
  /// **'無法載入 Prefix 路由規則。'**
  String get prefixRouteLoadFailed;

  /// No description provided for @prefixRouteClearAutomatic.
  ///
  /// In zh_TW, this message translates to:
  /// **'清除自動學習'**
  String get prefixRouteClearAutomatic;

  /// No description provided for @prefixRouteClearAutomaticTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'清除自動學習？'**
  String get prefixRouteClearAutomaticTitle;

  /// No description provided for @prefixRouteClearAutomaticMessage.
  ///
  /// In zh_TW, this message translates to:
  /// **'將清除已學習候選與統計；手動指定與已下載圖片會保留。'**
  String get prefixRouteClearAutomaticMessage;

  /// No description provided for @prefixRouteClearAutomaticSuccess.
  ///
  /// In zh_TW, this message translates to:
  /// **'已清除 Prefix 自動學習資料。'**
  String get prefixRouteClearAutomaticSuccess;

  /// No description provided for @prefixRouteReset.
  ///
  /// In zh_TW, this message translates to:
  /// **'重設此 Prefix 學習'**
  String get prefixRouteReset;

  /// No description provided for @prefixRouteResetTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'重設此 Prefix 的學習資料？'**
  String get prefixRouteResetTitle;

  /// No description provided for @prefixRouteResetMessage.
  ///
  /// In zh_TW, this message translates to:
  /// **'將清除候選與統計；如果有手動指定 route，會保留。'**
  String get prefixRouteResetMessage;

  /// No description provided for @prefixRouteForget.
  ///
  /// In zh_TW, this message translates to:
  /// **'移除此 Prefix 規則'**
  String get prefixRouteForget;

  /// No description provided for @prefixRouteForgetTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'移除此 Prefix 規則？'**
  String get prefixRouteForgetTitle;

  /// No description provided for @prefixRouteForgetMessage.
  ///
  /// In zh_TW, this message translates to:
  /// **'將移除此 Prefix 的學習資料與手動指定；不會變更已下載圖片或作品資料。'**
  String get prefixRouteForgetMessage;

  /// No description provided for @workFieldProvenanceTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'欄位來源'**
  String get workFieldProvenanceTitle;

  /// No description provided for @workFieldProvenanceSource.
  ///
  /// In zh_TW, this message translates to:
  /// **'來源'**
  String get workFieldProvenanceSource;

  /// No description provided for @workFieldProvenanceObservedAt.
  ///
  /// In zh_TW, this message translates to:
  /// **'觀測時間'**
  String get workFieldProvenanceObservedAt;

  /// No description provided for @workFieldProvenanceUnknown.
  ///
  /// In zh_TW, this message translates to:
  /// **'未知來源'**
  String get workFieldProvenanceUnknown;

  /// No description provided for @dataHealthTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'資料健康度'**
  String get dataHealthTitle;

  /// No description provided for @dataHealthSubtitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'檢查數量、作品欄位與圖片缺漏、欄位來源及待清理檔案。'**
  String get dataHealthSubtitle;

  /// No description provided for @dataHealthSectionUnavailable.
  ///
  /// In zh_TW, this message translates to:
  /// **'此區段無法載入：{section}'**
  String dataHealthSectionUnavailable(String section);

  /// No description provided for @dataHealthRefresh.
  ///
  /// In zh_TW, this message translates to:
  /// **'重新整理'**
  String get dataHealthRefresh;

  /// No description provided for @dataHealthActresses.
  ///
  /// In zh_TW, this message translates to:
  /// **'女優'**
  String get dataHealthActresses;

  /// No description provided for @dataHealthWorks.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品'**
  String get dataHealthWorks;

  /// No description provided for @dataHealthStored.
  ///
  /// In zh_TW, this message translates to:
  /// **'已收藏影片'**
  String get dataHealthStored;

  /// No description provided for @dataHealthNotStored.
  ///
  /// In zh_TW, this message translates to:
  /// **'未收藏影片'**
  String get dataHealthNotStored;

  /// No description provided for @dataHealthMetadataIssues.
  ///
  /// In zh_TW, this message translates to:
  /// **'缺少作品欄位'**
  String get dataHealthMetadataIssues;

  /// No description provided for @dataHealthMissingImages.
  ///
  /// In zh_TW, this message translates to:
  /// **'缺少圖片引用'**
  String get dataHealthMissingImages;

  /// No description provided for @dataHealthMissingProvenance.
  ///
  /// In zh_TW, this message translates to:
  /// **'缺少欄位來源'**
  String get dataHealthMissingProvenance;

  /// No description provided for @dataHealthPendingDeletions.
  ///
  /// In zh_TW, this message translates to:
  /// **'待清理檔案'**
  String get dataHealthPendingDeletions;

  /// No description provided for @settingsDataHealthTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'資料健康度'**
  String get settingsDataHealthTitle;

  /// No description provided for @settingsDataHealthSubtitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'查看資料完整性與欄位來源。'**
  String get settingsDataHealthSubtitle;

  /// No description provided for @libraryImportTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'資料夾刮削與媒體入庫'**
  String get libraryImportTitle;

  /// No description provided for @libraryImportOpen.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入影片'**
  String get libraryImportOpen;

  /// No description provided for @libraryImportSelectFolder.
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇刮削資料夾'**
  String get libraryImportSelectFolder;

  /// No description provided for @libraryImportSelectRoot.
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇收藏資料夾'**
  String get libraryImportSelectRoot;

  /// No description provided for @libraryImportScan.
  ///
  /// In zh_TW, this message translates to:
  /// **'掃描資料夾'**
  String get libraryImportScan;

  /// No description provided for @libraryImportConfirm.
  ///
  /// In zh_TW, this message translates to:
  /// **'確認並開始刮削'**
  String get libraryImportConfirm;

  /// No description provided for @libraryImportPhase1ReadOnly.
  ///
  /// In zh_TW, this message translates to:
  /// **'目前階段只讀取檔名與檔案資訊，不會修改來源影片。'**
  String get libraryImportPhase1ReadOnly;

  /// No description provided for @libraryImportNoFolder.
  ///
  /// In zh_TW, this message translates to:
  /// **'請先選擇刮削資料夾。'**
  String get libraryImportNoFolder;

  /// No description provided for @libraryImportNoRoot.
  ///
  /// In zh_TW, this message translates to:
  /// **'請先選擇收藏資料夾。'**
  String get libraryImportNoRoot;

  /// No description provided for @libraryImportManualCode.
  ///
  /// In zh_TW, this message translates to:
  /// **'手動修正番號'**
  String get libraryImportManualCode;

  /// No description provided for @libraryImportStatusReady.
  ///
  /// In zh_TW, this message translates to:
  /// **'可處理'**
  String get libraryImportStatusReady;

  /// No description provided for @libraryImportStatusNeedsCorrection.
  ///
  /// In zh_TW, this message translates to:
  /// **'需要修正番號'**
  String get libraryImportStatusNeedsCorrection;

  /// No description provided for @libraryImportSelected.
  ///
  /// In zh_TW, this message translates to:
  /// **'已選取 {count} 個檔案'**
  String libraryImportSelected(int count);

  /// No description provided for @libraryImportResult.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入結果：成功 {succeeded}、重複 {duplicate}、失敗 {failed}'**
  String libraryImportResult(int succeeded, int duplicate, int failed);

  /// No description provided for @libraryImportSource.
  ///
  /// In zh_TW, this message translates to:
  /// **'來源資料夾'**
  String get libraryImportSource;

  /// No description provided for @libraryImportDestination.
  ///
  /// In zh_TW, this message translates to:
  /// **'目的地 LibraryRoot'**
  String get libraryImportDestination;

  /// No description provided for @libraryImportSelectAll.
  ///
  /// In zh_TW, this message translates to:
  /// **'選取所有可辨識檔案'**
  String get libraryImportSelectAll;

  /// No description provided for @libraryImportClearAll.
  ///
  /// In zh_TW, this message translates to:
  /// **'清除全部'**
  String get libraryImportClearAll;

  /// No description provided for @libraryImportReview.
  ///
  /// In zh_TW, this message translates to:
  /// **'檢查已選取項目'**
  String get libraryImportReview;

  /// No description provided for @libraryImportBackToScan.
  ///
  /// In zh_TW, this message translates to:
  /// **'返回掃描'**
  String get libraryImportBackToScan;

  /// No description provided for @libraryImportCommit.
  ///
  /// In zh_TW, this message translates to:
  /// **'正式匯入 Library'**
  String get libraryImportCommit;

  /// No description provided for @libraryImportReviewTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'檢查匯入內容'**
  String get libraryImportReviewTitle;

  /// No description provided for @libraryImportPrimaryPerformer.
  ///
  /// In zh_TW, this message translates to:
  /// **'主女優'**
  String get libraryImportPrimaryPerformer;

  /// No description provided for @libraryImportChoosePrimary.
  ///
  /// In zh_TW, this message translates to:
  /// **'選擇主女優'**
  String get libraryImportChoosePrimary;

  /// No description provided for @libraryImportPrimaryRequired.
  ///
  /// In zh_TW, this message translates to:
  /// **'正式匯入前必須選擇主女優。'**
  String get libraryImportPrimaryRequired;

  /// No description provided for @libraryImportReviewNoItems.
  ///
  /// In zh_TW, this message translates to:
  /// **'沒有可供檢查的已選取媒體。'**
  String get libraryImportReviewNoItems;

  /// No description provided for @libraryImportReviewWork.
  ///
  /// In zh_TW, this message translates to:
  /// **'作品'**
  String get libraryImportReviewWork;

  /// No description provided for @libraryImportReviewMedia.
  ///
  /// In zh_TW, this message translates to:
  /// **'媒體'**
  String get libraryImportReviewMedia;

  /// No description provided for @libraryImportReviewDestination.
  ///
  /// In zh_TW, this message translates to:
  /// **'目的地'**
  String get libraryImportReviewDestination;

  /// No description provided for @libraryImportReviewIssues.
  ///
  /// In zh_TW, this message translates to:
  /// **'檢查問題'**
  String get libraryImportReviewIssues;

  /// No description provided for @libraryImportCommitBlocked.
  ///
  /// In zh_TW, this message translates to:
  /// **'所有已選取項目準備完成前，不能正式匯入。'**
  String get libraryImportCommitBlocked;

  /// No description provided for @libraryImportNoRecognizable.
  ///
  /// In zh_TW, this message translates to:
  /// **'找不到可辨識的影片檔案。'**
  String get libraryImportNoRecognizable;

  /// No description provided for @libraryMediaTitle.
  ///
  /// In zh_TW, this message translates to:
  /// **'媒體檔案'**
  String get libraryMediaTitle;

  /// No description provided for @libraryMediaPlay.
  ///
  /// In zh_TW, this message translates to:
  /// **'播放媒體'**
  String get libraryMediaPlay;

  /// No description provided for @libraryMediaUnavailable.
  ///
  /// In zh_TW, this message translates to:
  /// **'媒體檔案無法使用，請修復 Library 項目。'**
  String get libraryMediaUnavailable;

  /// No description provided for @libraryMediaPart.
  ///
  /// In zh_TW, this message translates to:
  /// **'分段'**
  String get libraryMediaPart;

  /// No description provided for @libraryMediaResolution.
  ///
  /// In zh_TW, this message translates to:
  /// **'解析度'**
  String get libraryMediaResolution;

  /// No description provided for @libraryMediaFrameRate.
  ///
  /// In zh_TW, this message translates to:
  /// **'影格率'**
  String get libraryMediaFrameRate;

  /// No description provided for @dataHealthLibraryWorks.
  ///
  /// In zh_TW, this message translates to:
  /// **'Library 作品'**
  String get dataHealthLibraryWorks;

  /// No description provided for @dataHealthLibraryMediaIssues.
  ///
  /// In zh_TW, this message translates to:
  /// **'Library 媒體問題'**
  String get dataHealthLibraryMediaIssues;

  /// No description provided for @dataHealthImportRepairs.
  ///
  /// In zh_TW, this message translates to:
  /// **'匯入待修復'**
  String get dataHealthImportRepairs;

  /// No description provided for @dataHealthLibraryLinks.
  ///
  /// In zh_TW, this message translates to:
  /// **'女優連結問題'**
  String get dataHealthLibraryLinks;

  /// No description provided for @playbackSettings.
  ///
  /// In zh_TW, this message translates to:
  /// **'播放設定'**
  String get playbackSettings;

  /// No description provided for @playbackSeekSeconds.
  ///
  /// In zh_TW, this message translates to:
  /// **'跳轉間隔'**
  String get playbackSeekSeconds;

  /// No description provided for @playbackHoldSpeed.
  ///
  /// In zh_TW, this message translates to:
  /// **'長按播放速度'**
  String get playbackHoldSpeed;

  /// No description provided for @seconds.
  ///
  /// In zh_TW, this message translates to:
  /// **'秒'**
  String get seconds;

  /// No description provided for @playerBack.
  ///
  /// In zh_TW, this message translates to:
  /// **'返回'**
  String get playerBack;

  /// No description provided for @playerPlay.
  ///
  /// In zh_TW, this message translates to:
  /// **'播放'**
  String get playerPlay;

  /// No description provided for @playerPause.
  ///
  /// In zh_TW, this message translates to:
  /// **'暫停'**
  String get playerPause;

  /// No description provided for @playerSpeed.
  ///
  /// In zh_TW, this message translates to:
  /// **'速度'**
  String get playerSpeed;

  /// No description provided for @playerSubtitles.
  ///
  /// In zh_TW, this message translates to:
  /// **'字幕'**
  String get playerSubtitles;

  /// No description provided for @playerFullscreen.
  ///
  /// In zh_TW, this message translates to:
  /// **'全螢幕'**
  String get playerFullscreen;

  /// No description provided for @playerExitFullscreen.
  ///
  /// In zh_TW, this message translates to:
  /// **'退出全螢幕'**
  String get playerExitFullscreen;

  /// No description provided for @playerSubtitleOff.
  ///
  /// In zh_TW, this message translates to:
  /// **'關閉'**
  String get playerSubtitleOff;

  /// No description provided for @playerHoldSpeed.
  ///
  /// In zh_TW, this message translates to:
  /// **'長按速度'**
  String get playerHoldSpeed;

  /// No description provided for @playerPosition.
  ///
  /// In zh_TW, this message translates to:
  /// **'播放進度'**
  String get playerPosition;

  /// No description provided for @playerPlaybackError.
  ///
  /// In zh_TW, this message translates to:
  /// **'無法播放這部影片'**
  String get playerPlaybackError;
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
