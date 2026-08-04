import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/index_service.dart';
import '../../services/installer/safehaven_updater/self_update_dialog.dart';
import '../../services/installer/safehaven_updater/self_update_service.dart';
import '../../services/installer/store_update_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';
import '../../widgets/footer.dart';
import '../account/settings/settings_screen.dart';
import '../apps/app_screen/app_screen.dart';
import '../apps/catalogue_screen/catalogue_navigation.dart';
import '../apps/catalogue_screen/catalogue_screen.dart';
import '../apps/history_screen.dart';
import '../apps/my_apps_screen.dart';
import '../apps/search_screen.dart';
import 'top_banner.dart';
import 'package:safehaven/translations/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _previousIndex = 0;
  late final AnimationController _tabController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  DateTime? _lastUpdateCheck;
  DateTime? _lastSelfUpdateCheck;
  DateTime? _selfUpdateDismissedUntil;
  bool _selfUpdateDialogOpen = false;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _deepLinkSub;

  static const List<Widget> _screens = [
    CatalogueScreen(),
    HistoryScreen(),
    SearchScreen(),
    MyAppsScreen(),
    SettingsScreen(),
  ];

  List<String> _titles(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return [
      'SafeHaven',
      l.titleRecentlyViewed,
      l.tabSearch,
      l.tabMyApps,
      l.tabSettings,
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _buildAnims(forward: true);
    _tabController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
      _checkForUpdates();
      _checkForSelfUpdate();
      _initDeepLinks();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForUpdates();
      _checkForSelfUpdate();
    }
  }

  Future<void> _checkForUpdates() async {
    final now = DateTime.now();
    if (_lastUpdateCheck != null &&
        now.difference(_lastUpdateCheck!) < const Duration(minutes: 5)) {
      return;
    }
    _lastUpdateCheck = now;
    try {
      final index = await IndexService.instance.fetchIndex(forceRefresh: true);
      await StoreUpdateService.instance.syncAndTriggerAutoUpdates(index.apps);
    } catch (_) {}
  }

  Future<void> _checkForSelfUpdate() async {
    final now = DateTime.now();
    if (_lastSelfUpdateCheck != null &&
        now.difference(_lastSelfUpdateCheck!) < const Duration(hours: 3)) {
      return;
    }
    if (_selfUpdateDismissedUntil != null &&
        now.isBefore(_selfUpdateDismissedUntil!)) {
      return;
    }
    if (_selfUpdateDialogOpen) return;
    _lastSelfUpdateCheck = now;

    try {
      final info = await SelfUpdateService.instance.check();
      if (info == null || !mounted) return;

      _selfUpdateDialogOpen = true;
      await SelfUpdateDialog.show(context, info);
      _selfUpdateDialogOpen = false;
      _selfUpdateDismissedUntil = DateTime.now().add(const Duration(hours: 1));
    } catch (_) {
      _selfUpdateDialogOpen = false;
    }
  }

  void _buildAnims({required bool forward}) {
    final curved = CurvedAnimation(
      parent: _tabController,
      curve: Curves.easeOutCubic,
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnim = Tween<Offset>(
      begin: Offset(forward ? 0.03 : -0.03, 0),
      end: Offset.zero,
    ).animate(curved);
  }

  void _onFooterSelected(int index) {
    if (index == _selectedIndex) return;
    FocusScope.of(context).unfocus();
    final forward = index > _selectedIndex;
    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
      _buildAnims(forward: forward);
    });
    _tabController.forward(from: 0);
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  void _initDeepLinks() {
    _deepLinkSub = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (_) {},
    );
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.host != 'store.colourswift.com') return;
    if (uri.pathSegments.length < 2 || uri.pathSegments[0] != 'app') return;

    final packageName = uri.pathSegments[1];
    if (packageName.isEmpty) return;

    try {
      final app = await StoreService.instance.fetchPublicApp(packageName);
      if (!mounted) return;
      Navigator.of(context).push(pushRoute(AppScreen(app: app)));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SafeHavenThemeManager.instance,
      builder: (context, _) {
        final colors = SafeHavenTheme.of(context);

        return Scaffold(
          backgroundColor: colors.backgroundFrost,
          appBar: _selectedIndex == 0
              ? TopBanner.home()
              : TopBanner.defaultScreen(
            title: _titles(context)[_selectedIndex],
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: child,
                  ),
                );
              },
              child: IndexedStack(
                index: _selectedIndex,
                children: _screens,
              ),
            ),
          ),
          bottomNavigationBar: SafeHavenFooter(
            selectedIndex: _selectedIndex,
            onSelected: _onFooterSelected,
          ),
        );
      },
    );
  }
}