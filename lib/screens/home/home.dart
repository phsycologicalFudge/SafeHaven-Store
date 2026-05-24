import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/theme/theme_manager.dart';
import '../../widgets/footer.dart';
import '../account/settings/settings_screen.dart';
import '../apps/catalogue_screen/catalogue_screen.dart';
import '../apps/history_screen.dart';
import '../apps/my_apps_screen.dart';
import '../apps/search_screen.dart';
import 'top_banner.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  int _previousIndex = 0;
  late final AnimationController _tabController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  static const List<Widget> _screens = [
    CatalogueScreen(),
    HistoryScreen(),
    SearchScreen(),
    MyAppsScreen(),
    SettingsScreen(),
  ];

  static const List<String> _titles = [
    'SafeHaven',
    'Recently Viewed',
    'Search',
    'My Apps',
    'Settings',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _buildAnims(forward: true);
    _tabController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            title: _titles[_selectedIndex],
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