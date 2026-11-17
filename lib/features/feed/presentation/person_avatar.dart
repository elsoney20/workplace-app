import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/storage/signed_urls.dart';
import '../domain/person.dart';

/// Round avatar: the person's photo if they set one, otherwise initials.
class PersonAvatar extends ConsumerWidget {
  const PersonAvatar(this.person, {super.key, this.radius = 20});

  final Person person;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // A stable color per person, so people are easy to recognise.
    final palette = [
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
      scheme.surfaceContainerHighest,
    ];
    final color = palette[person.id.hashCode.abs() % palette.length];
    final path = person.avatarPath;
    final url = path == null
        ? null
        : ref.watch(signedUrlProvider((bucket: 'avatars', path: path))).value;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundImage: url == null ? null : NetworkImage(url),
      onForegroundImageError: url == null ? null : (_, _) {},
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
