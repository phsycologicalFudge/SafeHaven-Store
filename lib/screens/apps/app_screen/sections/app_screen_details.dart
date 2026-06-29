import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../services/store_service.dart';
import '../../../../services/theme/theme_manager.dart';
import '../../../../widgets/ratings/rating_sheet.dart';
import '../app_screen_helpers.dart';
import 'app_screen_layout.dart';

class AppScreenRateButton extends StatelessWidget {
  const AppScreenRateButton({super.key, required this.app});

  final PublicStoreApp app;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      child: Column(
        children: [
          Text(
            'Rate this app',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tell others what you think',
            style: TextStyle(
              fontSize: 13,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return GestureDetector(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => AppAccentDialog(
                    child: SingleChildScrollView(
                      child: RatingSheet(app: app),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Icons.star_outline_rounded,
                    size: 38,
                    color: colors.textMuted,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class AppScreenPreviewSection extends StatelessWidget {
  const AppScreenPreviewSection({super.key, required this.app});

  final PublicStoreApp app;

  void _showGallery(BuildContext context, List<String> urls, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: PageView.builder(
            itemCount: urls.length,
            controller: PageController(initialPage: initialIndex),
            itemBuilder: (context, index) {
              return Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: urls[index],
                    fadeInDuration: const Duration(milliseconds: 150),
                    fit: BoxFit.contain,
                    memCacheWidth: 1080,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final shots = app.screenshots
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    if (shots.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppScreenSection(
      title: 'Preview',
      child: SizedBox(
        height: 220,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemCount: shots.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            return InkWell(
              onTap: () => _showGallery(context, shots, index),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 118,
                decoration: BoxDecoration(
                  color: colors.surfaceSoft,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: shots[index],
                  fadeInDuration: const Duration(milliseconds: 150),
                  fit: BoxFit.cover,
                  memCacheWidth: 360,
                  memCacheHeight: 680,
                  filterQuality: FilterQuality.medium,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AppScreenWhatsNewSection extends StatelessWidget {
  const AppScreenWhatsNewSection({super.key, required this.app});

  final PublicStoreApp app;

  String _normalize(String s) => s
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '')
      .trim();

  String get _fullText => _normalize(app.latestVersion?.whatsNew ?? '');

  @override
  Widget build(BuildContext context) {
    final fullText = _fullText;

    if (fullText.isEmpty) {
      return const SizedBox.shrink();
    }

    return AppScreenExpandableSection(
      title: "What's New?",
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: MarkdownBody(
          data: fullText,
          selectable: true,
          softLineBreak: true,
          styleSheet: markdownStyle(context),
          onTapLink: (_, href, __) async {
            if (href == null || href.trim().isEmpty) return;

            final uri = Uri.tryParse(href.trim());
            if (uri == null) return;

            await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
          },
        ),
      ),
    );
  }
}

class AppScreenAboutSection extends StatelessWidget {
  const AppScreenAboutSection({super.key, required this.app});

  final PublicStoreApp app;

  String _normalize(String s) => s
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '')
      .trim();

  String get _shortText {
    final summary = _normalize(app.summary);
    if (summary.isNotEmpty) return summary;

    return 'No short description provided.';
  }

  String get _fullText {
    final description = _normalize(app.description);
    if (description.isNotEmpty) return description;

    final summary = _normalize(app.summary);
    if (summary.isNotEmpty) return summary;

    return '';
  }

  void _showFull(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final fullText = _fullText;

    showDialog(
      context: context,
      builder: (_) => AppAccentDialog(
        maxWidth: 400,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Text(
                  'About this app',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: colors.text,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: MarkdownBody(
                    data: fullText.isNotEmpty
                        ? fullText
                        : 'No description provided.',
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: markdownStyle(context),
                    onTapLink: (_, href, __) async {
                      if (href == null || href.trim().isEmpty) return;

                      final uri = Uri.tryParse(href.trim());
                      if (uri == null) return;

                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                ),
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
    final shortText = _shortText;

    return AppScreenSection(
      title: 'About this app',
      onHeaderTap: () => _showFull(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Text(
          shortText,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: colors.textSoft,
          ),
        ),
      ),
    );
  }
}