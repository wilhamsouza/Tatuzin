import 'dart:ui';

class ReportDonutSlice {
  const ReportDonutSlice({
    required this.label,
    required this.value,
    required this.percentage,
    required this.color,
    required this.formattedValue,
  });

  final String label;
  final double value;
  final double percentage;
  final Color color;
  final String formattedValue;

  ReportDonutSlice copyWith({
    String? label,
    double? value,
    double? percentage,
    Color? color,
    String? formattedValue,
  }) {
    return ReportDonutSlice(
      label: label ?? this.label,
      value: value ?? this.value,
      percentage: percentage ?? this.percentage,
      color: color ?? this.color,
      formattedValue: formattedValue ?? this.formattedValue,
    );
  }
}
