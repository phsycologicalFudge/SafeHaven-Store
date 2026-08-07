import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/installer/update_mode_service.dart';
import '../../../services/locale/locale_manager.dart';
import '../../../services/logs/debug_log_service.dart';
import '../../../services/theme/theme_manager.dart';
import '../../../widgets/animated_tap.dart';
import '../../../widgets/settings_picker_dialog.dart';
import '../../apps/catalogue_screen/catalogue_navigation.dart';
import '../developer_account_screen.dart';
import 'package:safehaven/translations/app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _appVersion;
  UpdateMode _updateMode = UpdateMode.light;
  bool _debugEnabled = false;
  bool _hasLog = false;

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
    _loadUpdateMode();
    _loadDebugState();
  }

  Future<void> _loadVersionInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersion = '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appVersion = null;
      });
    }
  }

  Future<void> _loadUpdateMode() async {
    final mode = await UpdateModeService.getMode();
    if (!mounted) return;
    setState(() {
      _updateMode = mode;
    });
  }

  Future<void> _loadDebugState() async {
    final enabled = DebugLog.enabled;
    final has = await DebugLog.hasLog();
    if (!mounted) return;
    setState(() {
      _debugEnabled = enabled;
      _hasLog = has;
    });
  }

  Future<void> _setUpdateMode(UpdateMode mode) async {
    setState(() => _updateMode = mode);
    await UpdateModeService.setMode(mode);
  }

  Future<void> _setDebugEnabled(bool value) async {
    setState(() => _debugEnabled = value);
    await DebugLog.setEnabled(value);
  }

  Future<void> _shareLogs() async {
    await DebugLog.shareLog();
  }

  Future<void> _clearLogs() async {
    await DebugLog.clearLog();
    if (!mounted) return;
    setState(() => _hasLog = false);
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _updateModeSubtitle(BuildContext context, UpdateMode mode) {
    final l = AppLocalizations.of(context)!;
    return switch (mode) {
      UpdateMode.none => l.settingsUpdateOff,
      UpdateMode.light => l.settingsUpdateLight,
      UpdateMode.full => l.settingsUpdateFull,
    };
  }

  Future<void> _showUpdateModePicker() async {
    final selected = await SettingsPickerDialog.show<UpdateMode>(
      context: context,
      title: AppLocalizations.of(context)!.settingsFlawlessUpdates,
      children: [
        _UpdateModeOption(
          title: AppLocalizations.of(context)!.settingsUpdateOff,
          subtitle: AppLocalizations.of(context)!.settingsUpdateNoneDesc,
          selected: _updateMode == UpdateMode.none,
          onTap: () => Navigator.of(context).pop(UpdateMode.none),
        ),
        _UpdateModeOption(
          title: AppLocalizations.of(context)!.settingsUpdateLight,
          subtitle: AppLocalizations.of(context)!.settingsUpdateLightDesc,
          selected: _updateMode == UpdateMode.light,
          onTap: () => Navigator.of(context).pop(UpdateMode.light),
        ),
        _UpdateModeOption(
          title: AppLocalizations.of(context)!.settingsUpdateFull,
          subtitle: AppLocalizations.of(context)!.settingsUpdateFullDesc,
          selected: _updateMode == UpdateMode.full,
          onTap: () => Navigator.of(context).pop(UpdateMode.full),
        ),
      ],
    );

    if (selected != null && selected != _updateMode) {
      await _setUpdateMode(selected);
    }
  }

  String _languageSubtitle() {
    final locale = LocaleManager.instance.locale;
    if (locale == null) return 'System';
    return LocaleManager.instance.displayName(locale.languageCode);
  }

  Future<void> _showLanguagePicker() async {
    final lm = LocaleManager.instance;
    final locales = lm.supportedLocales;

    final selected = await SettingsPickerDialog.show<Locale?>(
      context: context,
      title: AppLocalizations.of(context)!.settingsLanguage,
      children: [
        _LanguageOption(
          title: 'System',
          selected: lm.locale == null,
          onTap: () => Navigator.of(context).pop(const Locale('system')),
        ),
        ...locales.map((l) => _LanguageOption(
          title: lm.displayName(l.languageCode),
          selected: lm.locale?.languageCode == l.languageCode,
          onTap: () => Navigator.of(context).pop(l),
        )),
      ],
    );

    if (selected == null) return;
    if (selected.languageCode == 'system') {
      await lm.setLocale(null);
    } else {
      await lm.setLocale(selected);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final themeManager = SafeHavenThemeManager.instance;

    return SafeArea(
      top: false,
      bottom: false,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: _SettingsSection(
              title: AppLocalizations.of(context)!.settingsOptions,
              children: [
                _SettingsActionTile(
                  icon: Icons.palette_rounded,
                  title: AppLocalizations.of(context)!.settingsTheme,
                  subtitle: AppLocalizations.of(context)!.settingsThemeSubtitle,
                  showArrow: false,
                  onTap: () => themeManager.toggle(),
                ),
                _SettingsActionTile(
                  icon: Icons.bolt_rounded,
                  title: AppLocalizations.of(context)!.settingsFlawlessUpdates,
                  subtitle: _updateModeSubtitle(context, _updateMode),
                  onTap: _showUpdateModePicker,
                ),
                _SettingsActionTile(
                  icon: Icons.language_rounded,
                  title: AppLocalizations.of(context)!.settingsLanguage,
                  subtitle: _languageSubtitle(),
                  onTap: _showLanguagePicker,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _SettingsSection(
              title: AppLocalizations.of(context)!.settingsDeveloper,
              children: [
                _SettingsActionTile(
                  icon: Icons.person_rounded,
                  title: AppLocalizations.of(context)!.settingsAccount,
                  subtitle: AppLocalizations.of(context)!.settingsAccountSubtitle,
                  onTap: () {
                    Navigator.of(context).push(
                      pushRoute(const DeveloperAccountScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _SettingsSection(
              title: AppLocalizations.of(context)!.settingsAbout,
              children: [
                _SettingsActionTile(
                  icon: Icons.help_outline_rounded,
                  title: AppLocalizations.of(context)!.settingsHowThisWorks,
                  subtitle: AppLocalizations.of(context)!.settingsHowThisWorksSubtitle,
                  showArrow: false,
                  onTap: () => _openLink('https://colourswift.com/safehaven/#overview'),
                ),
                _SettingsActionTile(
                  icon: Icons.upload_rounded,
                  title: AppLocalizations.of(context)!.settingsSubmitApp,
                  subtitle: AppLocalizations.of(context)!.settingsSubmitAppSubtitle,
                  showArrow: false,
                  onTap: () => _openLink('https://api.colourswift.com/submit'),
                ),
                _SettingsInfoTile(
                  icon: Icons.info_outline_rounded,
                  title: AppLocalizations.of(context)!.settingsVersion,
                  subtitle: _appVersion ?? AppLocalizations.of(context)!.settingsVersionLoading,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _SettingsSection(
              title: AppLocalizations.of(context)!.settingsDebugging,
              children: [
                _SettingsToggleTile(
                  icon: Icons.bug_report_rounded,
                  title: AppLocalizations.of(context)!.settingsDebugLogging,
                  subtitle: '/storage/emulated/0/Documents',
                  value: _debugEnabled,
                  onChanged: _setDebugEnabled,
                ),
                if (_hasLog) ...[
                  _SettingsActionTile(
                    icon: Icons.share_rounded,
                    title: AppLocalizations.of(context)!.settingsShareLog,
                    subtitle: AppLocalizations.of(context)!.settingsShareLogSubtitle,
                    showArrow: false,
                    onTap: _shareLogs,
                  ),
                  _SettingsActionTile(
                    icon: Icons.delete_outline_rounded,
                    title: AppLocalizations.of(context)!.settingsClearLog,
                    subtitle: AppLocalizations.of(context)!.settingsClearLogSubtitle,
                    showArrow: false,
                    onTap: _clearLogs,
                  ),
                ],
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    final List<Widget> dividedChildren = [];
    for (int i = 0; i < children.length; i++) {
      dividedChildren.add(children[i]);
      if (i < children.length - 1) {
        dividedChildren.add(
          Padding(
            padding: const EdgeInsets.only(left: 74, right: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color: colors.border.withOpacity(0.6),
            ),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 10),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
                color: colors.textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Column(
                children: dividedChildren,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.showArrow = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.textMuted, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showArrow)
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: colors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggleTile extends StatelessWidget {
  const _SettingsToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 0,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.textMuted, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.textSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Transform.scale(
              scale: 0.78,
              alignment: Alignment.centerRight,
              child: Switch(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeTrackColor: colors.text,
                activeColor: colors.surface,
                inactiveTrackColor: colors.border,
                inactiveThumbColor: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsInfoTile extends StatelessWidget {
  const _SettingsInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.textMuted, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.textSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateModeOption extends StatelessWidget {
  const _UpdateModeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? colors.text : colors.textMuted,
            ),
            const SizedBox(width: 14),
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
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.3,
                      color: colors.textSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return AnimatedTap(
      borderRadius: 0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20,
              color: selected ? colors.text : colors.textMuted,
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}