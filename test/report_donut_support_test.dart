import 'dart:ui';

import 'package:erp_pdv_app/modules/relatorios/data/support/report_donut_support.dart';
import 'package:erp_pdv_app/modules/relatorios/domain/entities/report_donut_slice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReportDonutSupport', () {
    test('calculates percentages with up to one decimal place', () {
      final slices = ReportDonutSupport.normalize(const [
        ReportDonutSlice(
          label: 'Pix',
          value: 2,
          percentage: 0,
          color: Color(0xFF166534),
          formattedValue: '',
        ),
        ReportDonutSlice(
          label: 'Cartao',
          value: 1,
          percentage: 0,
          color: Color(0xFF7B5234),
          formattedValue: '',
        ),
      ], formatValue: (value) => value.toStringAsFixed(0));

      expect(slices, hasLength(2));
      expect(slices.first.percentage, 66.7);
      expect(slices.last.percentage, 33.3);
      expect(
        ReportDonutSupport.formatPercentage(slices.last.percentage),
        '33.3%',
      );
    });

    test(
      'groups overflow into Outros and keeps at most five visible slices',
      () {
        final slices = ReportDonutSupport.normalize(const [
          ReportDonutSlice(
            label: 'A',
            value: 50,
            percentage: 0,
            color: Color(0xFF111111),
            formattedValue: '',
          ),
          ReportDonutSlice(
            label: 'B',
            value: 20,
            percentage: 0,
            color: Color(0xFF222222),
            formattedValue: '',
          ),
          ReportDonutSlice(
            label: 'C',
            value: 10,
            percentage: 0,
            color: Color(0xFF333333),
            formattedValue: '',
          ),
          ReportDonutSlice(
            label: 'D',
            value: 8,
            percentage: 0,
            color: Color(0xFF444444),
            formattedValue: '',
          ),
          ReportDonutSlice(
            label: 'E',
            value: 6,
            percentage: 0,
            color: Color(0xFF555555),
            formattedValue: '',
          ),
          ReportDonutSlice(
            label: 'F',
            value: 4,
            percentage: 0,
            color: Color(0xFF666666),
            formattedValue: '',
          ),
        ], formatValue: (value) => value.toStringAsFixed(0));

        expect(slices, hasLength(5));
        expect(slices.last.label, 'Outros');
        expect(slices.last.value, 10);
        expect(slices.last.formattedValue, '10');
      },
    );
  });
}
