import 'package:flutter/material.dart';

class ReportChartCenterLabel extends StatelessWidget {
  const ReportChartCenterLabel({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth =
              constraints.maxWidth.isFinite && constraints.maxWidth > 0
              ? constraints.maxWidth
              : 88.0;
          final labelFontSize = (availableWidth * 0.14).clamp(10.0, 12.0);
          final valueFontSize = (availableWidth * 0.24).clamp(14.0, 18.0);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: labelFontSize,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: availableWidth < 84 ? 2 : 4),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    textAlign: TextAlign.center,
                    softWrap: false,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: valueFontSize,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
