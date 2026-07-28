import 'dart:async';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/core/demo_utils.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/app_view_models.dart';
import 'package:meow_client/models/proxy_runtime_visual_state.dart';
import 'package:meow_client/theme/demo_app_theme.dart';
import 'package:meow_client/widgets/country_flag_badge.dart';
import 'package:meow_client/widgets/ip_refresh_dots.dart';

const _kActiveProxyFooterReservedHeight = 82.0;

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.connected,
    required this.connecting,
    required this.resolvingProxy,
    required this.activeProfile,
    required this.activeProxy,
    this.runtimeStates,
    required this.hideServerIp,
    required this.hapticEnabled,
    required this.speedBytesPerSecond,
    required this.trafficBytes,
    this.trafficListenable,
    required this.onToggleConnection,
    required this.onRefreshLatency,
    required this.onHideServerIpChanged,
    required this.onOpenSubscriptions,
    required this.onAddSubscription,
    required this.onOpenSettings,
    required this.onOpenChangelog,
    required this.brandName,
    required this.versionLabel,
    required this.bottomInset,
    this.onOpenTrafficDashboard,
    this.onRefreshActiveProxyIp,
    this.onRefreshActiveSubscription,
    this.activeProfileRefreshing = false,
    this.showActiveProfileRefreshAction = false,
    this.onProxyPanelInteractionStart,
    this.onProxyPanelDragUpdate,
    this.onProxyPanelDragEnd,
    this.showActiveProxyFooter = true,
    this.connectionStatusLabel = '',
  });

  final bool connected;
  final bool connecting;
  final bool resolvingProxy;
  final String connectionStatusLabel;
  final AppProfileSummary? activeProfile;
  final AppProxySummary? activeProxy;
  final ProxyRuntimeVisualStore? runtimeStates;
  final bool hideServerIp;
  final bool hapticEnabled;
  final double speedBytesPerSecond;
  final double trafficBytes;
  final ValueListenable<TrafficUiSnapshot>? trafficListenable;
  final VoidCallback onToggleConnection;
  final VoidCallback onRefreshLatency;
  final ValueChanged<bool> onHideServerIpChanged;
  final VoidCallback onOpenSubscriptions;
  final VoidCallback onAddSubscription;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenChangelog;
  final String brandName;
  final String versionLabel;
  final double bottomInset;
  final VoidCallback? onOpenTrafficDashboard;
  final VoidCallback? onRefreshActiveProxyIp;
  final Future<void> Function()? onRefreshActiveSubscription;
  final bool activeProfileRefreshing;
  final bool showActiveProfileRefreshAction;
  final VoidCallback? onProxyPanelInteractionStart;
  final ValueChanged<DragUpdateDetails>? onProxyPanelDragUpdate;
  final ValueChanged<DragEndDetails>? onProxyPanelDragEnd;
  final bool showActiveProxyFooter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleColor =
        theme.appBarTheme.titleTextStyle?.color ??
        theme.textTheme.titleLarge?.color ??
        theme.colorScheme.onSurface;
    final profile = activeProfile;
    final proxy = activeProxy;
    final connectionOccupied = connected || connecting || resolvingProxy;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 18,
        title: _HomeBrandTitle(
          brandName: brandName,
          versionLabel: versionLabel,
          titleColor: titleColor,
          onOpenChangelog: onOpenChangelog,
        ),
        actions: [
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHigh,
            ),
            onPressed: onOpenSettings,
            tooltip: AppLocalizations.of(context).settingsTitle,
            icon: const Icon(Icons.settings_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
              ),
              onPressed: onAddSubscription,
              tooltip: AppLocalizations.of(context).addSubscription,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ),
      body: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: profile == null
                ? _HomeEmptyState(onAddSubscription: onAddSubscription)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wideLayout =
                          constraints.maxWidth >= 720 ||
                          (constraints.maxWidth >= 560 &&
                              constraints.maxWidth >
                                  constraints.maxHeight * 1.35);
                      return _HomeProxyPanelGestureRelay(
                        onInteractionStart: onProxyPanelInteractionStart,
                        onDragUpdate: onProxyPanelDragUpdate,
                        onDragEnd: onProxyPanelDragEnd,
                        child: wideLayout
                            ? _buildWideContent(
                                profile,
                                proxy,
                                constraints.maxWidth,
                              )
                            : _buildCompactContent(
                                profile,
                                proxy,
                                connectionOccupied,
                              ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactContent(
    AppProfileSummary profile,
    AppProxySummary? proxy,
    bool connectionOccupied,
  ) {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildSubscriptionTile(
            profile,
            const EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Center(
                    child: _buildConnectionControl(
                      proxy,
                      connectionOccupied: connectionOccupied,
                    ),
                  ),
                ),
                ?_buildActiveProxyFooter(proxy),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideContent(
    AppProfileSummary profile,
    AppProxySummary? proxy,
    double maxWidth,
  ) {
    final sideWidth = math.min(360.0, maxWidth * .42);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: sideWidth,
            child: Column(
              children: [
                _buildSubscriptionTile(profile, EdgeInsets.zero),
                if (_buildActiveProxyFooter(proxy) case final footer?) ...[
                  const Spacer(),
                  footer,
                ],
              ],
            ),
          ),
          const Gap(24),
          Expanded(
            child: Center(
              child: _buildConnectionControl(proxy, connectionOccupied: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionTile(AppProfileSummary profile, EdgeInsets margin) {
    return _SubscriptionTile(
      profile: profile,
      margin: margin,
      onTap: onOpenSubscriptions,
      onOpenTrafficDashboard: onOpenTrafficDashboard,
      onRefresh: onRefreshActiveSubscription,
      refreshing: activeProfileRefreshing,
      showRefreshAction: showActiveProfileRefreshAction,
    );
  }

  Widget _buildConnectionControl(
    AppProxySummary? proxy, {
    required bool connectionOccupied,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          end: connectionOccupied ? 0 : _kActiveProxyFooterReservedHeight / 2,
        ),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, offsetY, child) {
          return Transform.translate(offset: Offset(0, offsetY), child: child);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConnectionButton(
              connected: connected,
              connecting: connecting,
              resolvingProxy: resolvingProxy,
              statusLabel: connectionStatusLabel,
              onTap: onToggleConnection,
            ),
            const Gap(8),
            _buildActiveProxyDelayIndicator(proxy),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveProxyDelayIndicator(AppProxySummary? proxy) {
    Widget buildIndicator(ProxyRuntimeVisualState? state) {
      return ActiveProxyDelayIndicator(
        connected: connected,
        proxy: proxy == null
            ? null
            : applyProxyRuntimeVisualState(proxy, state),
        networkUnavailable: state?.networkUnavailable ?? false,
        onRefresh: onRefreshLatency,
      );
    }

    final states = runtimeStates;
    if (proxy == null || states == null) {
      return buildIndicator(null);
    }
    return ValueListenableBuilder<ProxyRuntimeVisualState?>(
      valueListenable: states.listenableFor(proxy.tag),
      builder: (context, state, _) => buildIndicator(state),
    );
  }

  Widget? _buildActiveProxyFooter(AppProxySummary? proxy) {
    if (!showActiveProxyFooter || proxy == null) {
      return null;
    }
    if (trafficListenable == null) {
      return ActiveProxyFooter(
        connected: connected,
        proxy: proxy,
        hideIp: hideServerIp,
        hapticEnabled: hapticEnabled,
        speedBytesPerSecond: speedBytesPerSecond,
        trafficBytes: trafficBytes,
        unknownText: '—',
        onRefreshIp: onRefreshActiveProxyIp,
      );
    }
    return ValueListenableBuilder<TrafficUiSnapshot>(
      valueListenable: trafficListenable!,
      builder: (context, traffic, _) {
        return ActiveProxyFooter(
          connected: connected,
          proxy: proxy,
          hideIp: hideServerIp,
          hapticEnabled: hapticEnabled,
          speedBytesPerSecond: traffic.speedBytesPerSecond,
          trafficBytes: traffic.trafficBytes,
          unknownText: '—',
          onRefreshIp: onRefreshActiveProxyIp,
        );
      },
    );
  }
}

class _HomeBrandTitle extends StatelessWidget {
  const _HomeBrandTitle({
    required this.brandName,
    required this.versionLabel,
    required this.titleColor,
    required this.onOpenChangelog,
  });

  final String brandName;
  final String versionLabel;
  final Color titleColor;
  final VoidCallback onOpenChangelog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/images/logo.svg',
          height: 24,
          colorFilter: ColorFilter.mode(titleColor, BlendMode.srcIn),
        ),
        const Gap(9),
        Flexible(
          child: Text(brandName, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Gap(8),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onOpenChangelog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh.withValues(
                alpha: .72,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Text(
              versionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeProxyPanelGestureRelay extends StatefulWidget {
  const _HomeProxyPanelGestureRelay({
    required this.child,
    this.onInteractionStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final Widget child;
  final VoidCallback? onInteractionStart;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final ValueChanged<DragEndDetails>? onDragEnd;

  @override
  State<_HomeProxyPanelGestureRelay> createState() =>
      _HomeProxyPanelGestureRelayState();
}

class _HomeProxyPanelGestureRelayState
    extends State<_HomeProxyPanelGestureRelay> {
  static const _startThreshold = 6.0;

  bool _dragStarted = false;
  double _totalDeltaY = 0;

  void _handlePointerDown(PointerDownEvent event) {
    widget.onInteractionStart?.call();
    _dragStarted = false;
    _totalDeltaY = 0;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _totalDeltaY += event.delta.dy;
    if (!_dragStarted && _totalDeltaY.abs() < _startThreshold) {
      return;
    }
    final deltaY = _dragStarted ? event.delta.dy : _totalDeltaY;
    _dragStarted = true;
    widget.onDragUpdate?.call(
      DragUpdateDetails(
        sourceTimeStamp: event.timeStamp,
        delta: Offset(0, deltaY),
        primaryDelta: deltaY,
        globalPosition: event.position,
        localPosition: event.localPosition,
      ),
    );
  }

  void _handlePointerEnd(PointerUpEvent event) {
    widget.onDragEnd?.call(DragEndDetails());
    _reset();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    widget.onDragEnd?.call(DragEndDetails());
    _reset();
  }

  void _reset() {
    _dragStarted = false;
    _totalDeltaY = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({required this.onAddSubscription});

  final VoidCallback onAddSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.7,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(
              Icons.cloud_download_rounded,
              size: 42,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const Gap(20),
          Text(
            l10n.noSubscriptions,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const Gap(8),
          Text(
            l10n.noSubscriptionsHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(24),
          FilledButton.icon(
            onPressed: onAddSubscription,
            icon: const Icon(Icons.add_link_rounded),
            label: Text(l10n.addSubscription),
          ),
        ],
      ),
    );
  }
}

class ConnectionButton extends StatefulWidget {
  const ConnectionButton({
    super.key,
    required this.connected,
    required this.connecting,
    required this.resolvingProxy,
    required this.statusLabel,
    required this.onTap,
  });

  final bool connected;
  final bool connecting;
  final bool resolvingProxy;
  final String statusLabel;
  final VoidCallback onTap;

  @override
  State<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends State<ConnectionButton> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final buttonTheme =
        theme.extension<ConnectionButtonTheme>() ?? ConnectionButtonTheme.light;
    final buttonColor = widget.connected
        ? buttonTheme.connectedColor!
        : buttonTheme.idleColor!;
    final busyLabel = widget.statusLabel.trim().isNotEmpty
        ? widget.statusLabel
        : l10n.tapToConnect;
    final label = widget.connected
        ? l10n.connected
        : (widget.connecting || widget.resolvingProxy)
        ? busyLabel
        : l10n.tapToConnect;

    return Column(
      children: [
        Semantics(
          button: true,
          label: label,
          child: TweenAnimationBuilder<_ConnectionButtonShape>(
            tween: _ConnectionButtonShapeTween(
              end: _ConnectionButtonShape.forState(
                connected: widget.connected,
                connecting: widget.connecting,
                resolvingProxy: widget.resolvingProxy,
              ),
            ),
            duration: const Duration(milliseconds: 680),
            curve: Curves.easeInOutCubicEmphasized,
            builder: (context, shape, child) {
              final scale = 1 + (shape.emphasis * 0.06);
              final glow = 16 + (shape.emphasis * 12);
              final inset = 36 - (shape.emphasis * 4);
              // Busy state must stay visually calm. A stuck native transition
              // should not keep Flutter rendering at display refresh rate.
              const rotationAngle = 0.0;
              return Transform.scale(
                scale: scale,
                child: Transform.rotate(
                  angle: rotationAngle,
                  child: CustomPaint(
                    painter: _ConnectionButtonShadowPainter(
                      shape: shape,
                      color: buttonColor.withValues(alpha: .45),
                      blur: glow,
                      spread: shape.emphasis * 2,
                    ),
                    child: ClipPath(
                      clipper: _ConnectionButtonShapeClipper(shape),
                      child: SizedBox(
                        width: 148,
                        height: 148,
                        child: Material(
                          color: Colors.white,
                          child: InkWell(
                            onTap: widget.connecting ? null : widget.onTap,
                            child: Transform.rotate(
                              angle: -rotationAngle,
                              child: Padding(
                                padding: EdgeInsets.all(inset),
                                child: SvgPicture.asset(
                                  'assets/images/logo.svg',
                                  colorFilter: ColorFilter.mode(
                                    buttonColor,
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Gap(16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.18),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Row(
            key: ValueKey(
              '${label}_${widget.connecting}_${widget.resolvingProxy}',
            ),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.connecting || widget.resolvingProxy) ...[
                Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const Gap(8),
              ],
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: widget.connected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

@immutable
class _ConnectionButtonShape {
  const _ConnectionButtonShape({
    required this.phase,
    required this.rotation,
    required this.emphasis,
  });

  factory _ConnectionButtonShape.forState({
    required bool connected,
    required bool connecting,
    required bool resolvingProxy,
  }) {
    if (resolvingProxy) {
      return const _ConnectionButtonShape(phase: 3, rotation: 0, emphasis: .96);
    }
    if (connected) {
      return const _ConnectionButtonShape(
        phase: 2,
        rotation: 0,
        emphasis: 1.16,
      );
    }
    if (connecting) {
      return const _ConnectionButtonShape(phase: 1, rotation: 0, emphasis: .52);
    }
    return const _ConnectionButtonShape(phase: 0, rotation: 0, emphasis: 0);
  }

  final double phase;
  final double rotation;
  final double emphasis;

  _ConnectionButtonShape copyWith({
    double? phase,
    double? rotation,
    double? emphasis,
  }) {
    return _ConnectionButtonShape(
      phase: phase ?? this.phase,
      rotation: rotation ?? this.rotation,
      emphasis: emphasis ?? this.emphasis,
    );
  }

  static _ConnectionButtonShape lerp(
    _ConnectionButtonShape a,
    _ConnectionButtonShape b,
    double t,
  ) {
    return _ConnectionButtonShape(
      phase: _lerp(a.phase, b.phase, t),
      rotation: _lerpAngle(a.rotation, b.rotation, t),
      emphasis: _lerp(a.emphasis, b.emphasis, t),
    );
  }
}

class _ConnectionButtonShapeTween extends Tween<_ConnectionButtonShape> {
  _ConnectionButtonShapeTween({required _ConnectionButtonShape end})
    : super(end: end);

  @override
  _ConnectionButtonShape lerp(double t) {
    return _ConnectionButtonShape.lerp(begin ?? end!, end!, t);
  }
}

class _ConnectionButtonShapeClipper extends CustomClipper<Path> {
  const _ConnectionButtonShapeClipper(this.shape);

  final _ConnectionButtonShape shape;

  @override
  Path getClip(Size size) => _connectionButtonCookiePath(size, shape);

  @override
  bool shouldReclip(_ConnectionButtonShapeClipper oldClipper) {
    return oldClipper.shape != shape;
  }
}

class _ConnectionButtonShadowPainter extends CustomPainter {
  const _ConnectionButtonShadowPainter({
    required this.shape,
    required this.color,
    required this.blur,
    required this.spread,
  });

  final _ConnectionButtonShape shape;
  final Color color;
  final double blur;
  final double spread;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _connectionButtonCookiePath(
      size,
      shape,
      radiusAdjustment: spread,
    );
    canvas.drawShadow(path, color, blur, true);
  }

  @override
  bool shouldRepaint(_ConnectionButtonShadowPainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.color != color ||
        oldDelegate.blur != blur ||
        oldDelegate.spread != spread;
  }
}

Path _connectionButtonCookiePath(
  Size size,
  _ConnectionButtonShape shape, {
  double radiusAdjustment = 0,
}) {
  final center = Offset(size.width / 2, size.height / 2);
  final radius = math.min(size.width, size.height) / 2 + radiusAdjustment;
  const samples = _kConnectionButtonPathSamples;
  final points = <Offset>[];
  final phase = shape.phase.clamp(0.0, 3.0);
  final (from, to, t) = switch (phase) {
    <= 1 => (_kConnectionCircle, _kConnectionConnectingCookie, phase),
    <= 2 => (
      _kConnectionConnectingCookie,
      _kConnectionConnectedCookie,
      phase - 1,
    ),
    _ => (_kConnectionConnectedCookie, _kConnectionResolvingCookie, phase - 2),
  };

  for (var index = 0; index < samples; index += 1) {
    final theta = (index / samples * math.pi * 2) + shape.rotation;
    final radiusFactor = _lerp(from[index], to[index], t);
    points.add(
      center + Offset(math.cos(theta), math.sin(theta)) * radius * radiusFactor,
    );
  }

  final path = Path();
  for (var index = 0; index < points.length; index += 1) {
    final current = points[index];
    final next = points[(index + 1) % points.length];
    final midpoint = Offset(
      (current.dx + next.dx) / 2,
      (current.dy + next.dy) / 2,
    );
    if (index == 0) {
      path.moveTo(midpoint.dx, midpoint.dy);
    } else {
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }
  }
  final first = points.first;
  final second = points[1];
  final firstMidpoint = Offset(
    (first.dx + second.dx) / 2,
    (first.dy + second.dy) / 2,
  );
  path.quadraticBezierTo(
    first.dx,
    first.dy,
    firstMidpoint.dx,
    firstMidpoint.dy,
  );
  path.close();
  return path;
}

const _kConnectionButtonPathSamples = 96;

final List<double> _kConnectionCircle = List<double>.filled(
  _kConnectionButtonPathSamples,
  1,
);

final List<double> _kConnectionConnectingCookie = List<double>.generate(
  _kConnectionButtonPathSamples,
  (index) => _cookieRadius(
    index: index,
    samples: _kConnectionButtonPathSamples,
    sides: 5,
    depth: .12,
    sharpness: 1.35,
    rotation: -math.pi / 2,
  ),
  growable: false,
);

final List<double> _kConnectionConnectedCookie = List<double>.generate(
  _kConnectionButtonPathSamples,
  (index) => _cookieRadius(
    index: index,
    samples: _kConnectionButtonPathSamples,
    sides: 8,
    depth: .1,
    sharpness: 1.08,
    rotation: -math.pi / 2,
  ),
  growable: false,
);

final List<double> _kConnectionResolvingCookie = List<double>.generate(
  _kConnectionButtonPathSamples,
  (index) => _cookieRadius(
    index: index,
    samples: _kConnectionButtonPathSamples,
    sides: 6,
    depth: .12,
    sharpness: 1.08,
    rotation: -math.pi / 2,
  ),
  growable: false,
);

double _cookieRadius({
  required int index,
  required int samples,
  required int sides,
  required double depth,
  required double sharpness,
  required double rotation,
}) {
  final theta = index / samples * math.pi * 2;
  final lobe = (1 + math.cos(sides * (theta - rotation))) / 2;
  final valley = math.pow(1 - lobe, sharpness).toDouble();
  return 1 - depth * valley;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _lerpAngle(double a, double b, double t) {
  final difference = math.atan2(math.sin(b - a), math.cos(b - a));
  return a + difference * t;
}

class ActiveProxyDelayIndicator extends StatelessWidget {
  const ActiveProxyDelayIndicator({
    super.key,
    required this.connected,
    required this.proxy,
    this.networkUnavailable = false,
    required this.onRefresh,
  });

  final bool connected;
  final AppProxySummary? proxy;
  final bool networkUnavailable;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final latency = proxy?.latency;
    final latencyFresh = proxy?.latencyFresh == true;
    final latencyChecking = proxy?.latencyChecking == true;
    final latencyUnavailable = proxy?.latencyUnavailable == true;
    final latencyUnknown = !latencyUnavailable && latency == null;
    final showCheckingIndicator = latencyChecking && !networkUnavailable;
    final hidden = !connected || proxy == null;
    final color = networkUnavailable
        ? theme.colorScheme.onSurfaceVariant
        : latencyChecking
        ? theme.colorScheme.primary
        : latencyUnavailable
        ? theme.colorScheme.onSurfaceVariant
        : !latencyFresh || latency == null
        ? theme.colorScheme.onSurfaceVariant
        : latency < 350
        ? theme.colorScheme.primary
        : latency < 900
        ? theme.colorScheme.tertiary
        : theme.colorScheme.error;
    final valueText = networkUnavailable
        ? '—'
        : latencyChecking
        ? l10n.checkingLatencyShort
        : latencyUnavailable
        ? '—'
        : latency != null
        ? '$latency'
        : '—';
    final icon = networkUnavailable
        ? Icon(Icons.wifi_off_rounded, color: color)
        : showCheckingIndicator
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          )
        : latencyUnavailable
        ? Icon(FluentIcons.wifi_warning_24_regular, color: color)
        : !latencyFresh || latencyUnknown
        ? Icon(FluentIcons.history_24_regular, color: color)
        : Icon(FluentIcons.wifi_1_24_regular, color: color);
    final unitText =
        networkUnavailable ||
            latencyChecking ||
            latencyUnavailable ||
            latency == null
        ? ''
        : l10n.millisecondsUnit;
    final tooltip = latencyChecking
        ? l10n.checkingLatency
        : l10n.refreshLatency;

    final content = Tooltip(
      message: tooltip,
      child: Semantics(
        button: !hidden,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: hidden ? null : onRefresh,
            child: SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      child: KeyedSubtree(
                        key: ValueKey(
                          networkUnavailable
                              ? 'offline'
                              : showCheckingIndicator
                              ? 'checking'
                              : latencyUnavailable
                              ? 'unavailable'
                              : latencyFresh
                              ? 'fresh'
                              : 'stale',
                        ),
                        child: icon,
                      ),
                    ),
                    const Gap(8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 76),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previousChildren, ?currentChild],
                          );
                        },
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(
                                begin: .96,
                                end: 1,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text.rich(
                          key: ValueKey('$valueText$unitText'),
                          TextSpan(
                            children: [
                              TextSpan(
                                text: valueText,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: unitText,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        opacity: hidden ? 0 : 1,
        child: content,
      ),
    );
  }
}

class ActiveProxyFooter extends StatelessWidget {
  const ActiveProxyFooter({
    super.key,
    required this.connected,
    required this.proxy,
    required this.hideIp,
    required this.hapticEnabled,
    required this.speedBytesPerSecond,
    required this.trafficBytes,
    required this.unknownText,
    this.onRefreshIp,
  });

  final bool connected;
  final AppProxySummary proxy;
  final bool hideIp;
  final bool hapticEnabled;
  final double speedBytesPerSecond;
  final double trafficBytes;
  final String unknownText;
  final VoidCallback? onRefreshIp;

  String _maskIp(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.*.*';
    }
    if (ip.length > 8) {
      return '${ip.substring(0, ip.length ~/ 2)}****';
    }
    return ip;
  }

  String get _displayIp {
    if (!connected) return '—';
    final ip = proxy.ip;
    if (ip.isEmpty) return unknownText;
    if (hideIp) return _maskIp(ip);
    return ip;
  }

  void _refreshIp() {
    if (!connected || onRefreshIp == null) return;
    if (hapticEnabled) {
      HapticFeedback.lightImpact();
    }
    onRefreshIp?.call();
  }

  Widget _ipDisplay(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    if (connected && proxy.ipChecking && proxy.ip.trim().isEmpty) {
      return IpRefreshDots(
        key: const ValueKey('ip-refresh-checking'),
        color: color,
      );
    }
    return Text(
      _displayIp,
      key: ValueKey(_displayIp),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speedText = formatSpeed(connected ? speedBytesPerSecond : 0);
    final trafficText = formatBytes(connected ? trafficBytes : 0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: IgnorePointer(
        ignoring: !connected,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 74),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CountryFlagBadge(countryCode: proxy.countryCode, size: 40),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRect(
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerLeft,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeOutCubic,
                              layoutBuilder: (currentChild, previousChildren) {
                                return Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    ...previousChildren,
                                    ?currentChild,
                                  ],
                                );
                              },
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.12),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: Text(
                                proxy.displayName,
                                key: ValueKey(proxy.displayName),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Gap(6),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: connected ? _refreshIp : null,
                          child: SizedBox(
                            height: 24,
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeOutCubic,
                                layoutBuilder:
                                    (currentChild, previousChildren) {
                                      return Stack(
                                        alignment: Alignment.centerLeft,
                                        children: [
                                          ...previousChildren,
                                          ?currentChild,
                                        ],
                                      );
                                    },
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.08),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: _ipDisplay(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  SizedBox(
                    width: 118,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _FooterStatLine(
                          icon: FluentIcons.arrow_download_20_regular,
                          text: speedText,
                        ),
                        const Gap(8),
                        _FooterStatLine(
                          icon: FluentIcons
                              .arrow_bidirectional_up_down_20_regular,
                          text: trafficText,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterStatLine extends StatelessWidget {
  const _FooterStatLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Gap(6),
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
      ],
    );
  }
}

class _SubscriptionTile extends StatelessWidget {
  const _SubscriptionTile({
    required this.profile,
    required this.margin,
    required this.onTap,
    this.onOpenTrafficDashboard,
    this.onRefresh,
    this.refreshing = false,
    this.showRefreshAction = false,
  });

  final AppProfileSummary profile;
  final EdgeInsets margin;
  final VoidCallback onTap;
  final VoidCallback? onOpenTrafficDashboard;
  final Future<void> Function()? onRefresh;
  final bool refreshing;
  final bool showRefreshAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final surfaces =
        theme.extension<AppSurfaceTheme>() ?? AppSurfaceTheme.standard;
    final cardRadius = BorderRadius.circular(surfaces.mediumRadius);
    final usageText = profile.hasUsage
        ? l10n.trafficUsage(
            formatBytes(profile.consumed),
            formatBytes(profile.total),
          )
        : l10n.trafficUsage(
            formatBytes(profile.consumed),
            l10n.unlimitedSymbol,
          );
    final remainingDays = profile.remainingDays;
    final remainingText = remainingDays == null
        ? l10n.daysLeftUnlimited
        : remainingDays > 0
        ? l10n.daysLeft(remainingDays)
        : l10n.expired;

    return Card(
      margin: margin,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: cardRadius,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .42),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showRefreshAction) ...[
                _ProfileRefreshAction(
                  refreshing: refreshing,
                  enabled: onRefresh != null && !refreshing,
                  onTap: onRefresh == null
                      ? null
                      : () => unawaited(onRefresh!.call()),
                ),
                VerticalDivider(
                  width: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: .52,
                  ),
                ),
              ],
              Expanded(
                child: InkWell(
                  borderRadius: showRefreshAction
                      ? BorderRadius.horizontal(right: cardRadius.topRight)
                      : cardRadius,
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                profile.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (onOpenTrafficDashboard != null) ...[
                              const Gap(4),
                              Tooltip(
                                message: l10n.openTrafficDashboard,
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: l10n.openTrafficDashboard,
                                  onPressed: onOpenTrafficDashboard,
                                  icon: const Icon(Icons.monitor_heart_rounded),
                                ),
                              ),
                            ],
                            const Gap(6),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                        if (profile.hasUsage) ...[
                          const Gap(6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: profile.ratio,
                              minHeight: 5,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          const Gap(6),
                        ] else
                          const Gap(1),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                usageText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Gap(12),
                            Text(
                              remainingText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileRefreshAction extends StatelessWidget {
  const _ProfileRefreshAction({
    required this.refreshing,
    required this.enabled,
    required this.onTap,
  });

  final bool refreshing;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final tooltip = enabled || refreshing
        ? l10n.refreshActiveSubscription
        : l10n.refreshActiveSubscriptionUnavailable;
    return SizedBox(
      width: 48,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Tooltip(
          message: tooltip,
          child: InkWell(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(20),
            ),
            onTap: enabled ? onTap : null,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: refreshing
                    ? SizedBox(
                        key: const ValueKey('profile-refresh-progress'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.update_rounded,
                        key: const ValueKey('profile-refresh-icon'),
                        color: enabled
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.disabledColor,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
