import 'dart:math' as math;

import 'package:flutter/material.dart';

class IpRefreshDots extends StatefulWidget {
  const IpRefreshDots({
    super.key,
    this.color,
    this.dotSize = 4,
    this.spacing = 3,
    this.lift = 3.5,
  });

  final Color? color;
  final double dotSize;
  final double spacing;
  final double lift;

  @override
  State<IpRefreshDots> createState() => _IpRefreshDotsState();
}

class _IpRefreshDotsState extends State<IpRefreshDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: widget.dotSize + widget.lift * 2 + 2,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              key: const ValueKey('ip-refresh-dots'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < 3; index++) ...[
                  _AnimatedIpDot(
                    index: index,
                    value: _controller.value,
                    color: color,
                    size: widget.dotSize,
                    lift: widget.lift,
                  ),
                  if (index < 2) SizedBox(width: widget.spacing),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AnimatedIpDot extends StatelessWidget {
  const _AnimatedIpDot({
    required this.index,
    required this.value,
    required this.color,
    required this.size,
    required this.lift,
  });

  final int index;
  final double value;
  final Color color;
  final double size;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final phase = (value * math.pi * 2) - index * .72;
    final wave = (math.sin(phase) + 1) / 2;
    final eased = Curves.easeInOutSine.transform(wave);
    return Transform.translate(
      offset: Offset(0, -lift * eased),
      child: Opacity(
        opacity: .72 + .28 * eased,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
