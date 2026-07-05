import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';

class ReleaseNotesCard extends StatelessWidget {
  const ReleaseNotesCard({
    super.key,
    required this.body,
    this.margin = EdgeInsets.zero,
  });

  final String body;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lines = _releaseNoteLines(body);
    return Card(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.updatesReleaseNotesTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(12),
            if (lines.isEmpty)
              Text(
                l10n.updatesNoReleaseNotes,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...lines.map((line) => _ReleaseNoteLine(line: line)),
          ],
        ),
      ),
    );
  }
}

class _ReleaseNoteLine extends StatelessWidget {
  const _ReleaseNoteLine({required this.line});

  final _ReleaseLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textStyle = switch (line.kind) {
      _ReleaseLineKind.heading => theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w900,
      ),
      _ReleaseLineKind.bullet => theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
        height: 1.35,
      ),
      _ReleaseLineKind.paragraph => theme.textTheme.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant,
        height: 1.35,
      ),
    };
    if (line.kind == _ReleaseLineKind.bullet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const Gap(10),
            Expanded(child: Text(line.text, style: textStyle)),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(
        top: line.kind == _ReleaseLineKind.heading ? 8 : 0,
        bottom: line.kind == _ReleaseLineKind.heading ? 8 : 10,
      ),
      child: Text(line.text, style: textStyle),
    );
  }
}

enum _ReleaseLineKind { heading, bullet, paragraph }

class _ReleaseLine {
  const _ReleaseLine(this.kind, this.text);

  final _ReleaseLineKind kind;
  final String text;
}

List<_ReleaseLine> _releaseNoteLines(String body) {
  final trimmedBody = body.trim();
  if (trimmedBody.isEmpty) return const <_ReleaseLine>[];
  final limited = trimmedBody.length > 6000
      ? '${trimmedBody.substring(0, 6000)}...'
      : trimmedBody;
  final lines = <_ReleaseLine>[];
  for (final raw in limited.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      lines.add(
        _ReleaseLine(
          _ReleaseLineKind.heading,
          line.replaceFirst(RegExp(r'^#+\s*'), ''),
        ),
      );
    } else if (line.startsWith('- ') ||
        line.startsWith('* ') ||
        RegExp(r'^\d+\.\s+').hasMatch(line)) {
      lines.add(
        _ReleaseLine(
          _ReleaseLineKind.bullet,
          line
              .replaceFirst(RegExp(r'^[-*]\s+'), '')
              .replaceFirst(RegExp(r'^\d+\.\s+'), ''),
        ),
      );
    } else {
      lines.add(_ReleaseLine(_ReleaseLineKind.paragraph, line));
    }
    if (lines.length >= 48) break;
  }
  return lines;
}
