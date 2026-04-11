import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

class TatuzinBrandLockup extends StatelessWidget {
  const TatuzinBrandLockup({
    super.key,
    this.showTagline = true,
    this.compact = false,
    this.alignment = CrossAxisAlignment.start,
    this.caption,
  });

  final bool showTagline;
  final bool compact;
  final CrossAxisAlignment alignment;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TatuzinMascotBadge(size: compact ? 52 : 68),
        SizedBox(width: compact ? 12 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: alignment,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppConstants.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? theme.textTheme.headlineSmall
                            : theme.textTheme.headlineMedium)
                        ?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: compact ? -0.7 : -1.0,
                        ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                caption ?? AppConstants.brandLine,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              if (showTagline) ...[
                SizedBox(height: compact ? 6 : 8),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: compact ? 5 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppConstants.appSlogan,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class TatuzinMascotBadge extends StatelessWidget {
  const TatuzinMascotBadge({
    super.key,
    this.size = 64,
    this.showSurface = true,
  });

  final double size;
  final bool showSurface;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final child = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TatuzinMascotPainter(
          primary: colorScheme.primary,
          secondary: const Color(0xFFA97A57),
          surface: Colors.white,
          outline: const Color(0xFF4E3423),
          accent: const Color(0xFFD7B89E),
        ),
      ),
    );

    if (!showSurface) {
      return child;
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _TatuzinMascotPainter extends CustomPainter {
  const _TatuzinMascotPainter({
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.outline,
    required this.accent,
  });

  final Color primary;
  final Color secondary;
  final Color surface;
  final Color outline;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final paintFill = Paint()..style = PaintingStyle.fill;
    final paintStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width * 0.032
      ..color = outline.withValues(alpha: 0.9);

    final shellRect = Rect.fromCenter(
      center: Offset(width * 0.46, height * 0.54),
      width: width * 0.46,
      height: height * 0.36,
    );
    final shell = RRect.fromRectAndRadius(
      shellRect,
      Radius.circular(width * 0.18),
    );
    paintFill.color = primary;
    canvas.drawRRect(shell, paintFill);
    canvas.drawRRect(shell, paintStroke);

    final beltPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width * 0.028
      ..color = accent.withValues(alpha: 0.78);
    for (var i = 0; i < 4; i++) {
      final dx = shellRect.left + shellRect.width * (0.2 + i * 0.18);
      canvas.drawLine(
        Offset(dx, shellRect.top + shellRect.height * 0.14),
        Offset(dx, shellRect.bottom - shellRect.height * 0.14),
        beltPaint,
      );
    }

    final headRect = Rect.fromCenter(
      center: Offset(width * 0.67, height * 0.34),
      width: width * 0.24,
      height: height * 0.22,
    );
    paintFill.color = secondary;
    canvas.drawOval(headRect, paintFill);
    canvas.drawOval(headRect, paintStroke);

    final snoutRect = Rect.fromCenter(
      center: Offset(width * 0.74, height * 0.37),
      width: width * 0.12,
      height: height * 0.08,
    );
    paintFill.color = const Color(0xFFF5ECE3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(snoutRect, Radius.circular(width * 0.04)),
      paintFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(snoutRect, Radius.circular(width * 0.04)),
      paintStroke,
    );

    final earPath = Path()
      ..moveTo(width * 0.61, height * 0.22)
      ..lineTo(width * 0.67, height * 0.14)
      ..lineTo(width * 0.72, height * 0.24)
      ..close();
    paintFill.color = secondary;
    canvas.drawPath(earPath, paintFill);
    canvas.drawPath(earPath, paintStroke);

    final capTop = RRect.fromRectAndRadius(
      Rect.fromLTWH(width * 0.58, height * 0.17, width * 0.2, height * 0.07),
      Radius.circular(width * 0.04),
    );
    paintFill.color = outline;
    canvas.drawRRect(capTop, paintFill);
    final capBrim = Path()
      ..moveTo(width * 0.7, height * 0.24)
      ..quadraticBezierTo(
        width * 0.82,
        height * 0.24,
        width * 0.86,
        height * 0.29,
      )
      ..lineTo(width * 0.75, height * 0.28)
      ..close();
    canvas.drawPath(capBrim, paintFill);

    paintFill.color = outline;
    canvas.drawCircle(
      Offset(width * 0.7, height * 0.33),
      width * 0.014,
      paintFill,
    );

    final armPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width * 0.038
      ..color = secondary;
    canvas.drawLine(
      Offset(width * 0.55, height * 0.47),
      Offset(width * 0.7, height * 0.56),
      armPaint,
    );
    canvas.drawLine(
      Offset(width * 0.31, height * 0.5),
      Offset(width * 0.22, height * 0.58),
      armPaint,
    );

    final boardRect = Rect.fromLTWH(
      width * 0.64,
      height * 0.5,
      width * 0.16,
      height * 0.21,
    );
    paintFill.color = surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, Radius.circular(width * 0.035)),
      paintFill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(boardRect, Radius.circular(width * 0.035)),
      paintStroke,
    );
    paintFill.color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          width * 0.675,
          height * 0.485,
          width * 0.09,
          height * 0.04,
        ),
        Radius.circular(width * 0.018),
      ),
      paintFill,
    );
    canvas.drawLine(
      Offset(width * 0.675, height * 0.57),
      Offset(width * 0.755, height * 0.57),
      beltPaint,
    );
    canvas.drawLine(
      Offset(width * 0.675, height * 0.62),
      Offset(width * 0.745, height * 0.62),
      beltPaint,
    );

    final legPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width * 0.04
      ..color = secondary;
    canvas.drawLine(
      Offset(width * 0.37, height * 0.71),
      Offset(width * 0.35, height * 0.88),
      legPaint,
    );
    canvas.drawLine(
      Offset(width * 0.54, height * 0.71),
      Offset(width * 0.56, height * 0.88),
      legPaint,
    );
    canvas.drawLine(
      Offset(width * 0.31, height * 0.88),
      Offset(width * 0.39, height * 0.88),
      legPaint,
    );
    canvas.drawLine(
      Offset(width * 0.52, height * 0.88),
      Offset(width * 0.61, height * 0.88),
      legPaint,
    );

    final tailPath = Path();
    tailPath.moveTo(width * 0.22, height * 0.62);
    tailPath.quadraticBezierTo(
      width * 0.08,
      height * 0.65,
      width * 0.11,
      height * 0.49,
    );
    final tailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width * 0.03
      ..color = primary.withValues(alpha: 0.9);
    canvas.drawPath(tailPath, tailPaint);

    final shadowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = outline.withValues(alpha: 0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(width * 0.48, height * 0.93),
        width: width * 0.42,
        height: height * 0.08,
      ),
      shadowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TatuzinMascotPainter oldDelegate) {
    return primary != oldDelegate.primary ||
        secondary != oldDelegate.secondary ||
        surface != oldDelegate.surface ||
        outline != oldDelegate.outline ||
        accent != oldDelegate.accent;
  }
}
