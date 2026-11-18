import '../../feed/domain/person.dart';

/// Kinds of thanks a colleague can give (same list as the database).
enum KudosBadge {
  thanks('🙏'),
  teamwork('🤝'),
  helpful('💡'),
  mvp('🏆'),
  creative('🎨'),
  speed('⚡');

  const KudosBadge(this.emoji);
  final String emoji;

  static KudosBadge parse(String? name) => KudosBadge.values.firstWhere(
    (b) => b.name == name,
    orElse: () => KudosBadge.thanks,
  );
}

class Kudos {
  const Kudos({
    required this.id,
    required this.from,
    required this.to,
    required this.badge,
    required this.createdAt,
    this.message,
  });

  factory Kudos.fromJson(Map<String, dynamic> j) => Kudos(
    id: j['id'] as String,
    from: Person.fromJson(_map(j['from'])),
    to: Person.fromJson(_map(j['to'])),
    badge: KudosBadge.parse(j['badge'] as String?),
    message: j['message'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );

  final String id;
  final Person from;
  final Person to;
  final KudosBadge badge;
  final String? message;
  final DateTime createdAt;
}

/// A birthday or work anniversary coming up.
class Celebration {
  const Celebration({
    required this.person,
    required this.day,
    required this.daysUntil,
    this.years,
  });

  factory Celebration.fromJson(Map<String, dynamic> j) => Celebration(
    person: Person.fromJson(_map(j['person'])),
    day: DateTime.parse(j['day'] as String),
    daysUntil: (j['days_until'] as num?)?.toInt() ?? 0,
    years: (j['years'] as num?)?.toInt(),
  );

  final Person person;
  final DateTime day;
  final int daysUntil;

  /// Work anniversaries only.
  final int? years;
}

class CompanyEvent {
  const CompanyEvent({
    required this.id,
    required this.title,
    required this.kind,
    required this.startsAt,
    this.endsAt,
    this.description,
    this.location,
    this.createdBy,
    this.goingCount = 0,
    this.iAmGoing = false,
    this.going = const [],
  });

  factory CompanyEvent.fromJson(Map<String, dynamic> j) => CompanyEvent(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    kind: j['kind'] as String? ?? 'event',
    description: j['description'] as String?,
    location: j['location'] as String?,
    createdBy: j['created_by'] as String?,
    startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
    endsAt: j['ends_at'] == null
        ? null
        : DateTime.parse(j['ends_at'] as String).toLocal(),
    goingCount: (j['going_count'] as num?)?.toInt() ?? 0,
    iAmGoing: j['i_am_going'] as bool? ?? false,
    going: [
      for (final p in (j['going'] as List? ?? const []))
        Person.fromJson(_map(p)),
    ],
  );

  final String id;
  final String title;

  /// event, tournament, meeting, celebration, training.
  final String kind;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? description;
  final String? location;
  final String? createdBy;
  final int goingCount;
  final bool iAmGoing;
  final List<Person> going;

  String get emoji => switch (kind) {
    'tournament' => '🏆',
    'meeting' => '👥',
    'celebration' => '🎉',
    'training' => '🎓',
    _ => '📅',
  };
}

/// Everything the home side columns show (public.get_home_sidebar()).
class HomeSidebar {
  const HomeSidebar({
    this.myBirthdaySet = true,
    this.birthdays = const [],
    this.anniversaries = const [],
    this.newJoiners = const [],
    this.events = const [],
    this.heroes = const [],
    this.kudos = const [],
  });

  factory HomeSidebar.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) => [
      for (final e in (j[key] as List? ?? const [])) f(_map(e)!),
    ];
    return HomeSidebar(
      myBirthdaySet: j['my_birthday_set'] as bool? ?? true,
      birthdays: list('birthdays', Celebration.fromJson),
      anniversaries: list('anniversaries', Celebration.fromJson),
      newJoiners: list(
        'new_joiners',
        (m) => Person.fromJson(_map(m['person'])),
      ),
      events: list('events', CompanyEvent.fromJson),
      heroes: list(
        'heroes',
        (m) => (
          Person.fromJson(_map(m['person'])),
          (m['count'] as num?)?.toInt() ?? 0,
        ),
      ),
      kudos: list('kudos', Kudos.fromJson),
    );
  }

  final bool myBirthdaySet;
  final List<Celebration> birthdays;
  final List<Celebration> anniversaries;
  final List<Person> newJoiners;
  final List<CompanyEvent> events;
  final List<(Person, int)> heroes;
  final List<Kudos> kudos;

  HomeSidebar withEvent(CompanyEvent e) => HomeSidebar(
    myBirthdaySet: myBirthdaySet,
    birthdays: birthdays,
    anniversaries: anniversaries,
    newJoiners: newJoiners,
    events: [for (final x in events) x.id == e.id ? e : x],
    heroes: heroes,
    kudos: kudos,
  );
}

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;
