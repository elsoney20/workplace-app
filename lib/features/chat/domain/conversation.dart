import '../../feed/domain/person.dart';

/// One row of the chat list (`public.list_conversations()`).
class Conversation {
  const Conversation({
    required this.id,
    required this.isGroup,
    required this.memberCount,
    this.title,
    this.otherPerson,
    this.isOwner = false,
    this.muted = false,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'];
    final other = json['other_person'];
    return Conversation(
      id: json['id'] as String,
      isGroup: json['kind'] == 'group',
      title: json['title'] as String?,
      otherPerson: other is Map
          ? Person.fromJson(Map<String, dynamic>.from(other))
          : null,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      isOwner: json['my_role'] == 'owner',
      muted: json['muted'] as bool? ?? false,
      lastMessage: last is Map
          ? LastMessage.fromJson(Map<String, dynamic>.from(last))
          : null,
      lastMessageAt: json['last_message_at'] == null
          ? null
          : DateTime.parse(json['last_message_at'] as String).toLocal(),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final bool isGroup;
  final String? title;

  /// The other person in a 1:1 chat.
  final Person? otherPerson;
  final int memberCount;
  final bool isOwner;
  final bool muted;
  final LastMessage? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  String get displayName =>
      isGroup ? (title ?? '…') : (otherPerson?.fullName ?? '…');

  /// Avatar stand-in for group chats.
  Person get avatarPerson =>
      otherPerson ?? Person(id: id, fullName: title ?? '#');
}

class LastMessage {
  const LastMessage({
    required this.body,
    required this.senderId,
    required this.senderName,
    required this.deleted,
    required this.hasAttachment,
  });

  factory LastMessage.fromJson(Map<String, dynamic> json) => LastMessage(
    body: json['body'] as String? ?? '',
    senderId: json['sender_id'] as String? ?? '',
    senderName: json['sender_name'] as String? ?? '',
    deleted: json['deleted'] as bool? ?? false,
    hasAttachment: json['has_attachment'] as bool? ?? false,
  );

  final String body;
  final String senderId;
  final String senderName;
  final bool deleted;
  final bool hasAttachment;
}
