import 'package:flutter/material.dart';

/// The repository-native HydraBox mark.
///
/// It is painted from simple geometry so HydraBox surfaces do not depend on
/// the inherited upstream logo asset. The outer box and three-headed network
/// form are deliberately kept usable at small sizes and in one color.
class HydraBoxMark extends StatelessWidget {
  const HydraBoxMark({
    super.key,
    this.size = 48,
    this.color,
    this.accentColor,
    this.foregroundColor,
  });

  final double size;
  final Color? color;
  final Color? accentColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = color ?? cs.primary;
    return Semantics(
      image: true,
      label: 'HydraBox logo',
      child: CustomPaint(
        size: Size.square(size),
        painter: _HydraBoxMarkPainter(
          color: primary,
          accentColor: accentColor ?? color ?? cs.tertiary,
          foregroundColor: foregroundColor ?? cs.onPrimary,
        ),
      ),
    );
  }
}

class HydraBoxLogoBadge extends StatelessWidget {
  const HydraBoxLogoBadge({
    super.key,
    this.size = 112,
    this.logoSize,
    this.innerScale = .58,
  });

  final double size;
  final double? logoSize;
  final double innerScale;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolvedLogoSize = logoSize ?? size * .5;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: .18),
            blurRadius: size * .26,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * innerScale,
          height: size * innerScale,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary.withValues(alpha: .10),
          ),
          child: Center(
            child: HydraBoxMark(
              size: resolvedLogoSize,
              color: cs.primary,
              accentColor: cs.tertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _HydraBoxMarkPainter extends CustomPainter {
  const _HydraBoxMarkPainter({
    required this.color,
    required this.accentColor,
    required this.foregroundColor,
  });

  final Color color;
  final Color accentColor;
  final Color foregroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final bounds = Offset.zero & size;
    final box = Path()
      ..moveTo(width * .50, height * .04)
      ..lineTo(width * .88, height * .24)
      ..lineTo(width * .88, height * .72)
      ..lineTo(width * .50, height * .94)
      ..lineTo(width * .12, height * .72)
      ..lineTo(width * .12, height * .24)
      ..close();

    canvas.drawPath(
      box,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, accentColor],
        ).createShader(bounds),
    );

    final linePaint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * .075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final hydra = Path()
      ..moveTo(width * .50, height * .76)
      ..lineTo(width * .50, height * .36)
      ..moveTo(width * .50, height * .55)
      ..cubicTo(
        width * .44,
        height * .47,
        width * .34,
        height * .45,
        width * .29,
        height * .34,
      )
      ..moveTo(width * .50, height * .55)
      ..cubicTo(
        width * .56,
        height * .47,
        width * .66,
        height * .45,
        width * .71,
        height * .34,
      );
    canvas.drawPath(hydra, linePaint);

    final headPaint = Paint()..color = foregroundColor;
    final headRadius = size.shortestSide * .085;
    canvas
      ..drawCircle(Offset(width * .29, height * .27), headRadius, headPaint)
      ..drawCircle(Offset(width * .50, height * .24), headRadius, headPaint)
      ..drawCircle(Offset(width * .71, height * .27), headRadius, headPaint);
  }

  @override
  bool shouldRepaint(_HydraBoxMarkPainter oldDelegate) =>
      color != oldDelegate.color ||
      accentColor != oldDelegate.accentColor ||
      foregroundColor != oldDelegate.foregroundColor;
}
