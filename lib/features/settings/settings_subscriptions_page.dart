import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hydrabox/data/local/app_settings_store.dart';
import 'package:hydrabox/data/subscription/happ_crypto_link.dart';
import 'package:hydrabox/features/settings/settings_ui.dart';
import 'package:hydrabox/l10n/generated/app_localizations.dart';
import 'package:hydrabox/logging/app_log_store.dart';
import 'package:hydrabox/models/subscription.dart';
import 'package:hydrabox/singbox/singbox_runtime.dart';
import 'package:hydrabox/widgets/progressive_blur_scaffold.dart';

class SettingsSubscriptionsPage extends StatefulWidget {
  const SettingsSubscriptionsPage({
    super.key,
    required this.currentConfig,
    required this.currentLocationLookupLimit,
    required this.currentLocationLookupTimeoutSeconds,
    required this.currentLocationLookupConcurrency,
    required this.onChanged,
    required this.onLocationLookupLimitChanged,
    required this.onLocationLookupTimeoutSecondsChanged,
    required this.onLocationLookupConcurrencyChanged,
  });

  final UrlTestConfig currentConfig;
  final int currentLocationLookupLimit;
  final int currentLocationLookupTimeoutSeconds;
  final int currentLocationLookupConcurrency;
  final ValueChanged<UrlTestConfig> onChanged;
  final ValueChanged<int> onLocationLookupLimitChanged;
  final ValueChanged<int> onLocationLookupTimeoutSecondsChanged;
  final ValueChanged<int> onLocationLookupConcurrencyChanged;

  @override
  State<SettingsSubscriptionsPage> createState() =>
      _SettingsSubscriptionsPageState();
}

