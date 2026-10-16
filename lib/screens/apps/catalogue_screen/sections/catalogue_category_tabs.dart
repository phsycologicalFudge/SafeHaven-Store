import 'package:flutter/material.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';
import 'package:safehaven/translations/app_localizations.dart';

class CatalogueCategoryTabs extends StatelessWidget {
  const CatalogueCategoryTabs({
    required this.categoryKeys,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categoryKeys;
  final Map<String, String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        children: [
          _CategoryTabItem(
            label: AppLocalizations.of(context)!.catalogueForYou,
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          ...categoryKeys.map((key) {
            final label = categories[key] ?? key;
            return _CategoryTabItem(
              label: label,
              selected: selected == key,
              onTap: () => onSelected(key),
            );
          }),
        ],
      ),
    );
  }
}

class _CategoryTabItem extends StatelessWidget {
  const _CategoryTabItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: AnimatedTap(
        borderRadius: 99,
        scale: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: selected
                ? (SafeHavenThemeManager.instance.isDark ? colors.surface : colors.surfaceSoft)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colors.text : colors.textMuted,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
