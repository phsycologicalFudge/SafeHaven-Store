// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get tabApps => 'Aplicaciones';

  @override
  String get tabRecents => 'Recientes';

  @override
  String get tabSearch => 'Buscar';

  @override
  String get tabMyApps => 'Mis aplicaciones';

  @override
  String get tabSettings => 'Ajustes';

  @override
  String get titleRecentlyViewed => 'Visto recientemente';

  @override
  String get retry => 'Reintentar';

  @override
  String get dismiss => 'Cerrar';

  @override
  String get allApps => 'Todas las aplicaciones';

  @override
  String get catalogueTopCharts => 'Más populares';

  @override
  String catalogueTopInCategory(String category) {
    return 'Lo mejor de $category';
  }

  @override
  String get catalogueNewArrivals => 'Novedades';

  @override
  String get catalogueNewBadge => 'NUEVO';

  @override
  String get catalogueForYou => 'Para ti';

  @override
  String get catalogueBrowseAll => 'Explorar todas las aplicaciones';

  @override
  String get catalogueSearchApps => 'Buscar aplicaciones';

  @override
  String get catalogueCouldNotLoad => 'No se pudo cargar el catálogo';

  @override
  String get catalogueNoApps => 'Aún no hay aplicaciones disponibles.';

  @override
  String get catalogueAllCategories => 'Todas las categorías';

  @override
  String get catalogueAnyRating => 'Cualquier valoración';

  @override
  String get catalogueRating1 => '1★ o más';

  @override
  String get catalogueRating2 => '2★ o más';

  @override
  String get catalogueRating3 => '3★ o más';

  @override
  String get catalogueRating4 => '4★ o más';

  @override
  String get catalogueRating5 => 'Solo 5★';

  @override
  String get catalogueSearchPrompt => 'Busca una aplicación para comenzar.';

  @override
  String get catalogueNoResults =>
      'Ninguna aplicación coincide con tus filtros.';

  @override
  String get buttonGet => 'Obtener';

  @override
  String get buttonUpdate => 'Actualizar';

  @override
  String get buttonOpen => 'Abrir';

  @override
  String get buttonInstall => 'Instalar';

  @override
  String get buttonUninstall => 'Desinstalar';

  @override
  String get buttonUnavailable => 'No disponible';

  @override
  String get buttonChecking => 'Comprobando';

  @override
  String get buttonNoLiveApk => 'Aún no hay APK disponible';

  @override
  String get buttonPaused => 'En pausa';

  @override
  String buttonDownloading(String percent) {
    return 'Descargando $percent%';
  }

  @override
  String get historyEmpty => 'Las aplicaciones que veas aparecerán aquí.';

  @override
  String myAppsUpdatesAvailable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count actualizaciones disponibles',
      one: '1 actualización disponible',
    );
    return '$_temp0';
  }

  @override
  String get myAppsUpdateAll => 'Actualizar todo';

  @override
  String get myAppsEmptyTitle =>
      'No se encontraron aplicaciones instaladas desde la tienda.';

  @override
  String get myAppsEmptyBody =>
      'Las aplicaciones solo aparecen aquí cuando el nombre de su paquete coincide con una aplicación del catálogo.';

  @override
  String get myAppsErrorTitle => 'No se pudieron cargar tus aplicaciones';

  @override
  String get appOptionsTitle => 'Opciones de la aplicación';

  @override
  String get appCopyRepoLink => 'Copiar enlace del repositorio';

  @override
  String get appNoRepoLink =>
      'Aún no hay ningún enlace al repositorio disponible.';

  @override
  String get appRepoLinkCopied => 'Enlace del repositorio copiado';

  @override
  String get appMetaRating => 'Valoración';

  @override
  String get appMetaVersion => 'Versión';

  @override
  String get appMetaRepo => 'Repositorio';

  @override
  String get appMetaNone => 'Ninguno';

  @override
  String get appRateTitle => 'Valorar esta aplicación';

  @override
  String get appRateSubtitle => 'Dile a los demás qué te parece';

  @override
  String get appPreviewTitle => 'Vista previa';

  @override
  String get appAboutTitle => 'Acerca de esta aplicación';

  @override
  String get appNoDescription => 'No se ha proporcionado ninguna descripción.';

  @override
  String get appNoShortDescription =>
      'No se ha proporcionado ninguna descripción breve.';

  @override
  String get appWhatsNew => '¿Qué hay de nuevo?';

  @override
  String get securitySignals => 'Indicadores de seguridad';

  @override
  String get securityVerifiedSig => 'Firma verificada';

  @override
  String get securityVerifiedSigBody =>
      'Las actualizaciones se verifican con la firma original del desarrollador.';

  @override
  String get securityLatestScan => 'Último análisis';

  @override
  String get securityNoScanTimestamp =>
      'Aún no hay disponible una marca de tiempo de un análisis completado.';

  @override
  String securityNoThreats(String date) {
    return 'No se detectaron amenazas. Último análisis: $date.';
  }

  @override
  String get technicalAppInfo => 'Información de la aplicación';

  @override
  String get technicalPackage => 'Paquete';

  @override
  String get technicalRepository => 'Repositorio';

  @override
  String get technicalSha256 => 'SHA-256';

  @override
  String get technicalApkSize => 'Tamaño del APK';

  @override
  String get technicalLastScanned => 'Último análisis';

  @override
  String get technicalNotProvided => 'No proporcionado';

  @override
  String get technicalNotAvailable => 'No disponible';

  @override
  String get installFailed => 'Error de instalación';

  @override
  String get installPermissionRequired =>
      'Permite que SafeHaven instale aplicaciones y vuelve a tocar «Instalar».';

  @override
  String get installCouldNotStart => 'No se pudo iniciar el instalador.';

  @override
  String get installIntegrityFailed =>
      'Falló la comprobación de integridad del APK.';

  @override
  String get installIncomplete =>
      'La descarga del APK parece estar incompleta.';

  @override
  String installFailedGeneric(String error) {
    return 'Error de instalación: $error';
  }

  @override
  String get couldNotOpenApp => 'No se pudo abrir la aplicación';

  @override
  String get couldNotOpenAppBody => 'No se pudo abrir esta aplicación.';

  @override
  String get nicknameTitle => 'Elige un apodo';

  @override
  String get nicknameSubtitle =>
      'Se utiliza para identificar valoraciones únicas. No es público.';

  @override
  String get nicknameHint => 'p. ej., Alex';

  @override
  String get nicknameEmpty => 'Introduce un apodo para continuar.';

  @override
  String get nicknameTooShort => 'El apodo debe tener al menos 2 caracteres.';

  @override
  String get nicknameSaving => 'Guardando...';

  @override
  String get nicknameContinue => 'Continuar';

  @override
  String get somethingWentWrong => 'Algo salió mal.';

  @override
  String get ratingTapStar => 'Toca una estrella para valorar esta aplicación';

  @override
  String get ratingSubmit => 'Enviar valoración';

  @override
  String get ratingSubmitting => 'Enviando...';

  @override
  String get ratingThanks => '¡Gracias por tu valoración!';

  @override
  String get ratingAlreadyRated => 'Ya has valorado esta aplicación.';

  @override
  String get ratingRateLimited =>
      'Se han enviado demasiadas valoraciones. Vuelve a intentarlo más tarde.';

  @override
  String get ratingNotFound => 'Aplicación no encontrada.';

  @override
  String get ratingError => 'Algo salió mal. Vuelve a intentarlo.';

  @override
  String get updateResultsTitle =>
      'No se pudieron actualizar algunas aplicaciones';

  @override
  String get updateResultsBody => 'Instala mediante SafeHaven para actualizar';

  @override
  String get updateFailureCannotUpdate =>
      'SafeHaven no puede actualizar la aplicación';

  @override
  String get updateFailureNoLink => 'No se pudo obtener el enlace de descarga';

  @override
  String get updateFailureGeneric => 'No se pudo iniciar la actualización';

  @override
  String get settingsOptions => 'Opciones';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeSubtitle => 'Toca para cambiar';

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsFlawlessUpdates => 'Actualizaciones fluidas';

  @override
  String get settingsUpdateOff => 'Desactivado';

  @override
  String get settingsUpdateLight => 'Ligero';

  @override
  String get settingsUpdateFull => 'Completo';

  @override
  String get settingsUpdateNoneDesc =>
      'SafeHaven no actualizará automáticamente las aplicaciones.';

  @override
  String get settingsUpdateLightDesc =>
      'SafeHaven comprobará si hay actualizaciones cada 6 horas. Esto consume muy poca batería, pero puede que las aplicaciones no se actualicen rápidamente.';

  @override
  String get settingsUpdateFullDesc =>
      'SafeHaven comprobará si hay actualizaciones cada 6 horas y también se ejecutará como servicio en primer plano para buscarlas cada 5 minutos.\n\n[Esto consume aproximadamente entre un 1 y un 3 % más de batería.]';

  @override
  String get settingsDeveloper => 'Desarrollador';

  @override
  String get settingsAccount => 'Cuenta';

  @override
  String get settingsAccountSubtitle => 'Gestiona tu perfil de desarrollador';

  @override
  String get settingsAbout => 'Acerca de';

  @override
  String get settingsHowThisWorks => 'Cómo funciona';

  @override
  String get settingsHowThisWorksSubtitle =>
      'Toca para obtener más información';

  @override
  String get settingsSubmitApp => '¿Quieres enviar una aplicación?';

  @override
  String get settingsSubmitAppSubtitle => 'Toca para saber cómo';

  @override
  String get settingsVersion => 'Versión';

  @override
  String get settingsVersionLoading => 'Cargando...';

  @override
  String get settingsVersionUnknown => 'Desconocida';

  @override
  String get settingsDebugging => 'Depuración';

  @override
  String get settingsDebugLogging => 'Registro de depuración';

  @override
  String get settingsShareLog => 'Compartir registro';

  @override
  String get settingsShareLogSubtitle =>
      'Enviar el archivo de registro de depuración';

  @override
  String get settingsClearLog => 'Borrar registro';

  @override
  String get settingsClearLogSubtitle =>
      'Eliminar el archivo de registro actual';

  @override
  String get devAccountTitle => 'Cuenta de desarrollador';

  @override
  String get devNotSignedIn => 'Sesión no iniciada';

  @override
  String get devSignIn => 'Iniciar sesión';

  @override
  String get devSignOut => 'Cerrar sesión';

  @override
  String get devDashboard => 'Panel';

  @override
  String get devOpening => 'Abriendo...';

  @override
  String get devOpenDashboard => 'Abrir panel';

  @override
  String get devYourApps => 'Tus aplicaciones';

  @override
  String get devSignInPrompt =>
      'Inicia sesión para gestionar los envíos de desarrollador, el estado de revisión, las claves de firma y el acceso al panel.';

  @override
  String get devNoDevAccess =>
      'El acceso de desarrollador no está habilitado. Abre el panel para aceptar los términos para desarrolladores.';

  @override
  String get devNoApps =>
      'Aún no hay aplicaciones registradas. Abre el panel para registrar tu primera aplicación.';

  @override
  String get devCouldNotOpenLogin =>
      'No se pudo abrir la página de inicio de sesión.';

  @override
  String get devCouldNotOpenDashboard => 'No se pudo abrir el panel.';

  @override
  String get devRepository => 'Repositorio';

  @override
  String get devRepoVerified => 'Repositorio verificado';

  @override
  String get devRepoVerifiedYes => 'Sí';

  @override
  String get devRepoVerifiedNo => 'Aún no';

  @override
  String get devSigningKey => 'Clave de firma';

  @override
  String get devSigningKeyNone => 'Aún no fijada';

  @override
  String get devSubmissions => 'Envíos';

  @override
  String get devSeeAllHistory => 'Ver todo el historial';

  @override
  String get devStatusInactive => 'Inactivo';

  @override
  String devVersionCode(String code) {
    return 'Versión $code';
  }

  @override
  String get selfUpdateTitle => 'Actualización disponible';

  @override
  String get selfUpdateDismiss => 'Cerrar';

  @override
  String get selfUpdateRetry => 'Reintentar';

  @override
  String get selfUpdateButton => 'Actualizar';

  @override
  String get selfUpdateDownloadFailed =>
      'Error de descarga. Comprueba tu conexión y vuelve a intentarlo.';

  @override
  String get selfUpdateInstallFailed => 'No se pudo iniciar el instalador.';
}
