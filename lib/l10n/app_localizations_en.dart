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
  String get maxActressCountHint => 'Leave blank for no limit';

  @override
  String get maxActressCountInvalid => 'Enter an integer of 1 or greater';

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
}
