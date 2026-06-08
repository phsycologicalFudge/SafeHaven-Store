import 'package:flutter/material.dart';
import '../../../../services/catalogue_service.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';
import '../../app_screen/app_screen.dart';
import '../catalogue_navigation.dart';
import '../widgets/catalogue_app_icons.dart';
import '../widgets/catalogue_shared_widgets.dart';

class SeeMoreAppsScreen extends StatefulWidget {
  const SeeMoreAppsScreen({
    required this.title,
    required this.apps,
  });

  final String title;
  final List<PublicStoreApp> apps;

  @override
  State<SeeMoreAppsScreen> createState() => _SeeMoreAppsScreenState();
}

class _SeeMoreAppsScreenState extends State<SeeMoreAppsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late List<_SearchableApp> _searchableApps;
  late List<PublicStoreApp> _displayedApps;

  @override
  void initState() {
    super.initState();
    _initSearchables();
  }

  @override
  void didUpdateWidget(SeeMoreAppsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.apps != oldWidget.apps) {
      _initSearchables();
    }
  }

  void _initSearchables() {
    _searchableApps = widget.apps.map((a) => _SearchableApp(a)).toList();
    _filterApps();
  }

  void _filterApps() {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      _displayedApps = widget.apps;
      return;
    }

    _displayedApps = _searchableApps
        .where((a) => a.searchString.contains(query))
        .map((a) => a.app)
        .toList();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _filterApps();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _displayedApps = widget.apps;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Scaffold(
      backgroundColor: colors.backgroundFrost,
      body: SafeArea(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 18, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: colors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: colors.text,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '(${_displayedApps.length})',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          SafeHavenThemeManager.instance.isDark ? 0.16 : 0.045,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Icon(
                        Icons.search_rounded,
                        size: 22,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.text,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search apps',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: colors.textMuted,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: _clearSearch,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: colors.textMuted,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 14),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (_displayedApps.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: CatalogueEmptyBlock(),
                ),
              )
            else
              SliverList.builder(
                itemCount: _displayedApps.length,
                itemBuilder: (context, index) {
                  return _SeeMoreAppRow(app: _displayedApps[index]);
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
          ],
        ),
      ),
    );
  }
}

class _SeeMoreAppRow extends StatelessWidget {
  const _SeeMoreAppRow({required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 18,
      onTap: () {
        Navigator.of(context).push(pushRoute(AppScreen(app: app)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            CatalogueRawAppIcon(app: app, size: 52, radius: 13),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 52,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: colors.text,
                      ),
                    ),
                    if (app.developerName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        app.developerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchableApp {
  _SearchableApp(this.app)
      : searchString = '${app.name} ${app.developerName} ${app.packageName}'.toLowerCase();

  final PublicStoreApp app;
  final String searchString;
}