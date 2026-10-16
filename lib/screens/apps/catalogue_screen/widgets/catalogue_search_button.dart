import 'package:flutter/material.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';
import '../../search_screen.dart';
import '../catalogue_navigation.dart';
import 'package:safehaven/translations/app_localizations.dart';

class CatalogueSearchButton extends StatelessWidget {
  const CatalogueSearchButton();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      child: AnimatedTap(
        borderRadius: 14,
        scale: 0.985,
        onTap: () {
          Navigator.of(context).push(pushRoute(const SearchScreen()));
        },
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
                child: Text(
                  AppLocalizations.of(context)!.catalogueSearchApps,
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }
}
