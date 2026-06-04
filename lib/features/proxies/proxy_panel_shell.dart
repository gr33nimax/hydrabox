import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:meow_client/widgets/progressive_blur_scaffold.dart';

const proxyPanelMinHeight = 108.0;
const proxyPanelScreenCornerRadius = 32.0;

const _proxyPanelHeaderHeight = 108.0;
const _proxyPanelRowHeight = 66.0;
const _proxyPanelContentBottomPadding = 60.0;
const _proxyPanelStatusBarGap = 8.0;
const _proxyPanelInertiaMinVelocity = 90.0;
const _proxyPanelSettleCloseRatio = .857;
const _proxyPanelCompactSettleCloseRatio = .64;
const _proxyPanelMaxSpringVelocity = 5000.0;

final SpringDescription _proxyPanelSpring = SpringDescription.withDampingRatio(
  mass: 0.5,
  stiffness: 100,
  ratio: 1.1,
);

@immutable
class ProxyPanelMetrics {
  const ProxyPanelMetrics({
    required this.bottomInset,
    required this.panelHeight,
    required this.maxPanelHeight,
    required this.viewportHeight,
    required this.viewportLimit,
    required this.progress,
    required this.backdropProgress,
    required this.atMaxExtent,
    required this.canFillScreen,
    required this.collapseOnAnyDownwardDrag,
    required this.dragging,
    required this.animating,
  });

  final double bottomInset;
  final double panelHeight;
  final double maxPanelHeight;
  final double viewportHeight;
  final double viewportLimit;
  final double progress;
  final double backdropProgress;
  final bool atMaxExtent;
  final bool canFillScreen;
  final bool collapseOnAnyDownwardDrag;
  final bool dragging;
  final bool animating;

  @override
  bool operator ==(Object other) {
    return other is ProxyPanelMetrics &&
        other.bottomInset == bottomInset &&
        other.panelHeight == panelHeight &&
        other.maxPanelHeight == maxPanelHeight &&
        other.viewportHeight == viewportHeight &&
        other.viewportLimit == viewportLimit &&
        other.progress == progress &&
        other.backdropProgress == backdropProgress &&
        other.atMaxExtent == atMaxExtent &&
        other.canFillScreen == canFillScreen &&
        other.collapseOnAnyDownwardDrag == collapseOnAnyDownwardDrag &&
        other.dragging == dragging &&
        other.animating == animating;
  }

  @override
  int get hashCode => Object.hash(
    bottomInset,
    panelHeight,
    maxPanelHeight,
    viewportHeight,
    viewportLimit,
    progress,
    backdropProgress,
    atMaxExtent,
    canFillScreen,
    collapseOnAnyDownwardDrag,
    dragging,
    animating,
  );
}

@immutable
class ProxyPanelGestures {
  const ProxyPanelGestures({
    required this.onInteractionStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onHeaderTap,
  });

  final VoidCallback onInteractionStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;
  final VoidCallback onHeaderTap;
}

typedef ProxyPanelHomeBuilder =
    Widget Function(
      BuildContext context,
      ProxyPanelMetrics metrics,
      ProxyPanelGestures gestures,
    );

typedef ProxyPanelSheetBuilder =
    Widget Function(
      BuildContext context,
      ProxyPanelMetrics metrics,
      ValueListenable<ProxyPanelMetrics> metricsListenable,
      ScrollController scrollController,
      ProxyPanelGestures gestures,
    );

class ProxyPanelShell extends StatefulWidget {
  const ProxyPanelShell({
    super.key,
    required this.ready,
    required this.onboardingCompleted,
    required this.loading,
    required this.welcome,
    required this.visibleRows,
    required this.hasActiveProfile,
    required this.homeBuilder,
    required this.sheetBuilder,
    this.resetListKey,
    this.onInteractionActiveChanged,
  });

  final bool ready;
  final bool onboardingCompleted;
  final Widget loading;
  final Widget welcome;
  final int visibleRows;
  final bool hasActiveProfile;
  final ProxyPanelHomeBuilder homeBuilder;
  final ProxyPanelSheetBuilder sheetBuilder;
  final Object? resetListKey;
  final ValueChanged<bool>? onInteractionActiveChanged;

