import 'package:flutter/material.dart';

enum AppFeedbackTone { info, success, error }

abstract final class AppFeedback {
  static void info(BuildContext context, String message) {
    _show(context, message: message, tone: AppFeedbackTone.info);
  }

  static void success(BuildContext context, String message) {
    _show(context, message: message, tone: AppFeedbackTone.success);
  }

  static void error(BuildContext context, String message) {
    _show(context, message: message, tone: AppFeedbackTone.error);
  }

  static void _show(
    BuildContext context, {
    required String message,
    required AppFeedbackTone tone,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final icon = switch (tone) {
      AppFeedbackTone.info => Icons.info_outline_rounded,
      AppFeedbackTone.success => Icons.check_circle_outline_rounded,
      AppFeedbackTone.error => Icons.error_outline_rounded,
    };
    final iconColor = switch (tone) {
      AppFeedbackTone.info => colorScheme.secondary,
      AppFeedbackTone.success => colorScheme.tertiary,
      AppFeedbackTone.error => colorScheme.error,
    };

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }
}
