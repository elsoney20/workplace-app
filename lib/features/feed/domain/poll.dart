/// A quick poll inside a post (one choice per person, can be changed).
class PollOption {
  const PollOption({required this.id, required this.label, this.votes = 0});

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
    id: json['id'] as String,
    label: json['label'] as String? ?? '',
    votes: (json['votes'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String label;
  final int votes;
}

class Poll {
  const Poll({
    required this.question,
    required this.options,
    this.total = 0,
    this.myOption,
    this.closesAt,
  });

  factory Poll.fromJson(Map<String, dynamic> json) => Poll(
    question: json['question'] as String? ?? '',
    total: (json['total'] as num?)?.toInt() ?? 0,
    myOption: json['my_option'] as String?,
    closesAt: json['closes_at'] == null
        ? null
        : DateTime.parse(json['closes_at'] as String).toLocal(),
    options: [
      for (final o in (json['options'] as List? ?? const []))
        PollOption.fromJson(Map<String, dynamic>.from(o as Map)),
    ],
  );

  final String question;
  final List<PollOption> options;
  final int total;

  /// The option I voted for, if any.
  final String? myOption;
  final DateTime? closesAt;

  bool get closed => closesAt != null && closesAt!.isBefore(DateTime.now());

  /// Local, optimistic change of my vote (null = take it back).
  Poll withMyVote(String? optionId) {
    var total = this.total;
    final options = [
      for (final o in this.options)
        PollOption(
          id: o.id,
          label: o.label,
          votes:
              o.votes - (o.id == myOption ? 1 : 0) + (o.id == optionId ? 1 : 0),
        ),
    ];
    if (myOption == null && optionId != null) total++;
    if (myOption != null && optionId == null) total--;
    return Poll(
      question: question,
      options: options,
      total: total,
      myOption: optionId,
      closesAt: closesAt,
    );
  }
}
