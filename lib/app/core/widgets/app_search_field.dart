import 'package:flutter/material.dart';

import '../../theme/app_design_tokens.dart';
import 'app_input.dart';

class AppSearchField extends StatelessWidget {
  const AppSearchField({
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
    final layout = context.appLayout;
    final hasValue = controller?.text.trim().isNotEmpty ?? false;

    return Row(
      children: [
        Expanded(
          child: AppInput(
            controller: controller,
            textInputAction: TextInputAction.search,
            prefixIcon: Icon(Icons.search_rounded, size: layout.iconLg),
            hintText: hintText,
            suffixIcon: hasValue && onClear != null
                ? IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        if (trailing != null) ...[SizedBox(width: layout.space4), trailing!],
      ],
    );
  }
}
