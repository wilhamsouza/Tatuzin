import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';

class AppSeparator extends StatelessWidget {
  const AppSeparator({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      endIndent: endIndent,
      color: context.appColors.outlineSoft,
    );
  }
}
