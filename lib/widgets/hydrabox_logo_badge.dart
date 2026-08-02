import 'package:flutter/material.dart';

/// The canonical dotted three-headed HydraBox mark.
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
      child: SizedBox.square(
        dimension: size,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
          child: Image.asset(
            'assets/branding/hydrabox-mark.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
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
