import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meow_client/widgets/app_visual_effects.dart';

const appNavigationBarVisualHeight = 80.0;
const appHeaderBlurHeight = 2.0;
const appHeaderContentGap = 36.0;

double appSystemStatusBarInset(BuildContext context) {
  return MediaQuery.viewPaddingOf(context).top;
}

double appSystemNavigationBarInset(BuildContext context) {
  final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
  final padding = MediaQuery.paddingOf(context).bottom;
  return viewPadding > padding ? viewPadding : padding;
}

double appBottomSafePadding(BuildContext context, double fallback) {
  return appSystemNavigationBarInset(context) + fallback;
}

double appBottomNavigationTotalHeight(BuildContext context) {
  return appNavigationBarVisualHeight + appSystemNavigationBarInset(context);
}

double appHeaderBlurTotalHeight(BuildContext context) {
  return appSystemStatusBarInset(context) +
      kToolbarHeight +
      appHeaderBlurHeight;
}

double progressiveHeaderTopPadding(BuildContext context, double fallback) {
  return AppVisualEffects.of(context).progressiveBlurEnabled
      ? appSystemStatusBarInset(context) + kToolbarHeight + fallback
      : fallback;
}

class ProgressiveBlurScaffold extends StatelessWidget {
  const ProgressiveBlurScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effects = AppVisualEffects.of(context);
    final blurEnabled = effects.progressiveBlurEnabled;
    final scaffoldColor = backgroundColor ?? theme.scaffoldBackgroundColor;
    final effectiveAppBar = blurEnabled ? _transparentAppBar(appBar) : appBar;
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBodyBehindAppBar: blurEnabled,
      appBar: effectiveAppBar,
      body: ColoredBox(
        color: scaffoldColor,
        child: Stack(
          children: [
            body,
            if (blurEnabled)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: appHeaderBlurTotalHeight(context),
                child: IgnorePointer(
                  child: _AppHeaderProgressiveBlur(tintColor: scaffoldColor),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AppProgressiveHeaderBlur extends StatelessWidget {
  const AppProgressiveHeaderBlur({
    super.key,
    required this.headerHeight,
    required this.child,
    this.sigma = 22,
    this.tintColor = Colors.transparent,
  });

  final double headerHeight;
  final Widget child;
  final double sigma;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: headerHeight,
          child: IgnorePointer(
            child: _AppHeaderProgressiveBlur(tintColor: tintColor),
          ),
        ),
      ],
    );
  }
}

class AppProgressiveEdgeBlur extends StatelessWidget {
  const AppProgressiveEdgeBlur({
    super.key,
    required this.enabled,
    required this.child,
    this.headerHeight = 0,
    this.footerHeight = 0,
    this.sigma = 24,
    this.tintColor = Colors.transparent,
  });

  final bool enabled;
  final Widget child;
  final double headerHeight;
  final double footerHeight;
  final double sigma;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    if (!enabled || headerHeight <= 0) {
      return child;
    }
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: headerHeight,
          child: IgnorePointer(
            child: _AppHeaderProgressiveBlur(tintColor: tintColor),
          ),
        ),
      ],
    );
  }
}

PreferredSizeWidget? _transparentAppBar(PreferredSizeWidget? appBar) {
  if (appBar is! AppBar) {
    return appBar;
  }
  return AppBar(
    leading: appBar.leading,
    automaticallyImplyLeading: appBar.automaticallyImplyLeading,
    title: appBar.title,
    actions: appBar.actions,
    flexibleSpace: appBar.flexibleSpace,
    bottom: appBar.bottom,
    elevation: 0,
    scrolledUnderElevation: 0,
    notificationPredicate: appBar.notificationPredicate,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    foregroundColor: appBar.foregroundColor,
    iconTheme: appBar.iconTheme,
    actionsIconTheme: appBar.actionsIconTheme,
    primary: appBar.primary,
    centerTitle: appBar.centerTitle,
    excludeHeaderSemantics: appBar.excludeHeaderSemantics,
    titleSpacing: appBar.titleSpacing,
    toolbarOpacity: appBar.toolbarOpacity,
    bottomOpacity: appBar.bottomOpacity,
    toolbarHeight: appBar.toolbarHeight,
    leadingWidth: appBar.leadingWidth,
    toolbarTextStyle: appBar.toolbarTextStyle,
    titleTextStyle: appBar.titleTextStyle,
    systemOverlayStyle: appBar.systemOverlayStyle,
    shape: appBar.shape,
    clipBehavior: appBar.clipBehavior,
  );
}

/// 6-band progressive blur with decreasing sigma from top to bottom.
/// Same lightweight approach as the proxy sheet header blur.
class _AppHeaderProgressiveBlur extends StatelessWidget {
  const _AppHeaderProgressiveBlur({required this.tintColor});

  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
            child: const ColoredBox(color: Colors.transparent),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tintColor.withValues(alpha: 0.85),
                  tintColor.withValues(alpha: 0.45),
                  tintColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
