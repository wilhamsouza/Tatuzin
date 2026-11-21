import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/owner_models.dart';
import 'owner_formatters.dart';

/// Plots only the sales series returned by the owner API. No inferred profit.
class OwnerSalesChart extends StatelessWidget {
  const OwnerSalesChart({super.key, required this.points});
  final List<OwnerSalesSeriesPoint> points;

  @override
  Widget build(BuildContext context) {
    final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Sem vendas no período. As vendas sincronizadas aparecerão aqui.',
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final maximum = sorted.fold<int>(
      0,
      (value, p) => math.max(value, p.totalAmountCents),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Maior valor diário: ${OwnerFormatters.moneyFromCents(maximum)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        Semantics(
          label:
              'Gráfico de vendas. Valores detalhados por dia disponíveis abaixo.',
          child: SizedBox(
            height: 190,
            child: CustomPaint(
              painter: _SalesPainter(
                sorted,
                scheme.primary,
                scheme.outlineVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [Text(sorted.first.date), Text(sorted.last.date)],
        ),
        ExpansionTile(
          title: const Text('Ver valores por dia'),
          tilePadding: EdgeInsets.zero,
          children: [
            for (final point in sorted)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(point.date),
                subtitle: Text('${point.totalCount} venda(s)'),
                trailing: Text(
                  OwnerFormatters.moneyFromCents(point.totalAmountCents),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SalesPainter extends CustomPainter {
  _SalesPainter(this.points, this.color, this.gridColor);
  final List<OwnerSalesSeriesPoint> points;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 6.0;
    final width = math.max(1.0, size.width - inset * 2);
    final height = size.height - inset * 2;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var row = 0; row <= 4; row++) {
      final y = inset + height * row / 4;
      canvas.drawLine(Offset(inset, y), Offset(inset + width, y), grid);
    }
    final maxValue = points.fold<int>(
      0,
      (m, p) => math.max(m, p.totalAmountCents),
    );
    final first = DateTime.tryParse(points.first.date)?.millisecondsSinceEpoch;
    final last = DateTime.tryParse(points.last.date)?.millisecondsSinceEpoch;
    final offsets = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final timestamp = DateTime.tryParse(
        points[index].date,
      )?.millisecondsSinceEpoch;
      final fraction =
          first != null && last != null && last > first && timestamp != null
          ? (timestamp - first) / (last - first)
          : points.length == 1
          ? 0.5
          : index / (points.length - 1);
      offsets.add(
        Offset(
          inset + fraction * width,
          inset +
              height *
                  (1 -
                      (maxValue == 0
                          ? 0
                          : points[index].totalAmountCents / maxValue)),
        ),
      );
    }
    final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final point in offsets.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(offsets.last.dx, inset + height)
      ..lineTo(offsets.first.dx, inset + height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    for (final point in offsets) {
      canvas.drawCircle(point, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SalesPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}
