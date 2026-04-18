import 'package:flutter/material.dart';

import '../../../../app/core/widgets/app_state_card.dart';

class ReportEmptyState extends StatelessWidget {
  const ReportEmptyState({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppStateCard(title: title, message: message, compact: true);
  }
}
