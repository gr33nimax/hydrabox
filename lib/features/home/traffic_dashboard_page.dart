import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/core/demo_utils.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/models/app_view_models.dart';
import 'package:meow_client/widgets/country_flag_badge.dart';

class TrafficDashboardPage extends StatelessWidget {
  const TrafficDashboardPage({
    super.key,
    required this.snapshotListenable,
    this.scrollController,
  });

  final ValueListenable<TrafficDashboardSnapshot> snapshotListenable;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TrafficDashboardSnapshot>(
      valueListenable: snapshotListenable,
      builder: (context, snapshot, _) {
        return _TrafficDashboardContent(
          snapshot: snapshot,
          scrollController: scrollController,
        );
      },
    );
  }
}

class _TrafficDashboardContent extends StatelessWidget {
  const _TrafficDashboardContent({
    required this.snapshot,
    required this.scrollController,
  });

  final TrafficDashboardSnapshot snapshot;
  final ScrollController? scrollController;

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

  String _uptimeText(AppLocalizations l10n) {
    final connectedSince = snapshot.connectedSince;
    if (!snapshot.connected || connectedSince == null) {
      return l10n.notAvailableShort;
    }
    final elapsed = DateTime.now().difference(connectedSince);
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60);
    final seconds = elapsed.inSeconds.remainder(60);
    if (hours > 0) {
      return l10n.trafficDashboardUptimeHours(hours, minutes);
    }
    if (minutes > 0) {
      return l10n.trafficDashboardUptimeMinutes(minutes, seconds);
    }
    return l10n.trafficDashboardUptimeSeconds(seconds);
  }

  String _connectionState(AppLocalizations l10n) {
    if (snapshot.connected) {
      return l10n.trafficDashboardStateConnected;
    }
    if (snapshot.connecting) {
      return l10n.trafficDashboardStateConnecting;
    }
    return l10n.trafficDashboardStateDisconnected;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final proxy = snapshot.activeProxy;
    final profile = snapshot.activeProfile;
    final ip = proxy?.ip.trim() ?? '';
    final displayIp = ip.isEmpty
        ? l10n.notAvailableShort
        : snapshot.hideServerIp
        ? _maskIp(ip)
        : ip;

    return SafeArea(
      top: false,
      child: Material(
        color: theme.scaffoldBackgroundColor,
        child: ListView(
          key: const ValueKey('traffic-dashboard'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: .32,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const Gap(16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.trafficDashboardTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Gap(4),
                Text(
                  l10n.trafficDashboardSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Gap(18),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: l10n.trafficDashboardDownload,
                    value: formatSpeed(snapshot.downlinkBps.toDouble()),
                    icon: Icons.arrow_downward_rounded,
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: _MetricCard(
                    label: l10n.trafficDashboardUpload,
                    value: formatSpeed(snapshot.uplinkBps.toDouble()),
                    icon: Icons.arrow_upward_rounded,
                  ),
                ),
              ],
            ),
            const Gap(10),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    label: l10n.trafficDashboardSessionTraffic,
                    value: formatBytes(snapshot.totalBytes.toDouble()),
                    icon: Icons.swap_vert_rounded,
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: _MetricCard(
                    label: l10n.trafficDashboardConnectedFor,
                    value: _uptimeText(l10n),
                    icon: Icons.timer_rounded,
                  ),
                ),
              ],
            ),
            const Gap(16),
            _TrafficGraphCard(samples: snapshot.samples),
            const Gap(16),
            _InfoSection(
              children: [
                _InfoRow(
                  label: l10n.trafficDashboardConnectionState,
                  value: _connectionState(l10n),
                ),
                _InfoRow(
                  label: l10n.trafficDashboardCurrentProfile,
                  value: profile?.name ?? l10n.notAvailableShort,
                ),
                _InfoRow(
                  label: l10n.trafficDashboardActiveProxy,
                  value: proxy?.displayName ?? l10n.notAvailableShort,
                  leading: proxy == null
                      ? null
                      : CountryFlagBadge(
                          countryCode: proxy.countryCode,
                          size: 22,
                        ),
                ),
                _InfoRow(
                  label: l10n.trafficDashboardServerIp,
                  value: displayIp,
                ),
                _InfoRow(
                  label: l10n.trafficDashboardDownloadTotal,
                  value: formatBytes(snapshot.downlinkTotalBytes.toDouble()),
                ),
                _InfoRow(
                  label: l10n.trafficDashboardUploadTotal,
                  value: formatBytes(snapshot.uplinkTotalBytes.toDouble()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const Gap(10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficGraphCard extends StatelessWidget {
  const _TrafficGraphCard({required this.samples});

  final List<TrafficSample> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    var maxDownload = 0;
    var maxUpload = 0;
    for (final sample in samples) {
      maxDownload = math.max(maxDownload, sample.downlinkBps);
      maxUpload = math.max(maxUpload, sample.uplinkBps);
    }
    final maxBps = math.max(1, math.max(maxDownload, maxUpload));
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.trafficDashboardGraphTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(6),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _GraphLegendItem(
                  color: theme.colorScheme.primary,
                  label: l10n.trafficDashboardDownload,
                  value: formatSpeed(maxDownload.toDouble()),
                ),
                _GraphLegendItem(
                  color: theme.colorScheme.tertiary,
                  label: l10n.trafficDashboardUpload,
                  value: formatSpeed(maxUpload.toDouble()),
                ),
                Text(
                  l10n.trafficDashboardGraphMax(formatSpeed(maxBps.toDouble())),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Gap(12),
            SizedBox(
              height: 128,
              width: double.infinity,
              child: CustomPaint(
                key: const ValueKey('traffic-dashboard-graph'),
                painter: _TrafficChartPainter(
                  samples: samples,
                  downloadColor: theme.colorScheme.primary,
                  uploadColor: theme.colorScheme.tertiary,
                  gridColor: theme.colorScheme.outlineVariant.withValues(
                    alpha: .45,
                  ),
                  maxBps: maxBps,
                  emptyTextColor: theme.colorScheme.onSurfaceVariant,
                  emptyText: l10n.trafficDashboardNoSamples,
                  textStyle: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphLegendItem extends StatelessWidget {
  const _GraphLegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const Gap(5),
        Text(
          '$label $value',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: children),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.leading});

  final String label;
  final String value;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Gap(12),
          if (leading != null) ...[leading!, const Gap(8)],
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficChartPainter extends CustomPainter {
  const _TrafficChartPainter({
    required this.samples,
    required this.downloadColor,
    required this.uploadColor,
    required this.gridColor,
    required this.maxBps,
    required this.emptyTextColor,
    required this.emptyText,
    required this.textStyle,
  });

  final List<TrafficSample> samples;
  final Color downloadColor;
  final Color uploadColor;
  final Color gridColor;
  final int maxBps;
  final Color emptyTextColor;
  final String emptyText;
  final TextStyle? textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (samples.length < 2) {
      final painter = TextPainter(
        text: TextSpan(
          text: emptyText,
          style: (textStyle ?? const TextStyle()).copyWith(
            color: emptyTextColor,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width);
      painter.paint(
        canvas,
        Offset(
          (size.width - painter.width) / 2,
          (size.height - painter.height) / 2,
        ),
      );
      return;
    }

    Path lineFor(int Function(TrafficSample sample) selector) {
      final path = Path();
      for (var i = 0; i < samples.length; i++) {
        final sample = samples[i];
        final x = samples.length == 1
            ? 0.0
            : size.width * i / (samples.length - 1);
        final value = selector(sample).clamp(0, maxBps);
        final y = size.height - size.height * value / maxBps;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    canvas.drawPath(
      lineFor((sample) => sample.downlinkBps),
      Paint()
        ..color = downloadColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      lineFor((sample) => sample.uplinkBps),
      Paint()
        ..color = uploadColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrafficChartPainter oldDelegate) {
    return oldDelegate.downloadColor != downloadColor ||
        oldDelegate.uploadColor != uploadColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.maxBps != maxBps ||
        oldDelegate.emptyTextColor != emptyTextColor ||
        oldDelegate.emptyText != emptyText ||
        !listEquals(oldDelegate.samples, samples);
  }
}
