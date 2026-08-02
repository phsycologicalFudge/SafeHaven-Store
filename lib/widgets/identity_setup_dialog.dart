import 'package:flutter/material.dart';
import '../services/device_identity_service.dart';
import '../services/theme/theme_manager.dart';
import 'package:safehaven/translations/app_localizations.dart';

class IdentitySetupDialog extends StatefulWidget {
  const IdentitySetupDialog({super.key});

  static Future<void> showIfNeeded(BuildContext context) async {
    final ready = await DeviceIdentityService.instance.isSetUp();
    if (ready) return;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const IdentitySetupDialog(),
    );
  }

  @override
  State<IdentitySetupDialog> createState() => _IdentitySetupDialogState();
}

class _IdentitySetupDialogState extends State<IdentitySetupDialog> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nickname = _controller.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = AppLocalizations.of(context)!.nicknameEmpty);
      return;
    }
    if (nickname.length < 2) {
      setState(() => _error = AppLocalizations.of(context)!.nicknameTooShort);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await DeviceIdentityService.instance.setupIdentity(nickname);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      setState(() {
        _saving = false;
        _error = AppLocalizations.of(context)!.somethingWentWrong;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.nicknameTitle,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.nicknameSubtitle,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSoft,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 24,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.nicknameHint,
                counterText: '',
                filled: true,
                fillColor: colors.surfaceSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: colors.textSoft),
                ),
                hintStyle: TextStyle(color: colors.textMuted),
              ),
              style: TextStyle(fontSize: 15, color: colors.text),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFFFCA5A5),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _saving ? null : colors.accentGradient,
                  color: _saving ? colors.surfaceSoft : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _saving ? null : _save,
                    child: Center(
                      child: Text(
                        _saving ? AppLocalizations.of(context)!.nicknameSaving : AppLocalizations.of(context)!.nicknameContinue,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _saving ? colors.textMuted : colors.buttonText,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}