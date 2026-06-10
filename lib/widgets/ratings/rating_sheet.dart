import 'package:flutter/material.dart';
import '../../screens/apps/app_screen/app_screen_helpers.dart';
import '../../services/device_identity_service.dart';
import '../../services/ratings/rating_service.dart';
import '../../services/store_service.dart';
import '../../services/theme/theme_manager.dart';
import '../identity_setup_dialog.dart';

class RatingSheet extends StatefulWidget {
  const RatingSheet({super.key, required this.app});

  final PublicStoreApp app;

  static Future<void> show(BuildContext context, PublicStoreApp app) {
    return showDialog<void>(
      context: context,
      builder: (_) => AppAccentDialog(
        child: RatingSheet(app: app),
      ),
    );
  }

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  int _selected = 0;
  bool _submitting = false;
  RatingResult? _result;

  Future<void> _submit() async {
    if (_selected == 0 || _submitting) return;

    final isSetUp = await DeviceIdentityService.instance.isSetUp();
    if (!isSetUp) {
      if (mounted) await IdentitySetupDialog.showIfNeeded(context);
      return;
    }

    setState(() => _submitting = true);

    final result = await RatingService.instance.submitRating(
      packageName: widget.app.packageName,
      rating: _selected,
    );

    if (mounted) {
      setState(() {
        _submitting = false;
        _result = result;
      });
    }

    if (result == RatingResult.ok && mounted) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);
    final canSubmit = _selected > 0 && !_submitting && _result == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.app.name,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a star to rate this app',
            style: TextStyle(fontSize: 13, color: colors.textSoft),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              final filled = star <= _selected;
              return GestureDetector(
                onTap: _result == null
                    ? () => setState(() => _selected = star)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 44,
                    color: filled ? colors.accentEnd : colors.textSoft,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                _resultMessage(_result!),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _result == RatingResult.ok
                      ? const Color(0xFF86EFAC)
                      : const Color(0xFFFCA5A5),
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: canSubmit ? colors.accentGradient : null,
                color: canSubmit ? null : colors.surfaceSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: canSubmit ? _submit : null,
                  child: Center(
                    child: Text(
                      _submitting ? 'Submitting...' : 'Submit rating',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: canSubmit ? colors.buttonText : colors.textMuted,
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

  String _resultMessage(RatingResult result) {
    switch (result) {
      case RatingResult.ok:
        return 'Thanks for your rating!';
      case RatingResult.alreadyRated:
        return "You've already rated this app.";
      case RatingResult.rateLimited:
        return 'Too many ratings submitted. Try again later.';
      case RatingResult.notFound:
        return 'App not found.';
      case RatingResult.error:
        return 'Something went wrong. Please try again.';
    }
  }
}
