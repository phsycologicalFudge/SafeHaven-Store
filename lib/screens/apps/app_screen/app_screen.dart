import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safehaven/screens/apps/app_screen/sections/app_screen_details.dart';
import 'package:safehaven/screens/apps/app_screen/sections/app_screen_header.dart';
import 'package:safehaven/screens/apps/app_screen/sections/app_screen_install_button.dart';
import 'package:safehaven/screens/apps/app_screen/sections/app_screen_technical.dart';
import '../../../services/history_service.dart';
import '../../../services/store_service.dart';
import '../../../services/theme/theme_manager.dart';
import 'app_screen_helpers.dart';

class AppScreen extends StatefulWidget {
  const AppScreen({super.key, required this.app});

  final PublicStoreApp app;

  @override
  State<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  Color _iconColor = const Color(0xFF161A24);
  int _iconColorRequestId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      _scrollOffset.value = _scrollController.offset;
    });
    _recordHistory();
    _loadIconColor();
  }

  @override
  void didUpdateWidget(covariant AppScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.app.packageName != widget.app.packageName) {
      _recordHistory();
    }

    if (oldWidget.app.iconUrl != widget.app.iconUrl) {
      _iconColor = const Color(0xFF161A24);
      _loadIconColor();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollOffset.dispose();
    super.dispose();
  }

  void _recordHistory() {
    HistoryService.instance.recordView(widget.app.packageName);
    HistoryService.instance.recordCategoryView(widget.app.category);
  }

  Future<void> _loadIconColor() async {
    final requestId = ++_iconColorRequestId;
    final iconUrl = widget.app.iconUrl?.trim();

    if (iconUrl == null || iconUrl.isEmpty) return;

    final color = await extractImageColor(iconUrl);

    if (!mounted || requestId != _iconColorRequestId || color == null) return;

    setState(() => _iconColor = color);
  }

  void _showActionsSheet() {
    final colors = SafeHavenTheme.of(context);
    final repoUrl = widget.app.repoUrl.trim();

    showDialog(
      context: context,
      builder: (_) => AppAccentDialog(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'App options',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 16),
              _ActionSheetItem(
                icon: Icons.content_copy_rounded,
                title: 'Copy repo link',
                subtitle: repoUrl.isEmpty
                    ? 'No repository link is available yet.'
                    : repoUrl,
                enabled: repoUrl.isNotEmpty,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: repoUrl));
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Repo link copied')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final accent = polishAccentColor(_iconColor);
    final topPadding = MediaQuery.paddingOf(context).top;

    final isDark = SafeHavenThemeManager.instance.isDark;
    final topGlowOpacity = isDark ? 0.08 : 0.10;
    final midWashOpacity = isDark ? 0.03 : 0.04;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: colors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.background,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      accent.withOpacity(topGlowOpacity),
                      accent.withOpacity(midWashOpacity),
                      colors.background.withOpacity(0),
                      colors.background.withOpacity(0),
                    ],
                    stops: const [0.0, 0.40, 0.75, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -90,
            right: -90,
            child: IgnorePointer(
              child: Container(
                height: 450,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.25,
                    colors: [
                      accent.withOpacity(topGlowOpacity),
                      colors.background.withOpacity(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: topPadding + 56 + 8,
                ),
              ),
              SliverToBoxAdapter(child: AppScreenHeader(app: widget.app)),
              SliverToBoxAdapter(child: AppScreenMetadataRow(app: widget.app)),
              SliverToBoxAdapter(child: AppScreenInstallButton(app: widget.app)),
              SliverToBoxAdapter(child: AppScreenPreviewSection(app: widget.app)),
              SliverToBoxAdapter(child: AppScreenAboutSection(app: widget.app)),
              SliverToBoxAdapter(child: AppScreenTrustSection(app: widget.app)),
              SliverToBoxAdapter(child: AppScreenTechnicalSection(app: widget.app)),
              SliverToBoxAdapter(child: AppScreenRateButton(app: widget.app)),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
          ValueListenableBuilder<double>(
            valueListenable: _scrollOffset,
            builder: (context, offset, _) {
              final t = ((offset - 320) / 40).clamp(0.0, 1.0);

              if (t == 0) return const SizedBox.shrink();

              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Transform.translate(
                  offset: Offset(0, -16 * (1 - t)),
                  child: Opacity(
                    opacity: t,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          height: topPadding + 56,
                          color: colors.surface.withOpacity(isDark ? 0.75 : 0.85),
                          padding: EdgeInsets.only(
                            top: topPadding,
                            left: 64,
                            right: 64,
                          ),
                          alignment: Alignment.center,
                          child: AppScreenInstallButton(
                            app: widget.app,
                            compact: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: topPadding + 4,
            left: 8,
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_back_rounded, color: colors.text),
              ),
            ),
          ),
          Positioned(
            top: topPadding + 4,
            right: 8,
            child: SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                onPressed: _showActionsSheet,
                icon: Icon(Icons.more_vert_rounded, color: colors.textSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionSheetItem extends StatelessWidget {
  const _ActionSheetItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              children: [
                Icon(icon, color: colors.textMuted, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSoft,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}