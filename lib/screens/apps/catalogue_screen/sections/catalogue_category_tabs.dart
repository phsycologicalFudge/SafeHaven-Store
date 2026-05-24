import 'package:flutter/material.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';

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

    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 8),
      alignment: Alignment.bottomLeft,
      decoration: BoxDecoration(
        color: colors.backgroundFrost,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _CategoryTabItem(
            label: 'For you',
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

    return AnimatedTap(
      borderRadius: 10,
      scale: 0.96,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? colors.text : colors.textMuted,
                  ),
                ),
              ),
            ),
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                gradient: selected ? colors.accentGradient : null,
                color: selected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}