class _SettingsSubscriptionsPageState extends State<SettingsSubscriptionsPage> {
  late final TextEditingController _urlController;
  String _androidId = '';
  bool _loadingAndroidId = true;
  bool _loadingHappSupport = true;
  bool _happCrypt5Supported = false;
  late int _intervalSeconds;
  late int _timeoutSeconds;
  late int _concurrency;
  late int _unavailableCheckIntervalSeconds;
  late int _locationLookupLimit;
  late int _locationLookupTimeoutSeconds;
  late int _locationLookupConcurrency;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: widget.currentConfig.url ?? '',
    );
    _intervalSeconds = widget.currentConfig.intervalSeconds ?? 900;
    _timeoutSeconds = widget.currentConfig.timeoutSeconds ?? 10;
    _concurrency = (widget.currentConfig.concurrency ?? 4).clamp(1, 8);
    _unavailableCheckIntervalSeconds =
        (widget.currentConfig.unavailableCheckIntervalSeconds ?? 120)
            .clamp(120, 3600)
            .toInt();
    _locationLookupLimit = widget.currentLocationLookupLimit
        .clamp(0, 50)
        .toInt();
    _locationLookupTimeoutSeconds = widget.currentLocationLookupTimeoutSeconds
        .clamp(2, 30)
        .toInt();
    _locationLookupConcurrency = widget.currentLocationLookupConcurrency
        .clamp(1, 60)
        .toInt();
    _loadAndroidId();
    _loadHappSupport();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadAndroidId() async {
    final androidId = await SingboxRuntime.instance.getAndroidId();
    if (!mounted) return;
    setState(() {
      _androidId = androidId;
      _loadingAndroidId = false;
    });
  }

  Future<void> _loadHappSupport() async {
    final support = await HappCryptoLinkDecoder.getCrypt5Support();
    if (support.supported) {
      AppLogStore.info('happ crypto', support.detail);
    } else {
      AppLogStore.warning('happ crypto', support.detail);
    }
    if (!mounted) return;
    setState(() {
      _happCrypt5Supported = support.supported;
      _loadingHappSupport = false;
    });
  }

  void _commitUrlTest() {
    final url = _urlController.text.trim();
    widget.onChanged(
      UrlTestConfig(
        url: url.isEmpty ? null : url,
        intervalSeconds: _intervalSeconds,
        timeoutSeconds: _timeoutSeconds,
        concurrency: _concurrency,
        unavailableCheckIntervalSeconds: _unavailableCheckIntervalSeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final resolvedInterval = _intervalSeconds.toString();
    final resolvedTimeout = _timeoutSeconds.toString();
    final resolvedConcurrency = _concurrency.toString();
    final resolvedUnavailableCheckInterval = _unavailableCheckIntervalSeconds
        .toString();
    final resolvedLocationLookupLimit = _locationLookupLimit == 0
        ? l10n.disabledLabel
        : _locationLookupLimit.toString();
    final resolvedLocationLookupTimeout = l10n.settingsSecondsShort(
      _locationLookupTimeoutSeconds,
    );
    final resolvedLocationLookupConcurrency = _locationLookupConcurrency
        .toString();
    final happStatusColor = _happCrypt5Supported
        ? const Color(0xFF1F9D63)
        : cs.error;
    final happStatusText = _loadingHappSupport
        ? l10n.loading
        : (_happCrypt5Supported
              ? l10n.happCrypt5Supported
              : l10n.happCrypt5Unsupported);
    final happDescription = _loadingHappSupport
        ? l10n.happCrypt5Checking
        : _happCrypt5Supported
        ? l10n.happCrypt5SupportedDescription
        : l10n.happCrypt5UnsupportedDescription;

    return ProgressiveBlurScaffold(
      appBar: AppBar(title: Text(l10n.settingsProfilesChecksTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          settingsScreenPadding.left,
          progressiveHeaderTopPadding(context, settingsScreenPadding.top),
          settingsScreenPadding.right,
          appBottomSafePadding(context, settingsScreenPadding.bottom),
        ),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SettingsLeadingIcon(
                        icon: Icons.speed_rounded,
                        color: cs.primary,
                        size: 44,
                        iconSize: 22,
                      ),
                      const Gap(14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Пинг',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(2),
                            Text(
                              'Как приложение проверяет жив ли ключ',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(18),
                  TextField(
                    controller: _urlController,
                    onTapOutside: (_) {
                      FocusScope.of(context).unfocus();
                      _commitUrlTest();
                    },
                    onSubmitted: (_) => _commitUrlTest(),
                    onEditingComplete: () {
                      FocusScope.of(context).unfocus();
                      _commitUrlTest();
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.urlTestUrlTitle,
                      hintText: defaultUrlTestUrl,
                    ),
                  ),
                  const Gap(6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      l10n.urlTestUrlSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Gap(14),
                  Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: .5),
                  ),
                  const Gap(14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Интервал проверки',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$resolvedInterval сек.',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    'Как часто приложение перепроверяет доступность ключа для авто-выбора.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Gap(10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: cs.onSurface.withValues(alpha: .12),
                      thumbColor: cs.primary,
                      overlayColor: cs.primary.withValues(alpha: .10),
                      showValueIndicator: ShowValueIndicator.never,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _intervalSeconds.toDouble(),
                      min: 30,
                      max: 600,
                      divisions: 19,
                      label: '$resolvedInterval сек.',
                      onChanged: (value) {
                        setState(() {
                          _intervalSeconds = value.round();
                        });
                      },
                      onChangeEnd: (_) => _commitUrlTest(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        Text(
                          '30 с',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '600 с',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(14),
                  Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: .5),
                  ),
                  const Gap(14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.urlTestTimeoutTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.tertiary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$resolvedTimeout сек.',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.tertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    l10n.urlTestTimeoutSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Gap(10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: cs.tertiary,
                      inactiveTrackColor: cs.onSurface.withValues(alpha: .12),
                      thumbColor: cs.tertiary,
                      overlayColor: cs.tertiary.withValues(alpha: .10),
                      showValueIndicator: ShowValueIndicator.never,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _timeoutSeconds.toDouble(),
                      min: 1,
                      max: 60,
                      divisions: 59,
                      label: '$resolvedTimeout сек.',
                      onChanged: (value) {
                        setState(() {
                          _timeoutSeconds = value.round();
                        });
                      },
                      onChangeEnd: (_) => _commitUrlTest(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        Text(
                          '1 с',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '60 с',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(14),
                  Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: .5),
                  ),
                  const Gap(14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.urlTestConcurrencyTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          resolvedConcurrency,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    l10n.urlTestConcurrencySubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Gap(10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: cs.onSurface.withValues(alpha: .12),
                      thumbColor: cs.primary,
                      overlayColor: cs.primary.withValues(alpha: .10),
                      showValueIndicator: ShowValueIndicator.never,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _concurrency.toDouble(),
                      min: 1,
                      max: 8,
                      divisions: 7,
                      label: resolvedConcurrency,
                      onChanged: (value) {
                        setState(() {
                          _concurrency = value.round();
                        });
                      },
                      onChangeEnd: (_) => _commitUrlTest(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        Text(
                          '1',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '8',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(14),
                  Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: .5),
                  ),
                  const Gap(14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.urlTestSingleRetestTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$resolvedUnavailableCheckInterval сек.',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.secondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    l10n.urlTestSingleRetestSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Gap(10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: cs.secondary,
                      inactiveTrackColor: cs.onSurface.withValues(alpha: .12),
                      thumbColor: cs.secondary,
                      overlayColor: cs.secondary.withValues(alpha: .10),
                      showValueIndicator: ShowValueIndicator.never,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _unavailableCheckIntervalSeconds.toDouble(),
                      min: 120,
                      max: 3600,
                      divisions: 58,
                      label: '$resolvedUnavailableCheckInterval сек.',
                      onChanged: (value) {
                        setState(() {
                          _unavailableCheckIntervalSeconds = value.round();
                        });
                      },
                      onChangeEnd: (_) => _commitUrlTest(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        Text(
                          '120 с',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '3600 с',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(settingsIslandGap),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SettingsLeadingIcon(
                        icon: Icons.travel_explore_rounded,
                        color: cs.tertiary,
                        size: 44,
                      ),
                      const Gap(14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.locationLookupTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(2),
                            Text(
                              l10n.locationLookupSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.locationLookupLimitTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.tertiary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          resolvedLocationLookupLimit,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.tertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    l10n.locationLookupLimitSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Gap(10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: cs.tertiary,
                      inactiveTrackColor: cs.onSurface.withValues(alpha: .12),
                      thumbColor: cs.tertiary,
                      overlayColor: cs.tertiary.withValues(alpha: .10),
                      showValueIndicator: ShowValueIndicator.never,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _locationLookupLimit.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      label: resolvedLocationLookupLimit,
                      onChanged: (value) {
                        setState(() {
                          _locationLookupLimit = value.round();
                        });
                      },
                      onChangeEnd: (value) =>
                          widget.onLocationLookupLimitChanged(value.round()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Row(
                      children: [
                        Text(
                          '0',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '30',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(18),
                  Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: .5),
                  ),
                  const Gap(14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.locationLookupTimeoutTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.tertiary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          resolvedLocationLookupTimeout,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.tertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    l10n.locationLookupTimeoutSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Gap(10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: cs.tertiary,
                      inactiveTrackColor: cs.onSurface.withValues(alpha: .12),
                      thumbColor: cs.tertiary,
                      overlayColor: cs.tertiary.withValues(alpha: .10),
                      showValueIndicator: ShowValueIndicator.never,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _locationLookupTimeoutSeconds.toDouble(),
                      min: 2,
                      max: 30,
                      divisions: 28,
                      label: resolvedLocationLookupTimeout,
                      onChanged: (value) {
                        setState(() {
                          _locationLookupTimeoutSeconds = value.round();
                        });
                      },
                      onChangeEnd: (value) => widget
                          .onLocationLookupTimeoutSecondsChanged(value.round()),
                    ),
                  ),
                  const Gap(14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.locationLookupConcurrencyTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.tertiary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          resolvedLocationLookupConcurrency,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.tertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    l10n.locationLookupConcurrencySubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const Gap(10),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: cs.tertiary,
                      inactiveTrackColor: cs.onSurface.withValues(alpha: .12),
                      thumbColor: cs.tertiary,
                      overlayColor: cs.tertiary.withValues(alpha: .10),
                      showValueIndicator: ShowValueIndicator.never,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                      activeTickMarkColor: Colors.transparent,
                      inactiveTickMarkColor: Colors.transparent,
                    ),
                    child: Slider(
                      value: _locationLookupConcurrency.toDouble(),
                      min: 1,
                      max: 60,
                      divisions: 59,
                      label: resolvedLocationLookupConcurrency,
                      onChanged: (value) {
                        setState(() {
                          _locationLookupConcurrency = value.round();
                        });
                      },
                      onChangeEnd: (value) => widget
                          .onLocationLookupConcurrencyChanged(value.round()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(settingsIslandGap),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SettingsLeadingIcon(
                        icon: Icons.auto_awesome_rounded,
                        color: cs.primary,
                        size: 44,
                      ),
                      const Gap(14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Happ',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(2),
                            Text(
                              'Импорт и совместимость',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.key_rounded,
                          color: cs.primary,
                          size: 18,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Crypt5',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const Gap(12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: happStatusColor.withValues(
                                      alpha: .12,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    happStatusText,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: happStatusColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const Gap(6),
                            Text(
                              'Локальная дешифровка Happ crypto link',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const Gap(10),
                            Text(
                              happDescription,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Gap(settingsIslandGap),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.fingerprint_rounded,
                          color: cs.primary,
                        ),
                      ),
                      const Gap(14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.hwidTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Gap(2),
                            Text(
                              l10n.hwidSubtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.hwidValueTitle,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Gap(6),
                        SelectableText(
                          _loadingAndroidId
                              ? l10n.loading
                              : (_androidId.isEmpty ? '—' : _androidId),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
