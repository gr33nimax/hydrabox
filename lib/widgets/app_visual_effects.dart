import 'package:flutter/widgets.dart';

class AppVisualEffects extends InheritedWidget {
  const AppVisualEffects({
    super.key,
    required this.progressiveBlurEnabled,
    required this.hapticEnabled,
    required super.child,
  });

  final bool progressiveBlurEnabled;
  final bool hapticEnabled;

  static AppVisualEffects of(BuildContext context) {
    final effects = context
        .dependOnInheritedWidgetOfExactType<AppVisualEffects>();
    return effects ?? const _AppVisualEffectsFallback();
  }

  @override
  bool updateShouldNotify(AppVisualEffects oldWidget) {
    return progressiveBlurEnabled != oldWidget.progressiveBlurEnabled ||
        hapticEnabled != oldWidget.hapticEnabled;
  }
}

class _AppVisualEffectsFallback extends AppVisualEffects {
  const _AppVisualEffectsFallback()
    : super(
        progressiveBlurEnabled: false,
        hapticEnabled: true,
        child: const SizedBox.shrink(),
      );
}
