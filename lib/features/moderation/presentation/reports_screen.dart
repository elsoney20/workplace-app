import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../feed/domain/rich_text.dart';
import '../../feed/presentation/feed_format.dart';
import '../../feed/presentation/person_avatar.dart';
import '../../feed/presentation/post_screen.dart';
import '../data/moderation_repository.dart';

/// Moderation queue. Admins see every report; group moderators see reports
/// about their groups (the database decides, see list_reports).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  static const String routePath = '/reports';
  static const String routeName = 'reports';

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportStatus _status = ReportStatus.open;

  Future<void> _handle(
    ContentReport r,
    ReportStatus status, {
    bool delete = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(moderationRepositoryProvider)
          .handle(r.id, status, deleteContent: delete);
      ref.invalidate(reportsProvider);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorUnknown)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reports = ref.watch(reportsProvider(_status));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportsTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<ReportStatus>(
                  segments: [
                    ButtonSegment(
                      value: ReportStatus.open,
                      label: Text(l10n.reportOpen),
                    ),
                    ButtonSegment(
                      value: ReportStatus.resolved,
                      label: Text(l10n.reportResolved),
                    ),
                    ButtonSegment(
                      value: ReportStatus.dismissed,
                      label: Text(l10n.reportDismissed),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
              ),
              Expanded(
                child: reports.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(
                    child: TextButton(
                      onPressed: () => ref.invalidate(reportsProvider),
                      child: Text(l10n.retry),
                    ),
                  ),
                  data: (list) => list.isEmpty
                      ? Center(child: Text(l10n.reportsEmpty))
                      : RefreshIndicator(
                          onRefresh: () async =>
                              ref.invalidate(reportsProvider),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final r = list[i];
                              final author = r.contentAuthor;
                              return Card(
                                key: Key('report-${r.id}'),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: author == null
                                            ? null
                                            : PersonAvatar(author),
                                        title: Text(author?.fullName ?? ''),
                                        subtitle: Text(
                                          [
                                            if (r.groupName != null)
                                              r.groupName!,
                                            timeAgo(context, r.createdAt),
                                          ].join(' · '),
                                        ),
                                        onTap: r.postId == null
                                            ? null
                                            : () => context.push(
                                                PostScreen.pathFor(r.postId!),
                                              ),
                                      ),
                                      Text(
                                        r.contentDeleted
                                            ? l10n.contentDeleted
                                            : plainText(r.content ?? ''),
                                        style: r.contentDeleted
                                            ? theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontStyle: FontStyle.italic,
                                                  )
                                            : theme.textTheme.bodyMedium,
                                      ),
                                      const Divider(height: 20),
                                      Text(
                                        l10n.reportedBy(r.reporter.fullName),
                                        style: theme.textTheme.labelMedium,
                                      ),
                                      if (r.reason.isNotEmpty)
                                        Text('“${r.reason}”'),
                                      if (r.status == ReportStatus.open)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Wrap(
                                            spacing: 8,
                                            children: [
                                              OutlinedButton(
                                                key: Key('dismiss-${r.id}'),
                                                onPressed: () => _handle(
                                                  r,
                                                  ReportStatus.dismissed,
                                                ),
                                                child: Text(l10n.dismissReport),
                                              ),
                                              FilledButton(
                                                key: Key(
                                                  'deleteReported-${r.id}',
                                                ),
                                                onPressed: r.contentDeleted
                                                    ? () => _handle(
                                                        r,
                                                        ReportStatus.resolved,
                                                      )
                                                    : () => _handle(
                                                        r,
                                                        ReportStatus.resolved,
                                                        delete: true,
                                                      ),
                                                child: Text(
                                                  l10n.deleteAndResolve,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
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
