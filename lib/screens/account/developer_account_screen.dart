import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/index_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';

class DeveloperAccountScreen extends StatefulWidget {
  const DeveloperAccountScreen({super.key});

  @override
  State<DeveloperAccountScreen> createState() => _DeveloperAccountScreenState();
}

class _DeveloperAccountScreenState extends State<DeveloperAccountScreen> {
  final StoreService _service = StoreService.instance;
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
  }

  @override
  void dispose() {
    _linkSub?.cancel();
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
          await _service.saveTokenFromAuthUri(uri);
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
      final token = await _service.getToken();
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

      final results = await Future.wait([
        _service.fetchMe(),
        IndexService.instance.fetchIndex(),
      ]);

      final account = results[0] as StoreAccount;
      final index = results[1] as StoreIndex;
      final apps = account.developerEnabled
          ? await _service.fetchDeveloperApps()
          : <DeveloperStoreApp>[];

      if (!mounted) return;
      setState(() {
        _account = account;
        _apps = apps;
        _publicApps = {for (final app in index.apps) app.packageName: app};
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
        _service.loginUri(),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        setState(() => _error = 'Could not open login page.');
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
      final uri = await _service.dashboardUri();
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _error = 'Could not open dashboard.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _openingDashboard = false);
    }
  }

  Future<void> _logout() async {
    await _service.clearToken();
    if (!mounted) return;
    setState(() {
      _account = null;
      _apps = const [];
      _publicApps = const {};
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Scaffold(
      backgroundColor: colors.backgroundFrost,
      body: RefreshIndicator(
        onRefresh: () => _load(showLoading: false),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _AccountHeader(
                account: _account,
                loading: _loading,
                openingLogin: _openingLogin,
                openingDashboard: _openingDashboard,
                onLogin: _login,
                onDashboard: _openDashboard,
                onLogout: _logout,
              ),
            ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
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
              const SliverToBoxAdapter(child: _LoadingBlock()),
            if (!_loading && _account != null) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(
                  title: 'Your apps',
                  count: _account!.developerEnabled ? _apps.length : null,
                ),
              ),
              if (!_account!.developerEnabled)
                SliverToBoxAdapter(
                  child: _MessageBlock(
                    message:
                    'Developer access is not enabled. Open the dashboard to agree to the developer terms.',
                    actionLabel: 'Open dashboard',
                    onAction: _openDashboard,
                  ),
                )
              else if (_apps.isEmpty)
                SliverToBoxAdapter(
                  child: _MessageBlock(
                    message:
                    'No apps registered yet. Open the dashboard to register your first app.',
                    actionLabel: 'Open dashboard',
                    onAction: _openDashboard,
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      final app = _apps[index];
                      return _DeveloperAppRow(
                        app: app,
                        publicApp: _publicApps[app.packageName],
                      );
                    },
                    childCount: _apps.length,
                  ),
                ),
            ],
            if (!_loading && _account == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                  child: Text(
                    'Sign in to manage developer submissions, review status, signing keys, and dashboard access.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.account,
    required this.loading,
    required this.openingLogin,
    required this.openingDashboard,
    required this.onLogin,
    required this.onDashboard,
    required this.onLogout,
  });

  final StoreAccount? account;
  final bool loading;
  final bool openingLogin;
  final bool openingDashboard;
  final VoidCallback onLogin;
  final VoidCallback onDashboard;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final signedIn = account != null;
    final displayName = account?.displayName.trim() ?? '';
    final email = account?.email.trim() ?? '';
    final label = displayName.isNotEmpty
        ? displayName
        : email.isNotEmpty
        ? email
        : signedIn
        ? 'Developer account'
        : 'Developer account';
    final initial = label.isNotEmpty ? label.substring(0, 1).toUpperCase() : 'S';

    final safeTop = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, safeTop + 18, 18, 22),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.iconBackground,
              shape: BoxShape.circle,
              border: Border.all(color: colors.border),
            ),
            child: loading
                ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.accentEnd,
              ),
            )
                : Text(
              signedIn ? initial : 'S',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: colors.text,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            signedIn ? label : 'Not signed in',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: colors.text,
            ),
          ),
          if (signedIn && email.isNotEmpty && displayName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              email,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
          ],
          const SizedBox(height: 20),
          if (signedIn)
            Row(
              children: [
                Expanded(
                  child: _GradientButton(
                    label: openingDashboard ? 'Opening...' : 'Dashboard',
                    onTap: openingDashboard ? null : onDashboard,
                  ),
                ),
                const SizedBox(width: 10),
                _PlainActionButton(label: 'Sign out', onTap: onLogout),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: _GradientButton(
                label: openingLogin ? 'Opening...' : 'Sign in',
                onTap: openingLogin ? null : onLogin,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
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
          if (count != null)
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textMuted,
              ),
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
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
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
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(label: 'Repository', value: app.repoUrl.isEmpty ? 'None' : app.repoUrl),
        _DetailRow(label: 'Repo verified', value: app.repoVerified ? 'Yes' : 'Not yet'),
        _DetailRow(
          label: 'Signing key',
          value: app.signingKeyHash.isEmpty ? 'Not locked yet' : app.signingKeyHash,
        ),
        if (publicApp != null && publicApp!.ratingCount > 0)
          _DetailRow(
            label: 'Rating',
            value: '${publicApp!.displayRating} ★ (${publicApp!.ratingCount})',
          ),
        if (detail.submissions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Submissions',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 8),
          ...detail.submissions.map((submission) {
            return _SubmissionRow(submission: submission);
          }),
        ],
      ],
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  const _SubmissionRow({required this.submission});

  final StoreSubmission submission;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              submission.versionName.isEmpty
                  ? 'Version ${submission.versionCode}'
                  : 'v${submission.versionName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
          ),
          Text(
            submission.statusLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
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

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: _GradientButton(label: actionLabel, onTap: onAction),
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

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 44, 18, 44),
      child: Center(child: CircularProgressIndicator(color: colors.accentEnd)),
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

Color _statusColor(BuildContext context, String status) {
  final colors = SafeHavenTheme.of(context);

  switch (status) {
    case 'live':
    case 'active':
      return colors.accentEnd;
    case 'rejected':
    case 'suspended':
    case 'removed':
      return const Color(0xFFE85D75);
    default:
      return colors.textMuted;
  }
}