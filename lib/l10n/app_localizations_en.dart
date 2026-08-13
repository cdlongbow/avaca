// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get addTitle => 'Add Collection';

  @override
  String get noPhoto => 'No Photo';

  @override
  String get selectPhoto => 'Select Photo';

  @override
  String get removePhoto => 'Remove Photo';

  @override
  String get actressNameRequired => 'Actress Name (Required)';

  @override
  String get saveCard => 'Save Card';

  @override
  String get changePhoto => 'Change Photo';

  @override
  String get deletePhoto => 'Delete Photo';

  @override
  String get noAttributesSet => 'No Attributes Set';

  @override
  String get bodyInfo => 'Details';

  @override
  String get heightCm => 'Height (cm)';

  @override
  String get weightKg => 'Weight (kg)';

  @override
  String get cup => 'Cup';

  @override
  String get measurements => 'Measurements';

  @override
  String get privateNotes => 'Private Notes';

  @override
  String get noNotes => 'No Notes';

  @override
  String get confirmDeleteTitle => 'Confirm Delete?';

  @override
  String get deleteWarningWithPhoto =>
      'This cannot be undone. The photo file will also be deleted.';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirmDelete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get appTitle => 'AVACA';

  @override
  String get search => 'Search';

  @override
  String get filterAndSort => 'Filter & Sort';

  @override
  String get filterSection => 'Filter';

  @override
  String get sortSection => 'Sort';

  @override
  String get sortCreatedDesc => 'Added (Newest)';

  @override
  String get sortCreatedAsc => 'Added (Oldest)';

  @override
  String get sortModifiedDesc => 'Modified (Newest)';

  @override
  String get sortModifiedAsc => 'Modified (Oldest)';

  @override
  String get sortAgeAsc => 'Age (Low to High)';

  @override
  String get sortAgeDesc => 'Age (High to Low)';

  @override
  String get birthDate => 'Birthday';

  @override
  String get setBirthDate => 'Set birthday';

  @override
  String get clear => 'Clear';

  @override
  String get done => 'Done';

  @override
  String ageWithBirthDate(int age, String date) {
    return 'Age $age  $date';
  }

  @override
  String get add => 'Add';

  @override
  String get settings => 'Settings';

  @override
  String get themeAndColors => 'Theme & Colors';

  @override
  String get interfaceSettings => 'Interface';

  @override
  String loadFailed(String error) {
    return 'Failed to load: $error';
  }

  @override
  String get noData => 'No Data';

  @override
  String get searchNameHint => 'Enter a name to search quickly...';

  @override
  String get applySettings => 'Apply Settings';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get followSystem => 'Follow System';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get customTheme => 'Custom Theme';

  @override
  String get pureBlackAmoled => 'Pure Black AMOLED';

  @override
  String get pureBlackOnlyDark => 'Only works with dark theme';

  @override
  String get colorSurface => 'Background';

  @override
  String get colorSurfaceContainer => 'Card Background';

  @override
  String get colorOnSurface => 'Primary Text';

  @override
  String get colorOnSurfaceVariant => 'Secondary Text';

  @override
  String get colorPrimary => 'Primary Accent';

  @override
  String get colorOnPrimary => 'Text on Primary';

  @override
  String get colorOutline => 'Border / Divider';

  @override
  String get colorSnackbarBackground => 'Snackbar Background';

  @override
  String adjustColorTitle(String colorLabel) {
    return 'Adjust $colorLabel';
  }

  @override
  String get apply => 'Apply';

  @override
  String get imageReadFailedUnsupportedFormat =>
      'Failed to read image. The format may not be supported.';

  @override
  String get enterName => 'Please enter a name';

  @override
  String get collectionAdded => 'Added to collection';

  @override
  String get alreadyInCollection => 'Already in collection';

  @override
  String get dataDeleted => 'Data deleted permanently';

  @override
  String get deleteFailed => 'Delete failed';

  @override
  String get photoCroppedRememberSave => 'Photo cropped. Remember to save!';

  @override
  String get detailSaved => 'Details saved';

  @override
  String get saveFailedDuplicateName =>
      'Save failed. The name may already exist.';

  @override
  String get dataNotFound => 'Data not found';

  @override
  String get attrCensored => 'Censored';

  @override
  String get attrUncensored => 'Uncensored';

  @override
  String get attrWestern => 'Western';

  @override
  String get attrFc2 => 'FC2';

  @override
  String get attrDomestic => 'Domestic';

  @override
  String get filterAll => 'All';

  @override
  String get imageCropLoadErrorTitle => 'Image load error';

  @override
  String get close => 'Close';

  @override
  String get imageDecodeFailed => 'Failed to decode image';

  @override
  String get cropZoom => 'Zoom';

  @override
  String get cropPanX => 'Horizontal pan';

  @override
  String get cropPanY => 'Vertical pan';

  @override
  String get confirmCrop => 'Crop';

  @override
  String get language => 'Language';

  @override
  String get worksPageSize => 'Works page size';

  @override
  String get worksPageSizeSmall => 'Small';

  @override
  String get worksPageSizeLarge => 'Large';

  @override
  String get traditionalChineseTaiwan => 'Traditional Chinese (Taiwan)';

  @override
  String get english => 'English';

  @override
  String get simplifiedChinese => 'Simplified Chinese';

  @override
  String get japanese => 'Japanese';

  @override
  String get works => 'Works';

  @override
  String get aliases => 'Aliases';

  @override
  String get manageAliases => 'Manage aliases';

  @override
  String get aliasInputHint => 'Enter an alternate name';

  @override
  String get addAlias => 'Add alias';

  @override
  String get saveAliases => 'Save aliases';

  @override
  String get noAliases => 'No aliases';

  @override
  String get deleteWorks => 'Delete works';

  @override
  String get deleteWorksTitle => 'Delete selected works?';

  @override
  String get deleteWorksWarning =>
      'The selected works will be removed globally, including links from other actresses.';

  @override
  String worksDeleted(int count) {
    return 'Deleted $count works';
  }

  @override
  String get loadFailedGeneric => 'Failed to load';

  @override
  String actressWorksTitle(String actressName) {
    return 'Works featuring $actressName';
  }

  @override
  String get searchWorks => 'Search works';

  @override
  String get workCodeSearchHint => 'Enter a work code to search...';

  @override
  String get noMatchingWorks => 'No matching works';

  @override
  String get scrapeWorks => 'Scrape works';

  @override
  String get scrapeSettings => 'Scrape settings';

  @override
  String get syncActressDetails => 'Sync profile details';

  @override
  String get replaceActressImage => 'Replace actress image';

  @override
  String get maxActressCountLabel =>
      'Do not scrape works with more actresses than this';

  @override
  String get maxActressCountHint => '0 means no limit';

  @override
  String get maxActressCountInvalid => 'Enter an integer of 0 or greater';

  @override
  String get scrapeAvatarUnavailable => 'No usable actress image was found.';

  @override
  String get scrapeAvatarFailed =>
      'Actress image replacement failed; the previous image was kept.';

  @override
  String get fillMissingOnly => 'Only fill missing information on rescrape';

  @override
  String get excludedCodePrefixes => 'Excluded code prefixes';

  @override
  String get codePrefixHint => 'Enter a code prefix';

  @override
  String get addPrefix => 'Add';

  @override
  String get startScrape => 'Start scraping';

  @override
  String get noWorks => 'No works yet';

  @override
  String durationMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get studio => 'Studio';

  @override
  String get publisher => 'Publisher';

  @override
  String get series => 'Series';

  @override
  String scrapeComplete(int saved, int excluded, int failed) {
    return 'Scrape complete: saved $saved, excluded $excluded, failed $failed';
  }

  @override
  String scrapeCancelled(int saved, int excluded, int failed) {
    return 'Scrape cancelled: saved $saved, excluded $excluded, failed $failed';
  }

  @override
  String get scrapeFailed => 'Scrape failed. Please try again.';

  @override
  String get javBusVerificationTitle => 'JavBus verification';

  @override
  String get javBusVerificationInstructions =>
      'JavBus requires a manual regional age check. Answer every question to continue scraping in the same secure session.';

  @override
  String get javBusVerificationSubmit => 'Submit verification';

  @override
  String get settingsDataTransferTitle => 'Data transfer';

  @override
  String get settingsDataTransferSubtitle =>
      'Back up or restore actors, works, details, and images as a ZIP.';

  @override
  String get dataTransferExportTitle => 'Export data';

  @override
  String get dataTransferExportSubtitle =>
      'Choose a destination for a complete ZIP backup.';

  @override
  String get dataTransferImportTitle => 'Import data';

  @override
  String get dataTransferImportSubtitle =>
      'Choose a ZIP backup to restore it for immediate use.';

  @override
  String get dataTransferPreparing => 'Preparing data…';

  @override
  String get dataTransferDuplicateProgress =>
      'Waiting for duplicate-actor choices…';

  @override
  String get dataTransferWriting => 'Writing data and images…';

  @override
  String get dataTransferExportSuccess => 'Export complete.';

  @override
  String dataTransferExportSuccessWithSkippedImages(int count) {
    return 'Export complete; skipped $count unusable images.';
  }

  @override
  String get dataTransferImportSuccess =>
      'Import complete. The data is ready to use.';

  @override
  String get dataTransferDuplicateTitle => 'Duplicate actor found';

  @override
  String get dataTransferDuplicateExplanation =>
      'Compare the avatars and work counts, then choose which actor details to use. Existing works and relations are kept.';

  @override
  String get dataTransferKeepExisting => 'Keep current details';

  @override
  String get dataTransferUseImported => 'Use imported details';

  @override
  String get dataTransferContinue => 'Continue';

  @override
  String dataTransferWorkCount(int count) {
    return 'Works: $count';
  }

  @override
  String get dataTransferArchiveTooLarge =>
      'The ZIP exceeds the supported size.';

  @override
  String get dataTransferUnsafeArchive =>
      'The ZIP contains an unsafe file path.';

  @override
  String get dataTransferCorruptArchive =>
      'The ZIP is corrupt or an image checksum failed.';

  @override
  String get dataTransferFileUnreadable =>
      'The selected file could not be read.';

  @override
  String get dataTransferActorNameConflict =>
      'The imported actor name conflicts with another record.';

  @override
  String get dataTransferBusy =>
      'Another data transfer is already in progress.';

  @override
  String get dataTransferFailed =>
      'Data transfer failed. Existing data was not changed.';

  @override
  String get otherSettings => 'Other';

  @override
  String get about => 'About';

  @override
  String get github => 'github';

  @override
  String get feedbackSuggestions => 'Feedback';

  @override
  String get scrapeSources => 'Scrape sources';

  @override
  String get scrapeSourceDetailsTitle => 'Actress details source';

  @override
  String get scrapeSourceWorksTitle => 'Works source';

  @override
  String get scrapeSourceMinnanoAv => 'Minnano AV';

  @override
  String get scrapeSourceJavBus => 'JavBus';

  @override
  String get scrapeSourceAll => 'All sources (merge and deduplicate by code)';

  @override
  String get scrapeSourceSaveFailed => 'Could not save scrape source settings.';

  @override
  String get scrapePartial => 'Some sources or records could not be processed.';

  @override
  String get scrapeZeroResults => 'No new works were found.';

  @override
  String get softwareUpdate => 'Software update';

  @override
  String get softwareUpdateDescription =>
      'Check for and install the latest AVACA version.';

  @override
  String get currentVersion => 'Current version';

  @override
  String get latestVersion => 'Latest version';

  @override
  String get autoCheckUpdates => 'Check for updates automatically';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String get checkingForUpdates => 'Checking for updates…';

  @override
  String get downloadingUpdate => 'Downloading update…';

  @override
  String get verifyingUpdate => 'Verifying update…';

  @override
  String get installingUpdate => 'Starting installation…';

  @override
  String get updateAvailable => 'Update available';

  @override
  String get upToDate => 'AVACA is up to date.';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Later';

  @override
  String get updateUnavailable =>
      'No update file is available for this device.';

  @override
  String get updateCheckFailed =>
      'Could not check for updates. Try again later.';

  @override
  String get updateDownloadFailed =>
      'The update download failed. Existing data was not changed.';

  @override
  String get updateIntegrityFailed =>
      'The update file failed verification. The update was stopped.';

  @override
  String get updateNotSupported =>
      'Automatic updates are not supported on this device.';

  @override
  String get updateInstallPermissionRequired =>
      'Allow AVACA to install apps from this source first.';

  @override
  String get updatePortableFolderNotWritable =>
      'The portable app folder is not writable. The update was stopped.';

  @override
  String get updateInstallerFailed =>
      'The updater could not start. The current version was kept.';

  @override
  String get updateDataPreserved => 'Your data and settings will be preserved.';
}
