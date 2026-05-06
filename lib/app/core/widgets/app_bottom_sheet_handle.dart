import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

class AppBottomSheetHandle extends StatelessWidget {
  const AppBottomSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Center(
      child: Container(
        width: 44,
        height: 4,
        margin: EdgeInsets.only(bottom: layout.space6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(layout.radiusPill),
        ),
      ),
    );
  }
}
