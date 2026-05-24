import 'package:flutter/material.dart';
import '../services/theme/theme_manager.dart';

class SafeHavenFooter extends StatelessWidget {
  const SafeHavenFooter({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 70 + bottomPadding,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: colors.navBackground,
        border: Border(
          top: BorderSide(color: colors.navBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          _FooterItem(
            index: 0,
            selectedIndex: selectedIndex,
            icon: Icons.widgets_rounded,
            label: 'Apps',
            onSelected: onSelected,
          ),
          _FooterItem(
            index: 1,
            selectedIndex: selectedIndex,
            icon: Icons.update_rounded,
            label: 'Recents',
            onSelected: onSelected,
          ),
          _FooterItem(
            index: 2,
            selectedIndex: selectedIndex,
            icon: Icons.manage_search_rounded,
            label: 'Search',
            onSelected: onSelected,
          ),
          _FooterItem(
            index: 3,
            selectedIndex: selectedIndex,
            icon: Icons.phone_android_rounded,
            label: 'My Apps',
            onSelected: onSelected,
          ),
          _FooterItem(
            index: 4,
            selectedIndex: selectedIndex,
            icon: Icons.tune_rounded,
            label: 'Settings',
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

class _FooterItem extends StatelessWidget {
  const _FooterItem({
    required this.index,
    required this.selectedIndex,
    required this.icon,
    required this.label,
    required this.onSelected,
  });

  final int index;
  final int selectedIndex;
  final IconData icon;
  final String label;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final selected = index == selectedIndex;

    return Expanded(
      child: InkWell(
        onTap: () => onSelected(index),
        child: SizedBox(
          height: 70,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: selected
                ? _SelectedItem(
              key: ValueKey('sel_$index'),
              icon: icon,
              label: label,
              colors: colors,
            )
                : _UnselectedItem(
              key: ValueKey('unsel_$index'),
              icon: icon,
              label: label,
              colors: colors,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedItem extends StatelessWidget {
  const _SelectedItem({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final SafeHavenColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ShaderMask(
          shaderCallback: (bounds) =>
              colors.accentGradient.createShader(bounds),
          child: Icon(icon, size: 26, color: Colors.white),
        ),
        const SizedBox(height: 4),
        ShaderMask(
          shaderCallback: (bounds) =>
              colors.accentGradient.createShader(bounds),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _UnselectedItem extends StatelessWidget {
  const _UnselectedItem({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final SafeHavenColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: colors.textMuted),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}