import 'package:flutter/material.dart';
import '../../../../services/index_service.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';
import '../../app_screen/app_screen.dart';
import '../catalogue_navigation.dart';
import '../widgets/catalogue_app_icons.dart';
import '../widgets/catalogue_shared_widgets.dart';
import 'package:safehaven/translations/app_localizations.dart';

class SeeMoreAppsScreen extends StatefulWidget {
  const SeeMoreAppsScreen({required this.title});

  final String title;

  @override
  State<SeeMoreAppsScreen> createState() => _SeeMoreAppsScreenState();
}

class _SeeMoreAppsScreenState extends State<SeeMoreAppsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<PublicStoreApp>? _displayedApps;
  int _queryId = 0;

  @override
  void initState() {
    super.initState();
    _runQuery();
  }

  Future<void> _runQuery() async {
    final id = ++_queryId;
    try {
      final apps = await IndexService.instance.query(query: _searchQuery);
      if (mounted && id == _queryId) setState(() => _displayedApps = apps);
    } catch (_) {
      if (mounted && id == _queryId) setState(() => _displayedApps ??= const []);
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _runQuery();
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final apps = _displayedApps;

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
                          if (apps != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '(${apps.length})',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: colors.textMuted,
                              ),
                            ),
                          ],
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
                    color: colors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.border),
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
                            hintText: AppLocalizations.of(context)!.catalogueSearchApps,
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
            if (apps == null)
              const SliverToBoxAdapter(child: CatalogueLoadingBlock())
            else if (apps.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: CatalogueEmptyBlock(),
                ),
              )
            else
              SliverList.builder(
                itemCount: apps.length,
                itemBuilder: (context, index) {
                  return _SeeMoreAppRow(app: apps[index]);
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
