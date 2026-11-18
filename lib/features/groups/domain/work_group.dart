import '../../feed/domain/person.dart';

enum GroupPrivacy {
  public,
  private;

  static GroupPrivacy fromName(String? name) =>
      name == 'private' ? private : public;
}

enum GroupRole {
  owner,
  moderator,
  member;

  static GroupRole? fromName(String? name) =>
      values.where((r) => r.name == name).firstOrNull;
}

/// A group as returned by `public.list_groups()`.
class WorkGroup {
  const WorkGroup({
    required this.id,
    required this.name,
    required this.privacy,
    required this.memberCount,
    required this.canModerate,
    this.description,
    this.departmentId,
    this.myRole,
    this.muted = false,
  });

  factory WorkGroup.fromJson(Map<String, dynamic> json) => WorkGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    privacy: GroupPrivacy.fromName(json['privacy'] as String?),
    departmentId: json['department_id'] as String?,
    memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    myRole: GroupRole.fromName(json['my_role'] as String?),
    canModerate: json['can_moderate'] as bool? ?? false,
    muted: json['muted'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String? description;
  final GroupPrivacy privacy;
  final String? departmentId;
  final int memberCount;
  final GroupRole? myRole;
  final bool canModerate;
  final bool muted;

  bool get isMember => myRole != null;
  bool get isDepartment => departmentId != null;
  bool get isOwner => myRole == GroupRole.owner;
}

class GroupMember {
  const GroupMember(this.person, this.role);

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
    Person.fromJson(Map<String, dynamic>.from(json['person'] as Map)),
    GroupRole.fromName(json['role'] as String?) ?? GroupRole.member,
  );

  final Person person;
  final GroupRole role;
}
