import 'package:flutter/material.dart';
import '../../services/index_service.dart';
import '../../services/notification_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';
import '../../widgets/animated_tap.dart';
import '../apps/app_screen/app_screen.dart';
import '../apps/catalogue_screen/catalogue_navigation.dart';
import '../apps/catalogue_screen/widgets/catalogue_app_icons.dart';
import '../home/top_banner.dart';
import 'package:safehaven/translations/app_localizations.dart';

enum _Bucket { today, yesterday, lastWeek, lastMonth, older }

_Bucket _bucketOf(DateTime at) {
  final days = DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(at)).inDays;
  if (days <= 0) return _Bucket.today;
  if (days == 1) return _Bucket.yesterday;
  if (days <= 7) return _Bucket.lastWeek;
  if (days <= 31) return _Bucket.lastMonth;
  return _Bucket.older;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _service = NotificationService.instance;
  List<AppNotification>? _items;
  Map<String, PublicStoreApp> _apps = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _service.markAllRead();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await _service.load();
    final packages = {for (final n in items) n.packageName}.toList();
    final apps = await IndexService.instance.apps(packages).catchError((_) => <PublicStoreApp>[]);
    if (!mounted) return;
    setState(() {
      _items = items;
      _apps = {for (final app in apps) app.packageName: app};
    });
  }

  Future<void> _delete(AppNotification n) async {
    await _service.delete(n.id);
    if (mounted) setState(() => _items = _service.items);
  }

  void _open(AppNotification n) {
    final app = _apps[n.packageName];
    if (app != null) Navigator.of(context).push(pushRoute(AppScreen(app: app)));
  }

  String _label(AppLocalizations l, _Bucket bucket) => switch (bucket) {
        _Bucket.today => l.notificationsToday,
        _Bucket.yesterday => l.notificationsYesterday,
        _Bucket.lastWeek => l.notificationsLastWeek,
        _Bucket.lastMonth => l.notificationsLastMonth,
        _Bucket.older => l.notificationsOlder,
      };

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final l = AppLocalizations.of(context)!;
    final items = _items;
    final grouped = <_Bucket, List<AppNotification>>{};
    for (final n in items ?? const <AppNotification>[]) {
      grouped.putIfAbsent(_bucketOf(n.at), () => []).add(n);
    }

    return Scaffold(
      backgroundColor: colors.backgroundFrost,
      appBar: TopBanner.defaultScreen(title: l.notificationsTitle),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            if (items == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator(color: colors.accentEnd)),
                ),
              )
            else if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 0),
                  child: Column(
                    children: [
                      Icon(Icons.notifications_none_rounded, size: 40, color: colors.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        l.notificationsEmpty,
                        style: TextStyle(fontSize: 14, color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final bucket in _Bucket.values)
                if (grouped[bucket] case final group?) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                      child: Text(
                        _label(l, bucket),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: group.length,
                    itemBuilder: (context, i) => _NotificationRow(
                      key: ValueKey(group[i].id),
                      notification: group[i],
                      app: _apps[group[i].packageName],
                      today: bucket == _Bucket.today || bucket == _Bucket.yesterday,
                      onTap: () => _open(group[i]),
                      onDelete: () => _delete(group[i]),
                    ),
                  ),
                ],
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
          ],
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    super.key,
    required this.notification,
    required this.app,
    required this.today,
    required this.onTap,
    required this.onDelete,
  });

  final AppNotification notification;
  final PublicStoreApp? app;
  final bool today;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final l = AppLocalizations.of(context)!;
    final material = MaterialLocalizations.of(context);
    final n = notification;
    final body = switch (n.kind) {
      NotificationKind.updated => l.notificationUpdated,
      NotificationKind.updateFailed => l.notificationUpdateFailed,
      NotificationKind.selfUpdate => l.notificationSelfUpdate(n.detail),
    };
    final time = today
        ? material.formatTimeOfDay(TimeOfDay.fromDateTime(n.at))
        : material.formatShortMonthDay(n.at);
    final fallbackIcon = switch (n.kind) {
      NotificationKind.updateFailed => Icons.error_outline_rounded,
      _ => Icons.system_update_rounded,
    };

    return AnimatedTap(
      borderRadius: 16,
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                app != null
                    ? CatalogueRawAppIcon(app: app!, size: 44, radius: 12)
                    : Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.iconBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(fallbackIcon, color: colors.textMuted),
                      ),
                if (!n.read)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: colors.accentStart,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.backgroundFrost, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: n.read ? FontWeight.w600 : FontWeight.w800,
                            color: colors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(time, style: TextStyle(fontSize: 12, color: colors.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.3, color: colors.textMuted),
                  ),
                ],
              ),
            ),
            PopupMenuButton<int>(
              icon: Icon(Icons.more_vert_rounded, color: colors.textMuted),
              onSelected: (_) => onDelete(),
              itemBuilder: (_) => [
                PopupMenuItem<int>(value: 0, child: Text(l.notificationsDelete)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}