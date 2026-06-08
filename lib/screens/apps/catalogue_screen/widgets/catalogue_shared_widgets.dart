import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/animated_tap.dart';


String compactAppName(String name) {
  final trimmed = name.trim();
  if (trimmed.length <= 12) return trimmed;
  return '${trimmed.substring(0, 12)}...';
}

class CatalogueSectionHeader extends StatelessWidget {
  const CatalogueSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogueAllAppsTextButton extends StatelessWidget {
  const CatalogueAllAppsTextButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 14,
      scale: 0.96,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 4),
        child: Row(
          children: [
            Text(
              'All apps',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: colors.accentStart,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: colors.accentStart,
            ),
          ],
        ),
      ),
    );
  }
}

class CatalogueSeeAllBlock extends StatefulWidget {
  const CatalogueSeeAllBlock({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  State<CatalogueSeeAllBlock> createState() => _CatalogueSeeAllBlockState();
}

class _CatalogueSeeAllBlockState extends State<CatalogueSeeAllBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat(reverse: false);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 4),
      child: AnimatedTap(
        borderRadius: 16,
        scale: 0.975,
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.border),
            ),
            child: AnimatedBuilder(
              animation: _shimmer,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_shimmer.value);
                final x = (t * 3.0 - 1.0);
                final screenWidth = MediaQuery.of(context).size.width - 36;
                final shimmerColor = colors.text.withOpacity(0.08);

                return Stack(
                  children: [
                    child!,
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Transform.translate(
                          offset: Offset(x * screenWidth, 0),
                          child: Container(
                            width: 90,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  shimmerColor,
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.5, 1.0],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Browse all apps',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.accentStart.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.count}',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: colors.accentStart,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 17,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CatalogueLoadingBlock extends StatelessWidget {
  const CatalogueLoadingBlock();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 44, 18, 44),
      child: Center(child: CircularProgressIndicator(color: colors.accentEnd)),
    );
  }
}

class CatalogueErrorBlock extends StatelessWidget {
  const CatalogueErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 44, 18, 44),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: colors.textMuted,
            size: 34,
          ),
          const SizedBox(height: 14),
          Text(
            'Could not load catalogue',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSoft,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: colors.accentGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedTap(
                borderRadius: 10,
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Center(
                    child: Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colors.buttonText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CatalogueEmptyBlock extends StatelessWidget {
  const CatalogueEmptyBlock();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 54, 18, 54),
      child: Center(
        child: Text(
          'No apps are live yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: colors.textSoft,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
