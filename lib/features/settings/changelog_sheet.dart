import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:meow_client/data/update/app_update_service.dart';
import 'package:meow_client/l10n/generated/app_localizations.dart';
import 'package:meow_client/widgets/release_notes_card.dart';

class ChangelogSheet extends StatefulWidget {
  const ChangelogSheet({
    super.key,
    required this.currentVersion,
    required this.currentBuildNumber,
  });

  final String currentVersion;
  final int currentBuildNumber;

  @override
  State<ChangelogSheet> createState() => _ChangelogSheetState();
}

class _ChangelogSheetState extends State<ChangelogSheet> {
  late final Future<AppUpdateCheckResult> _future;

  @override
  void initState() {
    super.initState();
    _future = AppUpdateService.instance.checkForUpdates(
      currentVersion: widget.currentVersion,
      currentBuildNumber: widget.currentBuildNumber,
      manual: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final l10n = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .56,
      minChildSize: .34,
      maxChildSize: .90,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + bottomPadding),
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: .38),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const Gap(18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.updatesReleaseNotesTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.close,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(12),
              FutureBuilder<AppUpdateCheckResult>(
                future: _future,
                builder: (context, snapshot) {
                  final info = snapshot.data?.info;
                  if (info != null) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          info.displayVersion,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Gap(10),
                        ReleaseNotesCard(body: info.body),
                      ],
                    );
                  }
                  if (snapshot.hasError) {
                    return Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          snapshot.error.toString(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