  @override
  State<ProxyPanelShell> createState() => _ProxyPanelShellState();
}

class _ProxyPanelShellState extends State<ProxyPanelShell>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final ScrollController _listController = ScrollController();
  late final ValueNotifier<ProxyPanelMetrics> _metricsNotifier =
      ValueNotifier<ProxyPanelMetrics>(_fallbackMetrics);
  AnimationController? _inertiaController;
  bool _dragging = false;
  int _dragDirection = 0;
  double _height = proxyPanelMinHeight;
  double _lastViewportHeight = proxyPanelMinHeight;
  double _lastTopInset = 0;
  double _lastBottomInset = 0;
  bool _openForBack = false;
  BuildContext? _routeContext;
  ModalRoute<dynamic>? _route;
  LocalHistoryEntry? _historyEntry;
  bool _historyRemovalInProgress = false;
  bool _backCloseInProgress = false;
  bool _predictiveBackInProgress = false;
  double _predictiveBackStartHeight = proxyPanelMinHeight;
  double _predictiveBackMaxHeight = proxyPanelMinHeight;

  static const ProxyPanelMetrics _fallbackMetrics = ProxyPanelMetrics(
    bottomInset: 0,
    panelHeight: proxyPanelMinHeight,
    maxPanelHeight: proxyPanelMinHeight,
    viewportHeight: proxyPanelMinHeight,
    viewportLimit: proxyPanelMinHeight,
    progress: 0,
    backdropProgress: 0,
    atMaxExtent: false,
    canFillScreen: false,
    collapseOnAnyDownwardDrag: true,
    dragging: false,
    animating: false,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant ProxyPanelShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetListKey != widget.resetListKey ||
        (oldWidget.visibleRows != widget.visibleRows && _isClosed)) {
      _resetListScroll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeHistoryEntry();
    _routeContext = null;
    _route = null;
    _inertiaController?.dispose();
    _metricsNotifier.dispose();
    _listController.dispose();
    super.dispose();
  }

  bool get _isClosed => _height <= proxyPanelMinHeight + 0.5;

  void _setDragging(bool value) {
    if (_dragging == value) {
      return;
    }
    _dragging = value;
    widget.onInteractionActiveChanged?.call(value);
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !mounted) {
      return false;
    }
    final route = _route;
    final routeContext = _routeContext;
    if (route?.isCurrent != true || routeContext == null || !_openForBack) {
      return false;
    }
    _ensureHistoryEntry();
    _cancelInertia();
    final viewportHeight = _layoutViewportHeight(routeContext);
    final topInset = MediaQuery.paddingOf(routeContext).top;
    final maxHeight = _maxHeight(viewportHeight, topInset: topInset);
    _predictiveBackInProgress = true;
    _predictiveBackStartHeight = _height
        .clamp(proxyPanelMinHeight, maxHeight)
        .toDouble();
    _predictiveBackMaxHeight = maxHeight;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_predictiveBackInProgress || !mounted) {
      return;
    }
    final progress = backEvent.progress.clamp(0.0, 1.0).toDouble();
    final nextHeight =
        _predictiveBackStartHeight +
        (proxyPanelMinHeight - _predictiveBackStartHeight) * progress;
    _setDragging(true);
    _dragDirection = -1;
    _height = nextHeight
        .clamp(proxyPanelMinHeight, _predictiveBackMaxHeight)
        .toDouble();
    _publishCurrentMetrics();
  }

  @override
  void handleCancelBackGesture() {
    if (!_predictiveBackInProgress || !mounted) {
      return;
    }
    final target = _predictiveBackStartHeight;
    final maxHeight = _predictiveBackMaxHeight;
    _predictiveBackInProgress = false;
    _animateTo(target: target, heightVelocity: 0, maxHeight: maxHeight);
  }

  @override
  void handleCommitBackGesture() {
    if (!_predictiveBackInProgress || !mounted) {
      return;
    }
    final maxHeight = _predictiveBackMaxHeight;
    _predictiveBackInProgress = false;
    _backCloseInProgress = true;
    _animateTo(
      target: proxyPanelMinHeight,
      heightVelocity: 0,
      maxHeight: maxHeight,
    );
  }

  void _drag(double deltaY, double viewportHeight, {double topInset = 0}) {
    _cancelInertia();
    if (viewportHeight <= 0) {
      return;
    }
    final maxHeight = _maxHeight(viewportHeight, topInset: topInset);
    if (maxHeight <= proxyPanelMinHeight + 0.5) {
      return;
    }
    final nextDirection = deltaY < 0
        ? 1
        : deltaY > 0
        ? -1
        : _dragDirection;
    final nextHeight = (_height - deltaY)
        .clamp(proxyPanelMinHeight, maxHeight)
        .toDouble();
    if ((nextHeight - _height).abs() < 0.5 && nextDirection == _dragDirection) {
      return;
    }
    _setDragging(true);
    _dragDirection = nextDirection;
    _height = nextHeight;
    _publishCurrentMetrics();
    if (nextHeight > proxyPanelMinHeight + 8) {
      if (!_openForBack) {
        setState(() {
          _openForBack = true;
        });
      }
      _ensureHistoryEntry();
    }
    if (nextHeight <= proxyPanelMinHeight + 0.5) {
      if (_openForBack) {
        setState(() {
          _openForBack = false;
        });
      }
      _resetListScroll();
    }
  }

  void _settle(
    DragEndDetails details,
    double viewportHeight, {
    double topInset = 0,
  }) {
    _cancelInertia();
    if (viewportHeight <= 0) {
      return;
    }
    final maxHeight = _maxHeight(viewportHeight, topInset: topInset);
    if (maxHeight <= proxyPanelMinHeight + 0.5) {
      _setDragging(false);
      _dragDirection = 0;
      _height = proxyPanelMinHeight;
      _publishCurrentMetrics();
      _resetListScroll();
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final opening =
        velocity < -_proxyPanelInertiaMinVelocity ||
        (velocity.abs() <= _proxyPanelInertiaMinVelocity && _dragDirection > 0);
    if (opening) {
      _animateTo(
        target: maxHeight,
        heightVelocity: velocity < 0 ? -velocity : 0,
        maxHeight: maxHeight,
      );
      return;
    }
    if (velocity > _proxyPanelInertiaMinVelocity) {
      _animateBallistic(
        velocity: velocity,
        viewportHeight: viewportHeight,
        maxHeight: maxHeight,
      );
      return;
    }
    _finishSettle(viewportHeight: viewportHeight, maxHeight: maxHeight);
  }

  void _animateBallistic({
    required double velocity,
    required double viewportHeight,
    required double maxHeight,
  }) {
    final startHeight = _height
        .clamp(proxyPanelMinHeight, maxHeight)
        .toDouble();
    final closeThreshold = _closeThreshold(
      viewportHeight: viewportHeight,
      maxHeight: maxHeight,
    );
    final heightVelocity = (-velocity)
        .clamp(-_proxyPanelMaxSpringVelocity, _proxyPanelMaxSpringVelocity)
        .toDouble();
    final projectedLowPoint = _projectedSpringLowPoint(
      startHeight: startHeight,
      targetHeight: maxHeight,
      heightVelocity: heightVelocity,
      maxHeight: maxHeight,
    );
    final target = projectedLowPoint <= closeThreshold
        ? proxyPanelMinHeight
        : maxHeight;
    _animateTo(
      target: target,
      heightVelocity: heightVelocity,
      maxHeight: maxHeight,
    );
  }

  double _projectedSpringLowPoint({
    required double startHeight,
    required double targetHeight,
    required double heightVelocity,
    required double maxHeight,
  }) {
    if (heightVelocity >= 0) {
      return startHeight;
    }
    final simulation = SpringSimulation(
      _proxyPanelSpring,
      startHeight,
      targetHeight,
      heightVelocity,
    );
    var lowPoint = startHeight;
    var previousVelocity = heightVelocity;
    for (var step = 1; step <= 120; step += 1) {
      final time = step / 120;
      final height = simulation
          .x(time)
          .clamp(proxyPanelMinHeight, maxHeight)
          .toDouble();
      if (height < lowPoint) {
        lowPoint = height;
      }
      final velocity = simulation.dx(time);
      if (previousVelocity < 0 && velocity >= 0) {
        break;
      }
      if (simulation.isDone(time)) {
        break;
      }
      previousVelocity = velocity;
    }
    return lowPoint;
  }

  void _animateTo({
    required double target,
    required double heightVelocity,
    required double maxHeight,
  }) {
    _cancelInertia();
    if (target > proxyPanelMinHeight + 8) {
      _openForBack = true;
      _ensureHistoryEntry();
    }
    final startHeight = _height
        .clamp(proxyPanelMinHeight, maxHeight)
        .toDouble();
    if ((target - startHeight).abs() <= 0.5 &&
        heightVelocity.abs() <= _proxyPanelInertiaMinVelocity) {
      _setDragging(false);
      _dragDirection = 0;
      _height = target;
      _publishCurrentMetrics();
      _completeAnimationTarget(target);
      return;
    }
    final controller = AnimationController.unbounded(
      vsync: this,
      value: startHeight,
    );
    _inertiaController = controller;
    controller.addListener(() {
      final nextHeight = controller.value
          .clamp(proxyPanelMinHeight, maxHeight)
          .toDouble();
      _setDragging(true);
      _dragDirection = target > startHeight ? 1 : -1;
      _height = nextHeight;
      _publishCurrentMetrics();
    });
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) {
        return;
      }
      controller.dispose();
      if (identical(_inertiaController, controller)) {
        _inertiaController = null;
      }
      _setDragging(false);
      _dragDirection = 0;
      _height = target;
      _publishCurrentMetrics();
      _completeAnimationTarget(target);
    });
    controller.animateWith(
      SpringSimulation(_proxyPanelSpring, startHeight, target, heightVelocity),
    );
  }

  void _completeAnimationTarget(double target) {
    if (target <= proxyPanelMinHeight + 0.5) {
      _openForBack = false;
      _backCloseInProgress = false;
      _removeHistoryEntry();
      _resetListScroll();
    } else {
      _backCloseInProgress = false;
    }
  }

  void _finishSettle({
    required double viewportHeight,
    required double maxHeight,
  }) {
    final closeThreshold = _closeThreshold(
      viewportHeight: viewportHeight,
      maxHeight: maxHeight,
    );
    final target = _height <= closeThreshold ? proxyPanelMinHeight : maxHeight;
    _animateTo(target: target, heightVelocity: 0, maxHeight: maxHeight);
  }

  double _closeThreshold({
    required double viewportHeight,
    required double maxHeight,
  }) {
    final viewportThreshold = viewportHeight * _proxyPanelSettleCloseRatio;
    if (maxHeight > viewportThreshold) {
      return viewportThreshold;
    }
    return proxyPanelMinHeight +
        (maxHeight - proxyPanelMinHeight) * _proxyPanelCompactSettleCloseRatio;
  }

  void _cancelInertia() {
    final controller = _inertiaController;
    if (controller == null) {
      return;
    }
    final currentHeight = controller.value
        .clamp(proxyPanelMinHeight, double.infinity)
        .toDouble();
    final currentDirection = controller.velocity > 0
        ? 1
        : controller.velocity < 0
        ? -1
        : _dragDirection;
    _inertiaController = null;
    controller.stop();
    controller.dispose();
    if (!mounted) {
      return;
    }
    _setDragging(true);
    _dragDirection = currentDirection;
    _height = currentHeight;
    _publishCurrentMetrics();
  }

  void _toggle(double viewportHeight, {double topInset = 0}) {
    _cancelInertia();
    if (viewportHeight <= 0) {
      return;
    }
    final maxHeight = _maxHeight(viewportHeight, topInset: topInset);
    if (maxHeight <= proxyPanelMinHeight + 0.5) {
      return;
    }
    final target = _height <= proxyPanelMinHeight + 8
        ? maxHeight
        : proxyPanelMinHeight;
    _animateTo(target: target, heightVelocity: 0, maxHeight: maxHeight);
  }

  void _ensureHistoryEntry() {
    if (_historyEntry != null || !mounted) {
      return;
    }
    final route = _route;
    if (route == null) {
      return;
    }
    late final LocalHistoryEntry entry;
    entry = LocalHistoryEntry(
      onRemove: () {
        if (identical(_historyEntry, entry)) {
          _historyEntry = null;
        }
        if (_historyRemovalInProgress || !mounted) {
          return;
        }
        final routeContext = _routeContext;
        if (routeContext == null) {
          return;
        }
        final viewportHeight = _layoutViewportHeight(routeContext);
        final topInset = MediaQuery.paddingOf(routeContext).top;
        final maxHeight = _maxHeight(viewportHeight, topInset: topInset);
        _backCloseInProgress = true;
        _animateTo(
          target: proxyPanelMinHeight,
          heightVelocity: 0,
          maxHeight: maxHeight,
        );
      },
    );
    _historyEntry = entry;
    route.addLocalHistoryEntry(entry);
  }

  void _removeHistoryEntry() {
    final entry = _historyEntry;
    if (entry == null) {
      return;
    }
    _historyEntry = null;
    _historyRemovalInProgress = true;
    entry.remove();
    _historyRemovalInProgress = false;
  }

  void _closeFromBack() {
    final routeContext = _routeContext;
    if (routeContext == null) {
      return;
    }
    final viewportHeight = _layoutViewportHeight(routeContext);
    final topInset = MediaQuery.paddingOf(routeContext).top;
    final maxHeight = _maxHeight(viewportHeight, topInset: topInset);
    _backCloseInProgress = true;
    _animateTo(
      target: proxyPanelMinHeight,
      heightVelocity: 0,
      maxHeight: maxHeight,
    );
  }

  void _scheduleHistorySync(bool panelOpen) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (panelOpen) {
        if (!_backCloseInProgress) {
          _ensureHistoryEntry();
        }
      } else if (_historyEntry != null) {
        _removeHistoryEntry();
      }
    });
  }

  void _resetListScroll() {
    if (!_listController.hasClients) {
      return;
    }
    for (final position in _listController.positions) {
      if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
        position.jumpTo(position.minScrollExtent);
      }
    }
  }

  double _maxHeight(double viewportHeight, {double topInset = 0}) {
    if (viewportHeight <= proxyPanelMinHeight) {
      return proxyPanelMinHeight;
    }
    final viewportLimit = _viewportLimit(viewportHeight, topInset: topInset);
    final rowCount = widget.visibleRows;
    if (rowCount <= 0) {
      return proxyPanelMinHeight;
    }
    if (widget.hasActiveProfile && rowCount <= 1) {
      return viewportLimit;
    }
    final contentHeight =
        _proxyPanelHeaderHeight +
        rowCount * _proxyPanelRowHeight +
        _proxyPanelContentBottomPadding;
    final maxForContent = contentHeight
        .clamp(proxyPanelMinHeight, viewportLimit)
        .toDouble();
    return maxForContent >= viewportLimit * .88 ? viewportLimit : maxForContent;
  }

  double _viewportLimit(double viewportHeight, {double topInset = 0}) {
    if (viewportHeight <= proxyPanelMinHeight) {
      return proxyPanelMinHeight;
    }
    final topReserve = (topInset + _proxyPanelStatusBarGap)
        .clamp(0.0, viewportHeight - proxyPanelMinHeight)
        .toDouble();
    return viewportHeight - topReserve;
  }

  double _layoutViewportHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context).height;
    final bottomInset = appSystemNavigationBarInset(context);
    return (size - bottomInset)
        .clamp(proxyPanelMinHeight, double.infinity)
        .toDouble();
  }

  ProxyPanelMetrics _metricsForCurrentLayout() {
    final maxPanelHeight = _maxHeight(
      _lastViewportHeight,
      topInset: _lastTopInset,
    );
    final viewportLimit = _viewportLimit(
      _lastViewportHeight,
      topInset: _lastTopInset,
    );
    final panelHeight = _height
        .clamp(proxyPanelMinHeight, maxPanelHeight)
        .toDouble();
    final progressDenominator = maxPanelHeight - proxyPanelMinHeight;
    final progress = progressDenominator <= 0
        ? 0.0
        : ((panelHeight - proxyPanelMinHeight) / progressDenominator)
              .clamp(0.0, 1.0)
              .toDouble();
    final animating = _inertiaController != null;
    return ProxyPanelMetrics(
      bottomInset: _lastBottomInset,
      panelHeight: panelHeight,
      maxPanelHeight: maxPanelHeight,
      viewportHeight: _lastViewportHeight,
      viewportLimit: viewportLimit,
      progress: progress,
      backdropProgress: Curves.easeOutCubic.transform(progress),
      atMaxExtent: progress >= .985,
      canFillScreen: maxPanelHeight >= viewportLimit - 0.5,
      collapseOnAnyDownwardDrag:
          maxPanelHeight < viewportLimit - 0.5 || widget.visibleRows <= 3,
      dragging: _dragging,
      animating: animating,
    );
  }

  void _publishCurrentMetrics() {
    _metricsNotifier.value = _metricsForCurrentLayout();
  }

  @override
  Widget build(BuildContext context) {
    _routeContext = context;
    _route = ModalRoute.of(context);
    _lastViewportHeight = _layoutViewportHeight(context);
    _lastTopInset = MediaQuery.paddingOf(context).top;
    _lastBottomInset = appSystemNavigationBarInset(context);
    final metrics = _metricsForCurrentLayout();
    if (_metricsNotifier.value != metrics) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _metricsNotifier.value = metrics;
        }
      });
    }
    final openForBack =
        metrics.panelHeight > proxyPanelMinHeight + 8 || metrics.animating;
    if (openForBack != (_historyEntry != null)) {
      _scheduleHistorySync(openForBack);
    }
    final gestures = ProxyPanelGestures(
      onInteractionStart: _cancelInertia,
      onDragUpdate: (details) {
        _drag(details.delta.dy, _lastViewportHeight, topInset: _lastTopInset);
      },
      onDragEnd: (details) {
        _settle(details, _lastViewportHeight, topInset: _lastTopInset);
      },
      onHeaderTap: () => _toggle(_lastViewportHeight, topInset: _lastTopInset),
    );

    final rootChild = !widget.ready
        ? widget.loading
        : !widget.onboardingCompleted
        ? widget.welcome
        : _buildShell(context, metrics, gestures);

    return PopScope(
      canPop: !_openForBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_openForBack) {
          return;
        }
        _closeFromBack();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: rootChild,
      ),
    );
  }

  Widget _buildShell(
    BuildContext context,
    ProxyPanelMetrics metrics,
    ProxyPanelGestures gestures,
  ) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('shell'),
      extendBody: true,
      body: Stack(
        children: [
          RepaintBoundary(
            child: widget.homeBuilder(context, metrics, gestures),
          ),
          ValueListenableBuilder<ProxyPanelMetrics>(
            valueListenable: _metricsNotifier,
            builder: (context, metrics, _) {
              return IgnorePointer(
                ignoring: metrics.progress <= .02 && !metrics.animating,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (_) => _cancelInertia(),
                  onVerticalDragStart: (_) => _cancelInertia(),
                  onVerticalDragUpdate: gestures.onDragUpdate,
                  onVerticalDragEnd: gestures.onDragEnd,
                  onTap: () {
                    if (metrics.progress <= .02 && !metrics.animating) {
                      return;
                    }
                    _animateTo(
                      target: proxyPanelMinHeight,
                      heightVelocity: 0,
                      maxHeight: metrics.maxPanelHeight,
                    );
                  },
                  child: ColoredBox(
                    color: Colors.black.withValues(
                      alpha:
                          metrics.backdropProgress *
                          (theme.brightness == Brightness.dark ? .22 : .16),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<ProxyPanelMetrics>(
            valueListenable: _metricsNotifier,
            child: RepaintBoundary(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(proxyPanelScreenCornerRadius),
                ),
                clipBehavior: Clip.hardEdge,
                child: widget.sheetBuilder(
                  context,
                  metrics,
                  _metricsNotifier,
                  _listController,
                  gestures,
                ),
              ),
            ),
            builder: (context, metrics, child) {
              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: metrics.panelHeight + metrics.bottomInset,
                child: child!,
              );
            },
          ),
        ],
      ),
    );
  }
}
