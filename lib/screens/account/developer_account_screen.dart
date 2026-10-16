import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/index_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';
import '../../services/developer_profile_service.dart';
import '../../widgets/animated_tap.dart';
import '../../widgets/profile_edit_dialog.dart';
import '../../widgets/refresh/pull_to_refresh.dart';
import '../../widgets/settings_picker_dialog.dart';
import '../apps/catalogue_screen/widgets/catalogue_shared_widgets.dart';
import '../home/top_banner.dart';
import 'package:safehaven/translations/app_localizations.dart';

class DeveloperAccountScreen extends StatefulWidget {
  const DeveloperAccountScreen({super.key});

  @override
  State<DeveloperAccountScreen> createState() => _DeveloperAccountScreenState();
}

class _DeveloperAccountScreenState extends State<DeveloperAccountScreen> {
  final StoreService _service = StoreService.instance;
  final StoreAuthService _auth = StoreAuthService.instance;
  final AppLinks _appLinks = AppLinks();

  StreamSubscription<Uri>? _linkSub;

  bool _loading = true;
  bool _openingLogin = false;
  bool _openingDashboard = false;
  String? _error;
  StoreAccount? _account;
  List<DeveloperStoreApp> _apps = const [];
  Map<String, PublicStoreApp> _publicApps = const {};

  @override
  void initState() {
    super.initState();
    _listenForAuthLinks();
    _load(showLoading: true);
    DeveloperProfileService.instance.ensureLoaded();
    DeveloperProfileService.instance.addListener(_onProfileChanged);
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    DeveloperProfileService.instance.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _listenForAuthLinks() {
    _linkSub = _appLinks.uriLinkStream.listen(
          (uri) async {
        if (uri.scheme != 'safehaven') return;
        if (uri.host != 'auth') return;

        setState(() {
          _loading = true;
          _error = null;
        });

        try {
          await _auth.saveTokenFromAuthUri(uri);
          await _load(showLoading: false);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = e.toString();
          });
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      },
    );
  }

