import 'package:flutter/material.dart';
import '../../services/theme/theme_manager.dart';
import '../animated_tap.dart';

class UpdateFailure {
  const UpdateFailure({
    required this.appName,
    required this.reason,
    this.blockedBySafeHaven = false,
  });

  final String appName;
  final String reason;
  final bool blockedBySafeHaven;
}

class UpdateResultsDialog extends StatelessWidget {
  const UpdateResultsDialog({
    super.key,
    required this.started,
    required this.failed,
  });

  final int started;
  final List<UpdateFailure> failed;

  static Future<void> show(
      BuildContext context, {
        required int started,
        required List<UpdateFailure> failed,
      }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => UpdateResultsDialog(started: started, failed: failed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380, maxHeight: 480),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Some apps couldn\'t be updated',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Install through SafeHaven to update',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: colors.textSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(height: 0.5, color: colors.border),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < failed.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          _FailureRow(failure: failed[i]),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: colors.border),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: AnimatedTap(
                      borderRadius: 12,
                      scale: 0.97,
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.border),
                        ),
                        child: Text(
                          'Dismiss',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    ),
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

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.failure});

  final UpdateFailure failure;

  @override
  Widget build(BuildContext context) {
    final colors = SafeHavenTheme.of(context);

    if (failure.blockedBySafeHaven) {
      return Text(
        failure.appName,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colors.text,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          failure.appName,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          failure.reason,
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}