import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'translations/app_localizations.dart';
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

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @tabApps.
  ///
  /// In en, this message translates to:
  /// **'Apps'**
  String get tabApps;

  /// No description provided for @tabRecents.
  ///
  /// In en, this message translates to:
  /// **'Recents'**
  String get tabRecents;

  /// No description provided for @tabSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get tabSearch;

  /// No description provided for @tabMyApps.
  ///
  /// In en, this message translates to:
  /// **'My Apps'**
  String get tabMyApps;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @titleRecentlyViewed.
  ///
  /// In en, this message translates to:
  /// **'Recently Viewed'**
  String get titleRecentlyViewed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @allApps.
  ///
  /// In en, this message translates to:
  /// **'All apps'**
  String get allApps;

  /// No description provided for @catalogueTopCharts.
  ///
  /// In en, this message translates to:
  /// **'Top charts'**
  String get catalogueTopCharts;

  /// No description provided for @catalogueTopInCategory.
  ///
  /// In en, this message translates to:
  /// **'Top in {category}'**
  String catalogueTopInCategory(String category);

  /// No description provided for @catalogueNewArrivals.
  ///
  /// In en, this message translates to:
  /// **'New arrivals'**
  String get catalogueNewArrivals;

  /// No description provided for @catalogueNewBadge.
  ///
  /// In en, this message translates to:
  /// **'NEW'**
  String get catalogueNewBadge;

  /// No description provided for @catalogueForYou.
  ///
  /// In en, this message translates to:
  /// **'For you'**
  String get catalogueForYou;

  /// No description provided for @catalogueBrowseAll.
  ///
  /// In en, this message translates to:
  /// **'Browse all apps'**
  String get catalogueBrowseAll;

  /// No description provided for @catalogueSearchApps.
  ///
  /// In en, this message translates to:
  /// **'Search apps'**
  String get catalogueSearchApps;

  /// No description provided for @catalogueCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load catalogue'**
  String get catalogueCouldNotLoad;

  /// No description provided for @catalogueNoApps.
  ///
  /// In en, this message translates to:
  /// **'No apps are live yet.'**
  String get catalogueNoApps;

  /// No description provided for @catalogueAllCategories.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get catalogueAllCategories;

  /// No description provided for @catalogueAnyRating.
  ///
  /// In en, this message translates to:
  /// **'Any rating'**
  String get catalogueAnyRating;

  /// No description provided for @catalogueRating1.
  ///
  /// In en, this message translates to:
  /// **'1★ and up'**
  String get catalogueRating1;

  /// No description provided for @catalogueRating2.
  ///
  /// In en, this message translates to:
  /// **'2★ and up'**
  String get catalogueRating2;

  /// No description provided for @catalogueRating3.
  ///
  /// In en, this message translates to:
  /// **'3★ and up'**
  String get catalogueRating3;

  /// No description provided for @catalogueRating4.
  ///
  /// In en, this message translates to:
  /// **'4★ and up'**
  String get catalogueRating4;

  /// No description provided for @catalogueRating5.
  ///
  /// In en, this message translates to:
  /// **'5★ only'**
  String get catalogueRating5;

  /// No description provided for @catalogueSearchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search for an app to begin.'**
  String get catalogueSearchPrompt;

  /// No description provided for @catalogueNoResults.
  ///
  /// In en, this message translates to:
  /// **'No apps matched your filters.'**
  String get catalogueNoResults;

  /// No description provided for @buttonGet.
  ///
  /// In en, this message translates to:
  /// **'Get'**
  String get buttonGet;

  /// No description provided for @buttonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get buttonUpdate;

  /// No description provided for @buttonOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get buttonOpen;

  /// No description provided for @buttonInstall.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get buttonInstall;

  /// No description provided for @buttonUninstall.
  ///
  /// In en, this message translates to:
  /// **'Uninstall'**
  String get buttonUninstall;

  /// No description provided for @buttonUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get buttonUnavailable;

  /// No description provided for @buttonChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get buttonChecking;

  /// No description provided for @buttonNoLiveApk.
  ///
  /// In en, this message translates to:
  /// **'No live APK yet'**
  String get buttonNoLiveApk;

  /// No description provided for @buttonPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get buttonPaused;

  /// No description provided for @buttonDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String buttonDownloading(String percent);

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Apps you view will appear here.'**
  String get historyEmpty;

  /// No description provided for @myAppsUpdatesAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 update available} other{{count} updates available}}'**
  String myAppsUpdatesAvailable(int count);

  /// No description provided for @myAppsUpdateAll.
  ///
  /// In en, this message translates to:
  /// **'Update All'**
  String get myAppsUpdateAll;

  /// No description provided for @myAppsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No installed store apps found.'**
  String get myAppsEmptyTitle;

  /// No description provided for @myAppsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Apps only appear here when their package name matches an app in the catalogue.'**
  String get myAppsEmptyBody;

  /// No description provided for @myAppsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load your apps'**
  String get myAppsErrorTitle;

  /// No description provided for @appOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'App options'**
  String get appOptionsTitle;

  /// No description provided for @appCopyRepoLink.
  ///
  /// In en, this message translates to:
  /// **'Copy repo link'**
  String get appCopyRepoLink;

  /// No description provided for @appNoRepoLink.
  ///
  /// In en, this message translates to:
  /// **'No repository link is available yet.'**
  String get appNoRepoLink;

  /// No description provided for @appRepoLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Repo link copied'**
  String get appRepoLinkCopied;

  /// No description provided for @appMetaRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get appMetaRating;

  /// No description provided for @appMetaVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get appMetaVersion;

  /// No description provided for @appMetaRepo.
  ///
  /// In en, this message translates to:
  /// **'Repo'**
  String get appMetaRepo;

  /// No description provided for @appMetaNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get appMetaNone;

  /// No description provided for @appRateTitle.
  ///
  /// In en, this message translates to:
  /// **'Rate this app'**
  String get appRateTitle;

  /// No description provided for @appRateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tell others what you think'**
  String get appRateSubtitle;

  /// No description provided for @appPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get appPreviewTitle;

  /// No description provided for @appAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About this app'**
  String get appAboutTitle;

  /// No description provided for @appNoDescription.
  ///
  /// In en, this message translates to:
  /// **'No description provided.'**
  String get appNoDescription;

  /// No description provided for @appNoShortDescription.
  ///
  /// In en, this message translates to:
  /// **'No short description provided.'**
  String get appNoShortDescription;

  /// No description provided for @appWhatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s New?'**
  String get appWhatsNew;

  /// No description provided for @securitySignals.
  ///
  /// In en, this message translates to:
  /// **'Security signals'**
  String get securitySignals;

  /// No description provided for @securityVerifiedSig.
  ///
  /// In en, this message translates to:
  /// **'Verified signature'**
  String get securityVerifiedSig;

  /// No description provided for @securityVerifiedSigBody.
  ///
  /// In en, this message translates to:
  /// **'Updates are verified against the original developer signature.'**
  String get securityVerifiedSigBody;

  /// No description provided for @securityLatestScan.
  ///
  /// In en, this message translates to:
  /// **'Latest scan'**
  String get securityLatestScan;

  /// No description provided for @securityNoScanTimestamp.
  ///
  /// In en, this message translates to:
  /// **'No completed scan timestamp is available yet.'**
  String get securityNoScanTimestamp;

  /// No description provided for @securityNoThreats.
  ///
  /// In en, this message translates to:
  /// **'No threats detected. Last scanned {date}.'**
  String securityNoThreats(String date);

  /// No description provided for @technicalAppInfo.
  ///
  /// In en, this message translates to:
  /// **'App info'**
  String get technicalAppInfo;

  /// No description provided for @technicalPackage.
  ///
  /// In en, this message translates to:
  /// **'Package'**
  String get technicalPackage;

  /// No description provided for @technicalRepository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get technicalRepository;

  /// No description provided for @technicalSha256.
  ///
  /// In en, this message translates to:
  /// **'SHA-256'**
  String get technicalSha256;

  /// No description provided for @technicalApkSize.
  ///
  /// In en, this message translates to:
  /// **'APK size'**
  String get technicalApkSize;

  /// No description provided for @technicalLastScanned.
  ///
  /// In en, this message translates to:
  /// **'Last scanned'**
  String get technicalLastScanned;

  /// No description provided for @technicalNotProvided.
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get technicalNotProvided;

  /// No description provided for @technicalNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get technicalNotAvailable;

  /// No description provided for @installFailed.
  ///
  /// In en, this message translates to:
  /// **'Install failed'**
  String get installFailed;

  /// No description provided for @installPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Allow SafeHaven to install apps, then tap Install again.'**
  String get installPermissionRequired;

  /// No description provided for @installCouldNotStart.
  ///
  /// In en, this message translates to:
  /// **'Could not start the installer.'**
  String get installCouldNotStart;

  /// No description provided for @installIntegrityFailed.
  ///
  /// In en, this message translates to:
  /// **'APK integrity check failed.'**
  String get installIntegrityFailed;

  /// No description provided for @installIncomplete.
  ///
  /// In en, this message translates to:
  /// **'APK download appears incomplete.'**
  String get installIncomplete;

  /// No description provided for @installFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Install failed: {error}'**
  String installFailedGeneric(String error);

  /// No description provided for @couldNotOpenApp.
  ///
  /// In en, this message translates to:
  /// **'Could not open app'**
  String get couldNotOpenApp;

  /// No description provided for @couldNotOpenAppBody.
  ///
  /// In en, this message translates to:
  /// **'Could not open this app.'**
  String get couldNotOpenAppBody;

  /// No description provided for @nicknameTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a nickname'**
  String get nicknameTitle;

  /// No description provided for @nicknameSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This is used for unique ratings. It is not public.'**
  String get nicknameSubtitle;

  /// No description provided for @nicknameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. alex'**
  String get nicknameHint;

  /// No description provided for @nicknameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter a nickname to continue.'**
  String get nicknameEmpty;

  /// No description provided for @nicknameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Nickname must be at least 2 characters.'**
  String get nicknameTooShort;

  /// No description provided for @nicknameSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get nicknameSaving;

  /// No description provided for @nicknameContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get nicknameContinue;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get somethingWentWrong;

  /// No description provided for @ratingTapStar.
  ///
  /// In en, this message translates to:
  /// **'Tap a star to rate this app'**
  String get ratingTapStar;

  /// No description provided for @ratingSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit rating'**
  String get ratingSubmit;

  /// No description provided for @ratingSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get ratingSubmitting;

  /// No description provided for @ratingThanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks for your rating!'**
  String get ratingThanks;

  /// No description provided for @ratingAlreadyRated.
  ///
  /// In en, this message translates to:
  /// **'You\'ve already rated this app.'**
  String get ratingAlreadyRated;

  /// No description provided for @ratingRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many ratings submitted. Try again later.'**
  String get ratingRateLimited;

  /// No description provided for @ratingNotFound.
  ///
  /// In en, this message translates to:
  /// **'App not found.'**
  String get ratingNotFound;

  /// No description provided for @ratingError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get ratingError;

  /// No description provided for @updateResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Some apps couldn\'t be updated'**
  String get updateResultsTitle;

  /// No description provided for @updateResultsBody.
  ///
  /// In en, this message translates to:
  /// **'Install through SafeHaven to update'**
  String get updateResultsBody;

  /// No description provided for @updateFailureCannotUpdate.
  ///
  /// In en, this message translates to:
  /// **'App cannot be updated by SafeHaven'**
  String get updateFailureCannotUpdate;

  /// No description provided for @updateFailureNoLink.
  ///
  /// In en, this message translates to:
  /// **'Could not get download link'**
  String get updateFailureNoLink;

  /// No description provided for @updateFailureGeneric.
  ///
  /// In en, this message translates to:
  /// **'Could not start update'**
  String get updateFailureGeneric;

  /// No description provided for @settingsOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get settingsOptions;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to change'**
  String get settingsThemeSubtitle;

  /// No description provided for @settingsFlawlessUpdates.
  ///
  /// In en, this message translates to:
  /// **'Flawless Updates'**
  String get settingsFlawlessUpdates;

  /// No description provided for @settingsUpdateOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsUpdateOff;

  /// No description provided for @settingsUpdateLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsUpdateLight;

  /// No description provided for @settingsUpdateFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get settingsUpdateFull;

  /// No description provided for @settingsUpdateNoneDesc.
  ///
  /// In en, this message translates to:
  /// **'SafeHaven will not automatically update apps for you.'**
  String get settingsUpdateNoneDesc;

  /// No description provided for @settingsUpdateLightDesc.
  ///
  /// In en, this message translates to:
  /// **'SafeHaven will periodically every 6 hours check for updates. This uses minimum battery, but apps may not be updated quickly.'**
  String get settingsUpdateLightDesc;

  /// No description provided for @settingsUpdateFullDesc.
  ///
  /// In en, this message translates to:
  /// **'SafeHaven will periodically every 6 hours, and run as a foreground service to check for updates every 5 minutes.\n\n[This uses around 1-3% more battery.]'**
  String get settingsUpdateFullDesc;

  /// No description provided for @settingsDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get settingsDeveloper;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your developer profile'**
  String get settingsAccountSubtitle;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsHowThisWorks.
  ///
  /// In en, this message translates to:
  /// **'How This Works'**
  String get settingsHowThisWorks;

  /// No description provided for @settingsHowThisWorksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to find out'**
  String get settingsHowThisWorksSubtitle;

  /// No description provided for @settingsSubmitApp.
  ///
  /// In en, this message translates to:
  /// **'Want to submit an app?'**
  String get settingsSubmitApp;

  /// No description provided for @settingsSubmitAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to find out how'**
  String get settingsSubmitAppSubtitle;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// No description provided for @settingsVersionLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get settingsVersionLoading;

  /// No description provided for @settingsVersionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get settingsVersionUnknown;

  /// No description provided for @settingsDebugging.
  ///
  /// In en, this message translates to:
  /// **'Debugging'**
  String get settingsDebugging;

  /// No description provided for @settingsDebugLogging.
  ///
  /// In en, this message translates to:
  /// **'Debug Logging'**
  String get settingsDebugLogging;

  /// No description provided for @settingsShareLog.
  ///
  /// In en, this message translates to:
  /// **'Share Log'**
  String get settingsShareLog;

  /// No description provided for @settingsShareLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send the debug log file'**
  String get settingsShareLogSubtitle;

  /// No description provided for @settingsClearLog.
  ///
  /// In en, this message translates to:
  /// **'Clear Log'**
  String get settingsClearLog;

  /// No description provided for @settingsClearLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the current log file'**
  String get settingsClearLogSubtitle;

  /// No description provided for @devAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Developer account'**
  String get devAccountTitle;

  /// No description provided for @devNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get devNotSignedIn;

  /// No description provided for @devSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get devSignIn;

  /// No description provided for @devSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get devSignOut;

  /// No description provided for @devDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get devDashboard;

  /// No description provided for @devOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening...'**
  String get devOpening;

  /// No description provided for @devOpenDashboard.
  ///
  /// In en, this message translates to:
  /// **'Open dashboard'**
  String get devOpenDashboard;

  /// No description provided for @devYourApps.
  ///
  /// In en, this message translates to:
  /// **'Your apps'**
  String get devYourApps;

  /// No description provided for @devSignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to manage developer submissions, review status, signing keys, and dashboard access.'**
  String get devSignInPrompt;

  /// No description provided for @devNoDevAccess.
  ///
  /// In en, this message translates to:
  /// **'Developer access is not enabled. Open the dashboard to agree to the developer terms.'**
  String get devNoDevAccess;

  /// No description provided for @devNoApps.
  ///
  /// In en, this message translates to:
  /// **'No apps registered yet. Open the dashboard to register your first app.'**
  String get devNoApps;

  /// No description provided for @devCouldNotOpenLogin.
  ///
  /// In en, this message translates to:
  /// **'Could not open login page.'**
  String get devCouldNotOpenLogin;

  /// No description provided for @devCouldNotOpenDashboard.
  ///
  /// In en, this message translates to:
  /// **'Could not open dashboard.'**
  String get devCouldNotOpenDashboard;

  /// No description provided for @devRepository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get devRepository;

  /// No description provided for @devRepoVerified.
  ///
  /// In en, this message translates to:
  /// **'Repo verified'**
  String get devRepoVerified;

  /// No description provided for @devRepoVerifiedYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get devRepoVerifiedYes;

  /// No description provided for @devRepoVerifiedNo.
  ///
  /// In en, this message translates to:
  /// **'Not yet'**
  String get devRepoVerifiedNo;

  /// No description provided for @devSigningKey.
  ///
  /// In en, this message translates to:
  /// **'Signing key'**
  String get devSigningKey;

  /// No description provided for @devSigningKeyNone.
  ///
  /// In en, this message translates to:
  /// **'Not locked yet'**
  String get devSigningKeyNone;

  /// No description provided for @devSubmissions.
  ///
  /// In en, this message translates to:
  /// **'Submissions'**
  String get devSubmissions;

  /// No description provided for @devVersionCode.
  ///
  /// In en, this message translates to:
  /// **'Version {code}'**
  String devVersionCode(String code);

  /// No description provided for @selfUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get selfUpdateTitle;

  /// No description provided for @selfUpdateDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get selfUpdateDismiss;

  /// No description provided for @selfUpdateRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get selfUpdateRetry;

  /// No description provided for @selfUpdateButton.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get selfUpdateButton;

  /// No description provided for @selfUpdateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed. Check your connection and try again.'**
  String get selfUpdateDownloadFailed;

  /// No description provided for @selfUpdateInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the installer.'**
  String get selfUpdateInstallFailed;
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
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