  Future<void> _load({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }

    try {
      final token = await _auth.getToken();
      if (token == null) {
        if (!mounted) return;
        setState(() {
          _account = null;
          _apps = const [];
          _publicApps = const {};
          _loading = false;
        });
        return;
      }

      final account = await _auth.fetchMe();
      final apps = account.developerEnabled
          ? await _service.fetchDeveloperApps()
          : <DeveloperStoreApp>[];
      final publicApps = await IndexService.instance.apps([for (final app in apps) app.packageName]);

      if (!mounted) return;
      setState(() {
        _account = account;
        _apps = apps;
        _publicApps = {for (final app in publicApps) app.packageName: app};
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _account = null;
        _apps = const [];
        _publicApps = const {};
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _openingLogin = true;
      _error = null;
    });

    try {
      final ok = await launchUrl(
        _auth.loginUri(),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        setState(() => _error = AppLocalizations.of(context)!.devCouldNotOpenLogin);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _openingLogin = false);
    }
  }

  Future<void> _openDashboard() async {
    setState(() {
      _openingDashboard = true;
      _error = null;
    });

    try {
      final uri = await _auth.dashboardUri();
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _error = AppLocalizations.of(context)!.devCouldNotOpenDashboard);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _openingDashboard = false);
    }
  }

  Future<void> _logout() async {
    await _auth.clearToken();
    if (!mounted) return;
    setState(() {
      _account = null;
      _apps = const [];
      _publicApps = const {};
      _error = null;
    });
  }

  void _editProfile() {
    ProfileEditDialog.show(
      context: context,
      currentName: DeveloperProfileService.instance.displayName,
      fallbackName: _account?.displayName.trim() ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final l = AppLocalizations.of(context)!;
    final profile = DeveloperProfileService.instance;

    return Scaffold(
      backgroundColor: colors.backgroundFrost,
      appBar: TopBanner.defaultScreen(
        title: l.settingsAccount,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: AnimatedTap(
              borderRadius: 99,
              scale: 0.92,
              onTap: _editProfile,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.info_outline_rounded, size: 25, color: colors.textMuted),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: PullRefresh(
          onRefresh: () => _load(showLoading: false),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _AccountHeader(
                  account: _account,
                  openingLogin: _openingLogin,
                  onLogin: _login,
                  onLogout: _logout,
                  name: profile.name,
                  avatarFile: profile.avatarFile,
                  onEditProfile: _editProfile,
                ),
              ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFE85D75),
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              if (_loading)
                const SliverToBoxAdapter(child: CatalogueLoadingBlock())
              else if (_account == null)
                SliverFillRemaining(hasScrollBody: false, child: _EmptyState(message: l.accountSignInToView, showIcon: false))
              else ...[
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: l.devYourApps,
                    action: _openingDashboard ? l.devOpening : l.devDashboard,
                    onAction: _openingDashboard ? null : _openDashboard,
                  ),
                ),
                if (_apps.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _EmptyState(message: l.accountEmpty))
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 28),
                    sliver: SliverList.builder(
                      itemCount: _apps.length,
                      itemBuilder: (context, index) => _DeveloperAppRow(
                        app: _apps[index],
                        publicApp: _publicApps[_apps[index].packageName],
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.account,
    required this.openingLogin,
    required this.onLogin,
    required this.onLogout,
    required this.name,
    required this.avatarFile,
    required this.onEditProfile,
  });

  final StoreAccount? account;
  final bool openingLogin;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final String name;
  final File? avatarFile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final l = AppLocalizations.of(context)!;
    final signedIn = account != null;
    final email = account?.email.trim() ?? '';
    final accountName = account?.displayName.trim() ?? '';
    final label = name.isNotEmpty
        ? name
        : accountName.isNotEmpty
            ? accountName
            : l.settingsAccount;
    final subtitle = signedIn ? email : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 22),
      child: Row(
        children: [
          AnimatedTap(
            borderRadius: 40,
            onTap: onEditProfile,
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.iconBackground,
                shape: BoxShape.circle,
                border: Border.all(color: colors.border),
                image: avatarFile != null
                    ? DecorationImage(image: FileImage(avatarFile!), fit: BoxFit.cover)
                    : null,
              ),
              child: avatarFile != null
                  ? null
                  : Text(
                      label.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: colors.text,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: colors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          signedIn
              ? _PlainActionButton(label: l.devSignOut, onTap: onLogout)
              : _GradientButton(
                  label: openingLogin ? l.devOpening : l.devSignIn,
                  onTap: openingLogin ? null : onLogin,
                ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action, required this.onAction});

  final String title;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 14, 6),
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
          AnimatedTap(
            borderRadius: 8,
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    action,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.accentEnd,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.north_east_rounded, size: 13, color: colors.accentEnd),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.showIcon = true});

  final String message;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showIcon) ...[
            Icon(Icons.apps_rounded, size: 38, color: colors.textMuted),
            const SizedBox(height: 12),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _DeveloperAppRow extends StatefulWidget {
  const _DeveloperAppRow({required this.app, required this.publicApp});

  final DeveloperStoreApp app;
  final PublicStoreApp? publicApp;

  @override
  State<_DeveloperAppRow> createState() => _DeveloperAppRowState();
}

class _DeveloperAppRowState extends State<_DeveloperAppRow> {
  final StoreService _service = StoreService.instance;

  bool _expanded = false;
  bool _loading = false;
  String? _error;
  DeveloperAppDetail? _detail;

  Future<void> _loadDetail() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await _service.fetchDeveloperApp(widget.app.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (!_expanded || _detail != null) return;
    _loadDetail();
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final app = widget.app;
    final publicApp = widget.publicApp;

    return Column(
      children: [
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
            child: Row(
              children: [
                _AppIcon(iconUrl: publicApp?.iconUrl ?? '', size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
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
                      const SizedBox(height: 3),
                      Text(
                        app.packageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textSoft,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${app.statusLabel} · ${app.trustLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox.shrink()
              : Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            child: _loading
                ? LinearProgressIndicator(
              minHeight: 2,
              color: colors.textMuted,
              backgroundColor: colors.border,
            )
                : _error != null
                ? Text(
              _error!,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFFE85D75),
                height: 1.35,
              ),
            )
                : _detail != null
                ? _DeveloperAppDetail(
              app: app,
              detail: _detail!,
              publicApp: publicApp,
            )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class _DeveloperAppDetail extends StatelessWidget {
  const _DeveloperAppDetail({
    required this.app,
    required this.detail,
    required this.publicApp,
  });

  final DeveloperStoreApp app;
  final DeveloperAppDetail detail;
  final PublicStoreApp? publicApp;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final latestLive = _latestLiveSubmission(detail.submissions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SourceRow(
          label: AppLocalizations.of(context)!.devRepository,
          repoUrl: app.repoUrl,
        ),
        _DetailRow(label: AppLocalizations.of(context)!.devRepoVerified, value: app.repoVerified ? AppLocalizations.of(context)!.devRepoVerifiedYes : AppLocalizations.of(context)!.devRepoVerifiedNo),
        if (app.signingKeyHash.isNotEmpty)
          _CopySigningKeyRow(
            label: AppLocalizations.of(context)!.devSigningKey,
            signingKeyHash: app.signingKeyHash,
          )
        else
          _DetailRow(
            label: AppLocalizations.of(context)!.devSigningKey,
            value: AppLocalizations.of(context)!.devSigningKeyNone,
          ),
        if (publicApp != null && publicApp!.ratingCount > 0)
          _DetailRow(
            label: AppLocalizations.of(context)!.appMetaRating,
            value: '${publicApp!.displayRating} ★ (${publicApp!.ratingCount})',
          ),
        if (detail.submissions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            AppLocalizations.of(context)!.devSubmissions,
            style: TextStyle(
              fontSize: 13.5,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          ..._visibleSubmissions(detail.submissions, latestLive).map((submission) {
            return _SubmissionRow(
              submission: submission,
              statusOverride: _statusOverride(context, submission, latestLive),
            );
          }),
          if (detail.submissions.length > 3)
            _SeeAllHistoryButton(
              onTap: () => _showSubmissionHistory(
                context,
                detail.submissions,
                latestLive,
              ),
            ),
        ],
      ],
    );
  }
}

StoreSubmission? _latestLiveSubmission(List<StoreSubmission> submissions) {
  StoreSubmission? latest;
  for (final s in submissions) {
    if (s.statusLabel.toLowerCase() != 'live') continue;
    if (latest == null || s.versionCode > latest.versionCode) {
      latest = s;
    }
  }
  return latest;
}

bool _isSupersededLive(StoreSubmission submission, StoreSubmission? latestLive) {
  if (submission.statusLabel.toLowerCase() != 'live') return false;
  if (latestLive == null) return false;
  return submission.versionCode != latestLive.versionCode;
}

String? _statusOverride(
    BuildContext context,
    StoreSubmission submission,
    StoreSubmission? latestLive,
    ) {
  if (!_isSupersededLive(submission, latestLive)) return null;
  return AppLocalizations.of(context)!.devStatusInactive;
}

int _effectiveStatusOrder(StoreSubmission submission, StoreSubmission? latestLive) {
  if (_isSupersededLive(submission, latestLive)) return 2;

  switch (submission.statusLabel.toLowerCase()) {
    case 'live':
      return 0;
    case 'rejected':
      return 1;
    case 'inactive':
      return 2;
    default:
      return 3;
  }
}

List<StoreSubmission> _visibleSubmissions(
    List<StoreSubmission> submissions,
    StoreSubmission? latestLive,
    ) {
  final filtered = submissions.where((s) {
    final status = s.statusLabel.toLowerCase();
    return status == 'live' || status == 'rejected' || status == 'inactive';
  }).toList();

  filtered.sort(
        (a, b) => _effectiveStatusOrder(a, latestLive)
        .compareTo(_effectiveStatusOrder(b, latestLive)),
  );

  return filtered.take(3).toList();
}

Future<void> _showSubmissionHistory(
    BuildContext context,
    List<StoreSubmission> submissions,
    StoreSubmission? latestLive,
    ) {
  return SettingsPickerDialog.show<void>(
    context: context,
    title: AppLocalizations.of(context)!.devSubmissions,
    children: [_SubmissionHistory(submissions: submissions, latestLive: latestLive)],
  );
}

String _versionLabel(BuildContext context, StoreSubmission submission) {
  final raw = submission.versionName;
  final name = raw.startsWith('v') || raw.startsWith('V') ? raw.substring(1) : raw;
  return name.isEmpty
      ? AppLocalizations.of(context)!.devVersionCode(submission.versionCode.toString())
      : 'v$name';
}

class _SubmissionHistory extends StatelessWidget {
  const _SubmissionHistory({required this.submissions, required this.latestLive});

  final List<StoreSubmission> submissions;
  final StoreSubmission? latestLive;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final live = <StoreSubmission>[];
    final inactive = <StoreSubmission>[];
    final rejected = <StoreSubmission>[];
    for (final s in submissions) {
      final status = s.statusLabel.toLowerCase();
      if (status == 'rejected') {
        rejected.add(s);
      } else if (status == 'inactive' || _isSupersededLive(s, latestLive)) {
        inactive.add(s);
      } else if (status == 'live') {
        live.add(s);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _HistoryColumn(title: l.devStatusLive, items: live)),
          Expanded(child: _HistoryColumn(title: l.devStatusInactive, items: inactive)),
          Expanded(child: _HistoryColumn(title: l.devStatusRejected, items: rejected)),
        ],
      ),
    );
  }
}

class _HistoryColumn extends StatelessWidget {
  const _HistoryColumn({required this.title, required this.items});

  final String title;
  final List<StoreSubmission> items;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final sorted = [...items]..sort((a, b) => b.versionCode.compareTo(a.versionCode));

    return Column(
      children: [
        Text(title, style: TextStyle(fontSize: 12.5, color: colors.textMuted)),
        const SizedBox(height: 8),
        if (sorted.isEmpty)
          Text('-', style: TextStyle(fontSize: 13, color: colors.textMuted))
        else
          for (final s in sorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _versionLabel(context, s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.text),
              ),
            ),
      ],
    );
  }
}

class _SeeAllHistoryButton extends StatelessWidget {
  const _SeeAllHistoryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 8,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)!.devSeeAllHistory,
              style: TextStyle(
                fontSize: 12.5,
                color: colors.accentEnd,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 11,
              color: colors.accentEnd,
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  const _SubmissionRow({required this.submission, this.statusOverride});

  final StoreSubmission submission;
  final String? statusOverride;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _versionLabel(context, submission),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: colors.text,
              ),
            ),
          ),
          Text(
            statusOverride ?? submission.statusLabel,
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: colors.textSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _repoSourceLabel(BuildContext context, String repoUrl) {
  if (repoUrl.isEmpty) return AppLocalizations.of(context)!.appMetaNone;

  final uri = Uri.tryParse(repoUrl);
  final host = uri?.host.toLowerCase() ?? '';

  if (host.contains('github')) return 'GitHub';
  if (host.contains('gitlab')) return 'GitLab';
  if (host.contains('codeberg')) return 'Codeberg';
  if (host.isEmpty) return repoUrl;
  return host;
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.label, required this.repoUrl});

  final String label;
  final String repoUrl;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(repoUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final hasRepo = repoUrl.isNotEmpty;
    final sourceLabel = _repoSourceLabel(context, repoUrl);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: colors.textMuted),
            ),
          ),
          Expanded(
            child: hasRepo
                ? Align(
              alignment: Alignment.centerRight,
              child: AnimatedTap(
                borderRadius: 6,
                onTap: () => _open(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sourceLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.accentEnd,
                          decoration: TextDecoration.underline,
                          decorationColor: colors.accentEnd,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.north_east_rounded, size: 12, color: colors.accentEnd),
                    ],
                  ),
                ),
              ),
            )
                : Text(
              sourceLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: colors.textSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopySigningKeyRow extends StatefulWidget {
  const _CopySigningKeyRow({required this.label, required this.signingKeyHash});

  final String label;
  final String signingKeyHash;

  @override
  State<_CopySigningKeyRow> createState() => _CopySigningKeyRowState();
}

class _CopySigningKeyRowState extends State<_CopySigningKeyRow> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.signingKeyHash));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              widget.label,
              style: TextStyle(fontSize: 12.5, color: colors.textMuted),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedTap(
                borderRadius: 6,
                onTap: _copy,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _copied
                            ? AppLocalizations.of(context)!.devSigningKeyCopied
                            : AppLocalizations.of(context)!.devSigningKeyTapToCopy,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _copied ? colors.accentEnd : colors.textSoft,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 13,
                        color: _copied ? colors.accentEnd : colors.textMuted,
                      ),
                    ],
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

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final enabled = onTap != null;

    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: enabled ? colors.accentGradient : null,
          color: enabled ? null : colors.surfaceSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled ? Colors.transparent : colors.border,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: enabled ? colors.buttonText : colors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainActionButton extends StatelessWidget {
  const _PlainActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: colors.textSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.iconUrl, required this.size});

  final String iconUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.iconBackground,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: iconUrl.isEmpty
          ? Icon(
        Icons.android_rounded,
        size: size * 0.42,
        color: colors.textMuted,
      )
          : CachedNetworkImage(
        imageUrl: iconUrl,
        fit: BoxFit.cover,
        memCacheWidth: (size * 2).toInt(),
        memCacheHeight: (size * 2).toInt(),
        fadeInDuration: const Duration(milliseconds: 120),
        filterQuality: FilterQuality.medium,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => Icon(
          Icons.android_rounded,
          size: size * 0.42,
          color: colors.textMuted,
        ),
      ),
    );
  }
}
