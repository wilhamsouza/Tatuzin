import 'package:flutter/material.dart';

import 'app_search_field.dart';

class AppSearchInput extends StatelessWidget {
  const AppSearchInput({
    super.key,
    this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.trailing,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppSearchField(
      controller: controller,
      hintText: hintText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onClear: onClear,
      trailing: trailing,
    );
  }
}
