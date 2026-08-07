// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tabApps => 'Apps';

  @override
  String get tabRecents => 'Recents';

  @override
  String get tabSearch => 'Search';

  @override
  String get tabMyApps => 'My Apps';

  @override
  String get tabSettings => 'Settings';

  @override
  String get titleRecentlyViewed => 'Recently Viewed';

  @override
  String get retry => 'Retry';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get allApps => 'All apps';

  @override
  String get catalogueTopCharts => 'Top charts';

  @override
  String catalogueTopInCategory(String category) {
    return 'Top in $category';
  }

  @override
  String get catalogueNewArrivals => 'New arrivals';

  @override
  String get catalogueNewBadge => 'NEW';

  @override
  String get catalogueForYou => 'For you';

  @override
  String get catalogueBrowseAll => 'Browse all apps';

  @override
  String get catalogueSearchApps => 'Search apps';

  @override
  String get catalogueCouldNotLoad => 'Could not load catalogue';

  @override
  String get catalogueNoApps => 'No apps are live yet.';

  @override
  String get catalogueAllCategories => 'All categories';

  @override
  String get catalogueAnyRating => 'Any rating';

  @override
  String get catalogueRating1 => '1★ and up';

  @override
  String get catalogueRating2 => '2★ and up';

  @override
  String get catalogueRating3 => '3★ and up';

  @override
  String get catalogueRating4 => '4★ and up';

  @override
  String get catalogueRating5 => '5★ only';

  @override
  String get catalogueSearchPrompt => 'Search for an app to begin.';

  @override
  String get catalogueNoResults => 'No apps matched your filters.';

  @override
  String get buttonGet => 'Get';

  @override
  String get buttonUpdate => 'Update';

  @override
  String get buttonOpen => 'Open';

  @override
  String get buttonInstall => 'Install';

  @override
  String get buttonUninstall => 'Uninstall';

  @override
  String get buttonUnavailable => 'Unavailable';

  @override
  String get buttonChecking => 'Checking';

  @override
  String get buttonNoLiveApk => 'No live APK yet';

  @override
  String get buttonPaused => 'Paused';

  @override
  String buttonDownloading(String percent) {
    return 'Downloading $percent%';
  }

  @override
  String get historyEmpty => 'Apps you view will appear here.';

  @override
  String myAppsUpdatesAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count updates available',
      one: '1 update available',
    );
    return '$_temp0';
  }

  @override
  String get myAppsUpdateAll => 'Update All';

  @override
  String get myAppsEmptyTitle => 'No installed store apps found.';

  @override
  String get myAppsEmptyBody =>
      'Apps only appear here when their package name matches an app in the catalogue.';

  @override
  String get myAppsErrorTitle => 'Could not load your apps';

  @override
  String get appOptionsTitle => 'App options';

  @override
  String get appCopyRepoLink => 'Copy repo link';

  @override
  String get appNoRepoLink => 'No repository link is available yet.';

  @override
  String get appRepoLinkCopied => 'Repo link copied';

  @override
  String get appMetaRating => 'Rating';

  @override
  String get appMetaVersion => 'Version';

  @override
  String get appMetaRepo => 'Repo';

  @override
  String get appMetaNone => 'None';

  @override
  String get appRateTitle => 'Rate this app';

  @override
  String get appRateSubtitle => 'Tell others what you think';

  @override
  String get appPreviewTitle => 'Preview';

  @override
  String get appAboutTitle => 'About this app';

  @override
  String get appNoDescription => 'No description provided.';

  @override
  String get appNoShortDescription => 'No short description provided.';

  @override
  String get appWhatsNew => 'What\'s New?';

  @override
  String get securitySignals => 'Security signals';

  @override
  String get securityVerifiedSig => 'Verified signature';

  @override
  String get securityVerifiedSigBody =>
      'Updates are verified against the original developer signature.';

  @override
  String get securityLatestScan => 'Latest scan';

  @override
  String get securityNoScanTimestamp =>
      'No completed scan timestamp is available yet.';

  @override
  String securityNoThreats(String date) {
    return 'No threats detected. Last scanned $date.';
  }

  @override
  String get technicalAppInfo => 'App info';

  @override
  String get technicalPackage => 'Package';

  @override
  String get technicalRepository => 'Repository';

  @override
  String get technicalSha256 => 'SHA-256';

  @override
  String get technicalApkSize => 'APK size';

  @override
  String get technicalLastScanned => 'Last scanned';

  @override
  String get technicalNotProvided => 'Not provided';

  @override
  String get technicalNotAvailable => 'Not available';

  @override
  String get installFailed => 'Install failed';

  @override
  String get installPermissionRequired =>
      'Allow SafeHaven to install apps, then tap Install again.';

  @override
  String get installCouldNotStart => 'Could not start the installer.';

  @override
  String get installIntegrityFailed => 'APK integrity check failed.';

  @override
  String get installIncomplete => 'APK download appears incomplete.';

  @override
  String installFailedGeneric(String error) {
    return 'Install failed: $error';
  }

  @override
  String get couldNotOpenApp => 'Could not open app';

  @override
  String get couldNotOpenAppBody => 'Could not open this app.';

  @override
  String get nicknameTitle => 'Choose a nickname';

  @override
  String get nicknameSubtitle =>
      'This is used for unique ratings. It is not public.';

  @override
  String get nicknameHint => 'e.g. alex';

  @override
  String get nicknameEmpty => 'Enter a nickname to continue.';

  @override
  String get nicknameTooShort => 'Nickname must be at least 2 characters.';

  @override
  String get nicknameSaving => 'Saving...';

  @override
  String get nicknameContinue => 'Continue';

  @override
  String get somethingWentWrong => 'Something went wrong.';

  @override
  String get ratingTapStar => 'Tap a star to rate this app';

  @override
  String get ratingSubmit => 'Submit rating';

  @override
  String get ratingSubmitting => 'Submitting...';

  @override
  String get ratingThanks => 'Thanks for your rating!';

  @override
  String get ratingAlreadyRated => 'You\'ve already rated this app.';

  @override
  String get ratingRateLimited =>
      'Too many ratings submitted. Try again later.';

  @override
  String get ratingNotFound => 'App not found.';

  @override
  String get ratingError => 'Something went wrong. Please try again.';

  @override
  String get updateResultsTitle => 'Some apps couldn\'t be updated';

  @override
  String get updateResultsBody => 'Install through SafeHaven to update';

  @override
  String get updateFailureCannotUpdate => 'App cannot be updated by SafeHaven';

  @override
  String get updateFailureNoLink => 'Could not get download link';

  @override
  String get updateFailureGeneric => 'Could not start update';

  @override
  String get settingsOptions => 'Options';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSubtitle => 'Tap to change';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsFlawlessUpdates => 'Flawless Updates';

  @override
  String get settingsUpdateOff => 'Off';

  @override
  String get settingsUpdateLight => 'Light';

  @override
  String get settingsUpdateFull => 'Full';

  @override
  String get settingsUpdateNoneDesc =>
      'SafeHaven will not automatically update apps for you.';

  @override
  String get settingsUpdateLightDesc =>
      'SafeHaven will periodically every 6 hours check for updates. This uses minimum battery, but apps may not be updated quickly.';

  @override
  String get settingsUpdateFullDesc =>
      'SafeHaven will periodically every 6 hours, and run as a foreground service to check for updates every 5 minutes.\n\n[This uses around 1-3% more battery.]';

  @override
  String get settingsDeveloper => 'Developer';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsAccountSubtitle => 'Manage your developer profile';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsHowThisWorks => 'How This Works';

  @override
  String get settingsHowThisWorksSubtitle => 'Tap to find out';

  @override
  String get settingsSubmitApp => 'Want to submit an app?';

  @override
  String get settingsSubmitAppSubtitle => 'Tap to find out how';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsVersionLoading => 'Loading...';

  @override
  String get settingsVersionUnknown => 'Unknown';

  @override
  String get settingsDebugging => 'Debugging';

  @override
  String get settingsDebugLogging => 'Debug Logging';

  @override
  String get settingsShareLog => 'Share Log';

  @override
  String get settingsShareLogSubtitle => 'Send the debug log file';

  @override
  String get settingsClearLog => 'Clear Log';

  @override
  String get settingsClearLogSubtitle => 'Delete the current log file';

  @override
  String get devAccountTitle => 'Developer account';

  @override
  String get devNotSignedIn => 'Not signed in';

  @override
  String get devSignIn => 'Sign in';

  @override
  String get devSignOut => 'Sign out';

  @override
  String get devDashboard => 'Dashboard';

  @override
  String get devOpening => 'Opening...';

  @override
  String get devOpenDashboard => 'Open dashboard';

  @override
  String get devYourApps => 'Your apps';

  @override
  String get devSignInPrompt =>
      'Sign in to manage developer submissions, review status, signing keys, and dashboard access.';

  @override
  String get devNoDevAccess =>
      'Developer access is not enabled. Open the dashboard to agree to the developer terms.';

  @override
  String get devNoApps =>
      'No apps registered yet. Open the dashboard to register your first app.';

  @override
  String get devCouldNotOpenLogin => 'Could not open login page.';

  @override
  String get devCouldNotOpenDashboard => 'Could not open dashboard.';

  @override
  String get devRepository => 'Repository';

  @override
  String get devRepoVerified => 'Repo verified';

  @override
  String get devRepoVerifiedYes => 'Yes';

  @override
  String get devRepoVerifiedNo => 'Not yet';

  @override
  String get devSigningKey => 'Signing key';

  @override
  String get devSigningKeyNone => 'Not locked yet';

  @override
  String get devSubmissions => 'Submissions';

  @override
  String get devSeeAllHistory => 'See all history';

  @override
  String get devStatusInactive => 'Inactive';

  @override
  String devVersionCode(String code) {
    return 'Version $code';
  }

  @override
  String get selfUpdateTitle => 'Update available';

  @override
  String get selfUpdateDismiss => 'Dismiss';

  @override
  String get selfUpdateRetry => 'Retry';

  @override
  String get selfUpdateButton => 'Update';

  @override
  String get selfUpdateDownloadFailed =>
      'Download failed. Check your connection and try again.';

  @override
  String get selfUpdateInstallFailed => 'Could not start the installer.';
}
