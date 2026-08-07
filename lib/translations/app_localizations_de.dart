// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get tabApps => 'Apps';

  @override
  String get tabRecents => 'Zuletzt';

  @override
  String get tabSearch => 'Suchen';

  @override
  String get tabMyApps => 'Meine Apps';

  @override
  String get tabSettings => 'Einstellungen';

  @override
  String get titleRecentlyViewed => 'Zuletzt angesehen';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get dismiss => 'Schließen';

  @override
  String get allApps => 'Alle Apps';

  @override
  String get catalogueTopCharts => 'Top-Charts';

  @override
  String catalogueTopInCategory(String category) {
    return 'Top in $category';
  }

  @override
  String get catalogueNewArrivals => 'Neu hinzugefügt';

  @override
  String get catalogueNewBadge => 'NEU';

  @override
  String get catalogueForYou => 'Für dich';

  @override
  String get catalogueBrowseAll => 'Alle Apps durchsuchen';

  @override
  String get catalogueSearchApps => 'Apps suchen';

  @override
  String get catalogueCouldNotLoad => 'Katalog konnte nicht geladen werden';

  @override
  String get catalogueNoApps => 'Noch sind keine Apps verfügbar.';

  @override
  String get catalogueAllCategories => 'Alle Kategorien';

  @override
  String get catalogueAnyRating => 'Beliebige Bewertung';

  @override
  String get catalogueRating1 => '1★ und höher';

  @override
  String get catalogueRating2 => '2★ und höher';

  @override
  String get catalogueRating3 => '3★ und höher';

  @override
  String get catalogueRating4 => '4★ und höher';

  @override
  String get catalogueRating5 => 'Nur 5★';

  @override
  String get catalogueSearchPrompt => 'Suche nach einer App, um zu beginnen.';

  @override
  String get catalogueNoResults => 'Keine Apps entsprechen deinen Filtern.';

  @override
  String get buttonGet => 'Holen';

  @override
  String get buttonUpdate => 'Aktualisieren';

  @override
  String get buttonOpen => 'Öffnen';

  @override
  String get buttonInstall => 'Installieren';

  @override
  String get buttonUninstall => 'Deinstallieren';

  @override
  String get buttonUnavailable => 'Nicht verfügbar';

  @override
  String get buttonChecking => 'Wird geprüft';

  @override
  String get buttonNoLiveApk => 'Noch keine APK verfügbar';

  @override
  String get buttonPaused => 'Pausiert';

  @override
  String buttonDownloading(String percent) {
    return 'Download läuft: $percent%';
  }

  @override
  String get historyEmpty => 'Apps, die du ansiehst, werden hier angezeigt.';

  @override
  String myAppsUpdatesAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Updates verfügbar',
      one: '1 Update verfügbar',
    );
    return '$_temp0';
  }

  @override
  String get myAppsUpdateAll => 'Alle aktualisieren';

  @override
  String get myAppsEmptyTitle => 'Keine installierten Store-Apps gefunden.';

  @override
  String get myAppsEmptyBody =>
      'Apps werden hier nur angezeigt, wenn ihr Paketname mit einer App im Katalog übereinstimmt.';

  @override
  String get myAppsErrorTitle => 'Deine Apps konnten nicht geladen werden';

  @override
  String get appOptionsTitle => 'App-Optionen';

  @override
  String get appCopyRepoLink => 'Repository-Link kopieren';

  @override
  String get appNoRepoLink => 'Noch ist kein Repository-Link verfügbar.';

  @override
  String get appRepoLinkCopied => 'Repository-Link kopiert';

  @override
  String get appMetaRating => 'Bewertung';

  @override
  String get appMetaVersion => 'Version';

  @override
  String get appMetaRepo => 'Repository';

  @override
  String get appMetaNone => 'Keine';

  @override
  String get appRateTitle => 'Diese App bewerten';

  @override
  String get appRateSubtitle => 'Teile anderen deine Meinung mit';

  @override
  String get appPreviewTitle => 'Vorschau';

  @override
  String get appAboutTitle => 'Über diese App';

  @override
  String get appNoDescription => 'Keine Beschreibung vorhanden.';

  @override
  String get appNoShortDescription => 'Keine Kurzbeschreibung vorhanden.';

  @override
  String get appWhatsNew => 'Was ist neu?';

  @override
  String get securitySignals => 'Sicherheitssignale';

  @override
  String get securityVerifiedSig => 'Verifizierte Signatur';

  @override
  String get securityVerifiedSigBody =>
      'Updates werden anhand der ursprünglichen Entwicklersignatur verifiziert.';

  @override
  String get securityLatestScan => 'Letzter Scan';

  @override
  String get securityNoScanTimestamp =>
      'Noch ist kein Zeitstempel eines abgeschlossenen Scans verfügbar.';

  @override
  String securityNoThreats(String date) {
    return 'Keine Bedrohungen erkannt. Zuletzt gescannt: $date.';
  }

  @override
  String get technicalAppInfo => 'App-Info';

  @override
  String get technicalPackage => 'Paket';

  @override
  String get technicalRepository => 'Repository';

  @override
  String get technicalSha256 => 'SHA-256';

  @override
  String get technicalApkSize => 'APK-Größe';

  @override
  String get technicalLastScanned => 'Zuletzt gescannt';

  @override
  String get technicalNotProvided => 'Nicht angegeben';

  @override
  String get technicalNotAvailable => 'Nicht verfügbar';

  @override
  String get installFailed => 'Installation fehlgeschlagen';

  @override
  String get installPermissionRequired =>
      'Erlaube SafeHaven, Apps zu installieren, und tippe dann erneut auf „Installieren“.';

  @override
  String get installCouldNotStart =>
      'Das Installationsprogramm konnte nicht gestartet werden.';

  @override
  String get installIntegrityFailed =>
      'Die APK-Integritätsprüfung ist fehlgeschlagen.';

  @override
  String get installIncomplete =>
      'Der APK-Download scheint unvollständig zu sein.';

  @override
  String installFailedGeneric(String error) {
    return 'Installation fehlgeschlagen: $error';
  }

  @override
  String get couldNotOpenApp => 'App konnte nicht geöffnet werden';

  @override
  String get couldNotOpenAppBody => 'Diese App konnte nicht geöffnet werden.';

  @override
  String get nicknameTitle => 'Wähle einen Spitznamen';

  @override
  String get nicknameSubtitle =>
      'Dieser wird für eindeutige Bewertungen verwendet. Er ist nicht öffentlich.';

  @override
  String get nicknameHint => 'z. B. Alex';

  @override
  String get nicknameEmpty => 'Gib einen Spitznamen ein, um fortzufahren.';

  @override
  String get nicknameTooShort =>
      'Der Spitzname muss mindestens 2 Zeichen lang sein.';

  @override
  String get nicknameSaving => 'Wird gespeichert...';

  @override
  String get nicknameContinue => 'Weiter';

  @override
  String get somethingWentWrong => 'Etwas ist schiefgelaufen.';

  @override
  String get ratingTapStar => 'Tippe auf einen Stern, um diese App zu bewerten';

  @override
  String get ratingSubmit => 'Bewertung absenden';

  @override
  String get ratingSubmitting => 'Wird gesendet...';

  @override
  String get ratingThanks => 'Danke für deine Bewertung!';

  @override
  String get ratingAlreadyRated => 'Du hast diese App bereits bewertet.';

  @override
  String get ratingRateLimited =>
      'Zu viele Bewertungen gesendet. Versuche es später erneut.';

  @override
  String get ratingNotFound => 'App nicht gefunden.';

  @override
  String get ratingError =>
      'Etwas ist schiefgelaufen. Bitte versuche es erneut.';

  @override
  String get updateResultsTitle =>
      'Einige Apps konnten nicht aktualisiert werden';

  @override
  String get updateResultsBody =>
      'Installiere über SafeHaven, um zu aktualisieren';

  @override
  String get updateFailureCannotUpdate =>
      'Die App kann nicht von SafeHaven aktualisiert werden';

  @override
  String get updateFailureNoLink =>
      'Download-Link konnte nicht abgerufen werden';

  @override
  String get updateFailureGeneric => 'Update konnte nicht gestartet werden';

  @override
  String get settingsOptions => 'Optionen';

  @override
  String get settingsTheme => 'Design';

  @override
  String get settingsThemeSubtitle => 'Zum Ändern tippen';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsFlawlessUpdates => 'Nahtlose Updates';

  @override
  String get settingsUpdateOff => 'Aus';

  @override
  String get settingsUpdateLight => 'Leicht';

  @override
  String get settingsUpdateFull => 'Voll';

  @override
  String get settingsUpdateNoneDesc =>
      'SafeHaven aktualisiert Apps nicht automatisch für dich.';

  @override
  String get settingsUpdateLightDesc =>
      'SafeHaven prüft alle 6 Stunden auf Updates. Dies verbraucht nur wenig Akku, Apps werden dadurch jedoch möglicherweise nicht sofort aktualisiert.';

  @override
  String get settingsUpdateFullDesc =>
      'SafeHaven prüft alle 6 Stunden auf Updates und läuft zusätzlich als Vordergrunddienst, um alle 5 Minuten nach Updates zu suchen.\n\n[Dies verbraucht etwa 1–3 % mehr Akku.]';

  @override
  String get settingsDeveloper => 'Entwickler';

  @override
  String get settingsAccount => 'Konto';

  @override
  String get settingsAccountSubtitle => 'Dein Entwicklerprofil verwalten';

  @override
  String get settingsAbout => 'Über';

  @override
  String get settingsHowThisWorks => 'So funktioniert es';

  @override
  String get settingsHowThisWorksSubtitle => 'Tippen, um mehr zu erfahren';

  @override
  String get settingsSubmitApp => 'Möchtest du eine App einreichen?';

  @override
  String get settingsSubmitAppSubtitle => 'Tippen, um zu erfahren, wie';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsVersionLoading => 'Wird geladen...';

  @override
  String get settingsVersionUnknown => 'Unbekannt';

  @override
  String get settingsDebugging => 'Debugging';

  @override
  String get settingsDebugLogging => 'Debug-Protokollierung';

  @override
  String get settingsShareLog => 'Protokoll teilen';

  @override
  String get settingsShareLogSubtitle => 'Debug-Protokolldatei senden';

  @override
  String get settingsClearLog => 'Protokoll löschen';

  @override
  String get settingsClearLogSubtitle => 'Aktuelle Protokolldatei löschen';

  @override
  String get devAccountTitle => 'Entwicklerkonto';

  @override
  String get devNotSignedIn => 'Nicht angemeldet';

  @override
  String get devSignIn => 'Anmelden';

  @override
  String get devSignOut => 'Abmelden';

  @override
  String get devDashboard => 'Dashboard';

  @override
  String get devOpening => 'Wird geöffnet...';

  @override
  String get devOpenDashboard => 'Dashboard öffnen';

  @override
  String get devYourApps => 'Deine Apps';

  @override
  String get devSignInPrompt =>
      'Melde dich an, um Entwicklereinreichungen, Prüfstatus, Signaturschlüssel und den Dashboard-Zugriff zu verwalten.';

  @override
  String get devNoDevAccess =>
      'Der Entwicklerzugriff ist nicht aktiviert. Öffne das Dashboard, um den Entwicklerbedingungen zuzustimmen.';

  @override
  String get devNoApps =>
      'Noch keine Apps registriert. Öffne das Dashboard, um deine erste App zu registrieren.';

  @override
  String get devCouldNotOpenLogin =>
      'Anmeldeseite konnte nicht geöffnet werden.';

  @override
  String get devCouldNotOpenDashboard =>
      'Dashboard konnte nicht geöffnet werden.';

  @override
  String get devRepository => 'Repository';

  @override
  String get devRepoVerified => 'Repository verifiziert';

  @override
  String get devRepoVerifiedYes => 'Ja';

  @override
  String get devRepoVerifiedNo => 'Noch nicht';

  @override
  String get devSigningKey => 'Signaturschlüssel';

  @override
  String get devSigningKeyNone => 'Noch nicht festgelegt';

  @override
  String get devSubmissions => 'Einreichungen';

  @override
  String get devSeeAllHistory => 'Gesamten Verlauf anzeigen';

  @override
  String get devStatusInactive => 'Inaktiv';

  @override
  String devVersionCode(String code) {
    return 'Version $code';
  }

  @override
  String get selfUpdateTitle => 'Update verfügbar';

  @override
  String get selfUpdateDismiss => 'Schließen';

  @override
  String get selfUpdateRetry => 'Erneut versuchen';

  @override
  String get selfUpdateButton => 'Aktualisieren';

  @override
  String get selfUpdateDownloadFailed =>
      'Download fehlgeschlagen. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get selfUpdateInstallFailed =>
      'Das Installationsprogramm konnte nicht gestartet werden.';
}
