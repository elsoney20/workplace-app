/// Public card for an employee (never contains a phone number).
class Person {
  const Person({
    required this.id,
    required this.fullName,
    this.jobTitle,
    this.avatarPath,
  });

  factory Person.fromJson(Map<String, dynamic>? json) => Person(
    id: json?['id'] as String? ?? '',
    fullName: json?['full_name'] as String? ?? '?',
    jobTitle: json?['job_title'] as String?,
    avatarPath: json?['avatar_path'] as String?,
  );

  final String id;
  final String fullName;
  final String? jobTitle;
  final String? avatarPath;

  /// One or two letters for the round avatar.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    String firstLetter(String word) => String.fromCharCodes(word.runes.take(1));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final letters =
        firstLetter(parts.first) +
        (parts.length > 1 ? firstLetter(parts[1]) : '');
    return letters.toUpperCase();
  }
}
