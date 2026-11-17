import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../../feed/domain/person.dart';

/// open | resolved | dismissed (matches public.report_status).
enum ReportStatus { open, resolved, dismissed }

class ContentReport {
  const ContentReport({
    required this.id,
    required this.status,
    required this.reason,
    required this.createdAt,
    required this.reporter,
    this.handledBy,
    this.postId,
    this.commentId,
    this.content,
    this.contentAuthor,
    this.contentDeleted = false,
    this.groupName,
  });

  factory ContentReport.fromJson(Map<String, dynamic> j) => ContentReport(
    id: j['id'] as String,
    status: ReportStatus.values.byName(j['status'] as String? ?? 'open'),
    reason: j['reason'] as String? ?? '',
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    reporter: Person.fromJson(_map(j['reporter'])),
    handledBy: j['handled_by'] == null
        ? null
        : Person.fromJson(_map(j['handled_by'])),
    postId: j['post_id'] as String?,
    commentId: j['comment_id'] as String?,
    content: j['content'] as String?,
    contentAuthor: j['content_author'] == null
        ? null
        : Person.fromJson(_map(j['content_author'])),
    contentDeleted: j['content_deleted'] as bool? ?? false,
    groupName: j['group_name'] as String?,
  );

  static Map<String, dynamic>? _map(Object? v) =>
      v == null ? null : Map<String, dynamic>.from(v as Map);

  final String id;
  final ReportStatus status;
  final String reason;
  final DateTime createdAt;
  final Person reporter;
  final Person? handledBy;
  final String? postId;
  final String? commentId;
  final String? content;
  final Person? contentAuthor;
  final bool contentDeleted;
  final String? groupName;
}

class ModerationRepository {
  ModerationRepository(SupabaseClient client) : _clientOrNull = client;
  ModerationRepository.withoutClient() : _clientOrNull = null;

  final SupabaseClient? _clientOrNull;
  SupabaseClient get _client => _clientOrNull!;

  Future<void> report({
    String? postId,
    String? commentId,
    required String reason,
  }) => _client.rpc<void>(
    'report_content',
    params: {
      'p_post_id': postId,
      'p_comment_id': commentId,
      'p_reason': reason,
    },
  );

  Future<List<ContentReport>> list(ReportStatus? status) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_reports',
      params: {'p_status': status?.name},
    );
    return rows
        .map((r) => ContentReport.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> handle(
    String reportId,
    ReportStatus status, {
    bool deleteContent = false,
  }) => _client.rpc<void>(
    'handle_report',
    params: {
      'p_report_id': reportId,
      'p_status': status.name,
      'p_delete_content': deleteContent,
    },
  );
}

final moderationRepositoryProvider = Provider<ModerationRepository>(
  (ref) => ModerationRepository(ref.watch(supabaseClientProvider)),
);

final reportsProvider = FutureProvider.autoDispose
    .family<List<ContentReport>, ReportStatus>(
      (ref, status) => ref.watch(moderationRepositoryProvider).list(status),
    );
