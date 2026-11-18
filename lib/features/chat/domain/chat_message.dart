import '../../feed/domain/person.dart';
import '../../feed/domain/post_attachment.dart';

/// One message (`public.get_messages()`).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.body,
    required this.createdAt,
    this.replyTo,
    this.editedAt,
    this.deletedAt,
    this.attachments = const [],
    this.reactions = const {},
    this.recipientCount = 0,
    this.deliveredCount = 0,
    this.seenCount = 0,
    this.pending = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final reply = json['reply_to'];
    final reactions = json['reactions'];
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      sender: Person.fromJson(
        json['sender'] is Map
            ? Map<String, dynamic>.from(json['sender'] as Map)
            : null,
      ),
      body: json['body'] as String? ?? '',
      replyTo: reply is Map
          ? QuotedMessage.fromJson(Map<String, dynamic>.from(reply))
          : null,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      editedAt: json['edited_at'] == null
          ? null
          : DateTime.parse(json['edited_at'] as String).toLocal(),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String).toLocal(),
      attachments: [
        for (final a in (json['attachments'] as List? ?? const []))
          PostAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
      ],
      reactions: reactions is Map
          ? {
              for (final e in reactions.entries)
                e.key as String: [
                  for (final id in e.value as List) id as String,
                ],
            }
          : const {},
      recipientCount: (json['recipient_count'] as num?)?.toInt() ?? 0,
      deliveredCount: (json['delivered_count'] as num?)?.toInt() ?? 0,
      seenCount: (json['seen_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String conversationId;
  final Person sender;
  final String body;
  final QuotedMessage? replyTo;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final List<PostAttachment> attachments;

  /// emoji -> profile ids who reacted with it.
  final Map<String, List<String>> reactions;
  final int recipientCount;
  final int deliveredCount;
  final int seenCount;

  /// Shown immediately while it is being sent.
  final bool pending;

  bool get isDeleted => deletedAt != null;

  ReceiptStatus get status {
    if (pending) return ReceiptStatus.sending;
    if (recipientCount > 0 && seenCount >= recipientCount) {
      return ReceiptStatus.seen;
    }
    if (recipientCount > 0 && deliveredCount >= recipientCount) {
      return ReceiptStatus.delivered;
    }
    return ReceiptStatus.sent;
  }
}

/// ⏱ sending, ✓ sent, ✓✓ grey delivered, ✓✓ blue seen (by everyone).
enum ReceiptStatus { sending, sent, delivered, seen }

class QuotedMessage {
  const QuotedMessage({
    required this.id,
    required this.body,
    required this.senderName,
    required this.deleted,
  });

  factory QuotedMessage.fromJson(Map<String, dynamic> json) => QuotedMessage(
    id: json['id'] as String,
    body: json['body'] as String? ?? '',
    senderName: json['sender_name'] as String? ?? '',
    deleted: json['deleted'] as bool? ?? false,
  );

  final String id;
  final String body;
  final String senderName;
  final bool deleted;
}

class MessageReceipt {
  const MessageReceipt(this.person, this.deliveredAt, this.seenAt);
  final Person person;
  final DateTime? deliveredAt;
  final DateTime? seenAt;
}
