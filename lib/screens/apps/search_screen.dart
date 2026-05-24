import 'package:flutter/material.dart';

import '../../services/index_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';
import '../../widgets/animated_tap.dart';
import 'app_screen/app_screen.dart';
import 'catalogue_screen/catalogue_navigation.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const String _allCategoriesValue = '__all_categories__';

  final TextEditingController _searchController = TextEditingController();
  late Future<StoreIndex> _future;
  String _query = '';
  String? _selectedCategory;
  double _minRating = 0;

  bool get _hasActiveSearch =>
      _query.isNotEmpty || _selectedCategory != null || _minRating > 0;

  @override
  void initState() {
    super.initState();
    _future = IndexService.instance.fetchIndex();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PublicStoreApp> _filtered(List<PublicStoreApp> apps) {
    if (!_hasActiveSearch) return const [];

    return apps.where((app) {
      final matchesQuery = _query.isEmpty ||
          app.name.toLowerCase().contains(_query) ||
          app.packageName.toLowerCase().contains(_query) ||
          app.displaySummary.toLowerCase().contains(_query);

      final matchesCategory =
          _selectedCategory == null || app.category == _selectedCategory;

      final matchesRating = _minRating == 0 || app.ratingAvg >= _minRating;

      return matchesQuery && matchesCategory && matchesRating;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return FutureBuilder<StoreIndex>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final index = snapshot.data;
        final filtered = _filtered(index?.apps ?? []);
        final categories = index?.categories ?? {};

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SearchBar(controller: _searchController),
            _FilterRow(
              categories: categories,
              selectedCategory: _selectedCategory,
              minRating: _minRating,
              allCategoriesValue: _allCategoriesValue,
              onCategoryChanged: (v) {
                setState(() {
                  _selectedCategory =
                  v == _allCategoriesValue ? null : v;
                });
              },
              onRatingChanged: (v) => setState(() => _minRating = v),
            ),
            Expanded(
              child: loading
                  ? Center(
                child: CircularProgressIndicator(
                  color: colors.accentEnd,
                ),
              )
                  : snapshot.hasError
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              )
                  : filtered.isEmpty
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    !_hasActiveSearch
                        ? 'Search for an app to begin.'
                        : 'No apps matched your filters.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              )
                  : ListView.builder(
                padding:
                const EdgeInsets.only(top: 4, bottom: 18),
                itemCount: filtered.length,
                itemBuilder: (context, index) =>
                    _AppRow(app: filtered[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              Icons.search_rounded,
              size: 22,
              color: colors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search apps',
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: colors.textMuted,
                  ),
                ),
                style: TextStyle(
                  fontSize: 15,
                  color: colors.text,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                onPressed: controller.clear,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: colors.textMuted,
                ),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.categories,
    required this.selectedCategory,
    required this.minRating,
    required this.allCategoriesValue,
    required this.onCategoryChanged,
    required this.onRatingChanged,
  });

  final Map<String, String> categories;
  final String? selectedCategory;
  final double minRating;
  final String allCategoriesValue;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<double> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    final categoryLabel = selectedCategory == null
        ? 'All categories'
        : categories[selectedCategory] ?? 'All categories';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(
        children: [
          Expanded(
            child: _FilterMenu<String>(
              value: selectedCategory ?? allCategoriesValue,
              label: categoryLabel,
              items: [
                _FilterMenuItem(
                  value: allCategoriesValue,
                  label: 'All categories',
                ),
                ...categories.entries.map(
                      (e) => _FilterMenuItem(
                    value: e.key,
                    label: e.value,
                  ),
                ),
              ],
              onChanged: onCategoryChanged,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FilterMenu<double>(
              value: minRating,
              label: _ratingLabel(minRating),
              items: const [
                _FilterMenuItem(value: 0.0, label: 'Any rating'),
                _FilterMenuItem(value: 1.0, label: '1★ and up'),
                _FilterMenuItem(value: 2.0, label: '2★ and up'),
                _FilterMenuItem(value: 3.0, label: '3★ and up'),
                _FilterMenuItem(value: 4.0, label: '4★ and up'),
                _FilterMenuItem(value: 5.0, label: '5★ only'),
              ],
              onChanged: onRatingChanged,
            ),
          ),
        ],
      ),
    );
  }

  static String _ratingLabel(double rating) {
    switch (rating) {
      case 1.0:
        return '1★ and up';
      case 2.0:
        return '2★ and up';
      case 3.0:
        return '3★ and up';
      case 4.0:
        return '4★ and up';
      case 5.0:
        return '5★ only';
      default:
        return 'Any rating';
    }
  }
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final String label;
  final List<_FilterMenuItem<T>> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return PopupMenuButton<T>(
      initialValue: value,
      tooltip: '',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: colors.surface,
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.10),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      constraints: const BoxConstraints(
        minWidth: 160,
        maxWidth: 260,
      ),
      itemBuilder: (context) {
        return items.map((item) {
          final selected = item.value == value;

          return PopupMenuItem<T>(
            value: item.value,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? colors.text : colors.textSoft,
                      fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_rounded,
                    size: 17,
                    color: colors.accentEnd,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
      onSelected: onChanged,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterMenuItem<T> {
  const _FilterMenuItem({
    required this.value,
    required this.label,
  });

  final T value;
  final String label;
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app});

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
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          children: [
            _AppIcon(app: app, size: 48),
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
                        fontSize: 14,
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
                          fontWeight: FontWeight.w600,
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

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, required this.size});

  final PublicStoreApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final iconUrl = app.iconUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox(
        width: size,
        height: size,
        child: iconUrl == null
            ? Container(
          color: colors.surfaceSoft,
          child: Icon(
            Icons.apps_rounded,
            size: size * 0.48,
            color: colors.textMuted,
          ),
        )
            : Image.network(
          iconUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: colors.surfaceSoft,
            child: Icon(
              Icons.apps_rounded,
              size: size * 0.48,
              color: colors.textMuted,
            ),
          ),
          loadingBuilder: (_, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: colors.surfaceSoft,
              child: Icon(
                Icons.apps_rounded,
                size: size * 0.48,
                color: colors.textMuted,
              ),
            );
          },
        ),
      ),
    );
  }
}