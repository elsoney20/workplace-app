import 'package:material_ui/material_ui.dart';

import '../domain/person.dart';

/// Round avatar with the person's initials (photos come with the profile
/// screen in a later phase).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.person, {super.key, this.radius = 20});

  final Person person;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A stable color per person, so people are easy to recognise.
    final palette = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      scheme.surfaceContainerHighest,
    ];
    final color = palette[person.id.hashCode.abs() % palette.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        person.initials,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
