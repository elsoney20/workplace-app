import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/my_profile.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/presentation/chat_drawer.dart';
import '../../feed/domain/person.dart';
import '../../feed/presentation/feed_format.dart';
import '../../feed/presentation/person_avatar.dart';
import '../application/engagement_providers.dart';
import '../data/engagement_repository.dart';
import '../domain/home_sidebar.dart';
import 'engagement_dialogs.dart';
import 'side_card.dart';

/// Which cards a side column shows.
enum SideSection { events, celebrations, newJoiners, kudos, heroes, online }

/// One scrolling column of cards next to the home feed.
class HomeSideColumn extends ConsumerWidget {
  const HomeSideColumn({super.key, required this.sections});

  static const double width = 320;

  final List<SideSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeSidebarProvider);
    final me = ref.watch(myProfileProvider).value;
    // Nothing to show (yet, or the server is not updated): stay empty.
    final sidebar = data.value;
    if (sidebar == null || me == null) return const SizedBox(width: width);

    return SizedBox(
      width: width,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
          children: [
            for (final (i, s) in sections.indexed)
              FadeSlideIn(
                index: i,
                child: switch (s) {
                  SideSection.events => _EventsCard(sidebar: sidebar, me: me),
                  SideSection.celebrations => _CelebrationsCard(
                    sidebar: sidebar,
                    me: me,
                  ),
                  SideSection.newJoiners => _NewJoinersCard(
                    people: sidebar.newJoiners,
                    me: me,
                  ),
                  SideSection.kudos => _KudosCard(sidebar: sidebar),
                  SideSection.heroes => _HeroesCard(heroes: sidebar.heroes),
                  SideSection.online => _OnlineCard(me: me),
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens (or starts) a private chat with [person] in the side panel.
Future<void> openChatWith(WidgetRef ref, Person person) async {
  final drawer = ref.read(chatDrawerProvider.notifier);
  final id = await ref.read(chatRepositoryProvider).openDirect(person.id);
  drawer.openChat(id);
}

// ---------------------------------------------------------------- events

class _EventsCard extends ConsumerWidget {
  const _EventsCard({required this.sidebar, required this.me});

  final HomeSidebar sidebar;
  final MyProfile me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final canCreate = me.isAdmin || me.role == 'manager';
    return SideCard(
      key: const Key('eventsCard'),
      emoji: '📅',
      title: l10n.sideEvents,
      action: canCreate
          ? IconButton(
              key: const Key('newEventButton'),
              tooltip: l10n.newEvent,
              icon: const Icon(Icons.add_rounded),
              onPressed: () async {
                if (await showNewEventDialog(context)) {
                  ref.invalidate(homeSidebarProvider);
                }
              },
            )
          : null,
      child: sidebar.events.isEmpty
          ? SideHint(l10n.sideNoEvents)
          : Column(
              children: [
                for (final e in sidebar.events)
                  _EventTile(event: e, me: me, sidebar: sidebar),
              ],
            ),
    );
  }
}

class _EventTile extends ConsumerStatefulWidget {
  const _EventTile({
    required this.event,
    required this.me,
    required this.sidebar,
  });

  final CompanyEvent event;
  final MyProfile me;
  final HomeSidebar sidebar;

  @override
  ConsumerState<_EventTile> createState() => _EventTileState();
}

class _EventTileState extends ConsumerState<_EventTile> {
  bool? _going;
  bool _busy = false;

  Future<void> _toggle() async {
    final e = widget.event;
    final next = !(_going ?? e.iAmGoing);
    setState(() {
      _going = next;
      _busy = true;
    });
    try {
      await ref
          .read(engagementRepositoryProvider)
          .setGoing(e.id, widget.me.id, going: next);
      ref.invalidate(homeSidebarProvider);
    } catch (_) {
      if (mounted) setState(() => _going = !next);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didUpdateWidget(_EventTile old) {
    super.didUpdateWidget(old);
    if (!_busy) _going = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = widget.event;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final going = _going ?? e.iAmGoing;
    final count = e.goingCount + (going == e.iAmGoing ? 0 : (going ? 1 : -1));
    final mine = e.createdBy == widget.me.id || widget.me.isAdmin;

    return InkWell(
      key: Key('event-${e.id}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => showEventDetails(
        context,
        e,
        canDelete: mine,
        onDeleted: () => ref.invalidate(homeSidebarProvider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Calendar leaf: month + day.
            Container(
              width: 50,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: scheme.primary.withValues(alpha: .14),
                border: Border.all(color: scheme.primary.withValues(alpha: .4)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat.MMM(locale).format(e.startsAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${e.startsAt.day}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '${DateFormat.E(locale).format(e.startsAt)} '
                          '${DateFormat.jm(locale).format(e.startsAt)}',
                      ?e.location,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      AvatarStack(people: e.going, size: 22),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.eventGoingCount(count),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ] else
                        const Spacer(),
                      SizedBox(
                        height: 30,
                        child: going
                            ? FilledButton.icon(
                                key: Key('going-${e.id}'),
                                onPressed: _busy ? null : _toggle,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: Text(l10n.eventGoing),
                              )
                            : OutlinedButton(
                                key: Key('going-${e.id}'),
                                onPressed: _busy ? null : _toggle,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                                child: Text(l10n.eventJoin),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Overlapping round avatars.
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.people, this.size = 24});

  final List<Person> people;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(4).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final step = size * .66;
    final ring = Theme.of(context).colorScheme.surfaceContainerLow;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (final (i, p) in shown.indexed)
            PositionedDirectional(
              start: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 1.5),
                ),
                child: PersonAvatar(p, radius: size / 2 - 1.5),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- celebrations

class _CelebrationsCard extends ConsumerWidget {
  const _CelebrationsCard({required this.sidebar, required this.me});

  final HomeSidebar sidebar;
  final MyProfile me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = [
      for (final b in sidebar.birthdays) (b, true),
      for (final a in sidebar.anniversaries) (a, false),
    ]..sort((x, y) => x.$1.daysUntil.compareTo(y.$1.daysUntil));

    String when(Celebration c, bool birthday) {
      if (!birthday) return l10n.anniversaryYears(c.years ?? 1);
      return switch (c.daysUntil) {
        0 => l10n.birthdayToday,
        1 => l10n.birthdayTomorrow,
        final n => l10n.birthdayIn(n),
      };
    }

    return SideCard(
      key: const Key('celebrationsCard'),
      emoji: '🎂',
      title: l10n.sideCelebrations,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (items.isEmpty) SideHint(l10n.sideNoCelebrations),
          for (final (c, birthday) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  PersonAvatar(c.person, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.person.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          '${birthday ? '🎂' : '🎉'} ${when(c, birthday)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: c.daysUntil == 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: c.daysUntil == 0
                                ? FontWeight.w700
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (c.person.id != me.id)
                    IconButton(
                      tooltip: l10n.sayCongrats,
                      icon: const Icon(Icons.waving_hand_outlined, size: 20),
                      onPressed: () => openChatWith(ref, c.person),
                    ),
                ],
              ),
            ),
          if (!sidebar.myBirthdaySet) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('addMyBirthday'),
              onPressed: () async {
                if (await showBirthdayDialog(context, ref)) {
                  ref.invalidate(homeSidebarProvider);
                }
              },
              icon: const Icon(Icons.cake_outlined, size: 18),
              label: Text(l10n.addMyBirthday),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewJoinersCard extends ConsumerWidget {
  const _NewJoinersCard({required this.people, required this.me});

  final List<Person> people;
  final MyProfile me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (people.isEmpty) return const SizedBox.shrink();
    return SideCard(
      key: const Key('newJoinersCard'),
      emoji: '👋',
      title: l10n.sideNewJoiners,
      child: Column(
        children: [
          for (final p in people)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  PersonAvatar(p, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (p.jobTitle != null)
                          Text(
                            p.jobTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (p.id != me.id)
                    TextButton(
                      onPressed: () => openChatWith(ref, p),
                      child: Text(l10n.sayWelcome),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ kudos

class _KudosCard extends ConsumerWidget {
  const _KudosCard({required this.sidebar});

  final HomeSidebar sidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SideCard(
      key: const Key('kudosCard'),
      emoji: '🙌',
      title: l10n.sideKudos,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: const Key('sendKudosButton'),
            onPressed: () async {
              if (await showSendKudosDialog(context)) {
                ref.invalidate(homeSidebarProvider);
              }
            },
            icon: const Text('🙏', style: TextStyle(fontSize: 16)),
            label: Text(l10n.sendKudos),
          ),
          const SizedBox(height: 8),
          if (sidebar.kudos.isEmpty) SideHint(l10n.sideNoKudos),
          for (final k in sidebar.kudos.take(5))
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: scheme.surfaceContainerHigh.withValues(alpha: .7),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PersonAvatar(k.from, radius: 12),
                      const SizedBox(width: 4),
                      Icon(
                        Directionality.of(context) == TextDirection.rtl
                            ? Icons.arrow_back_rounded
                            : Icons.arrow_forward_rounded,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      PersonAvatar(k.to, radius: 12),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          k.to.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _BadgeChip(badge: k.badge),
                    ],
                  ),
                  if (k.message != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      k.message!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.kudosFrom(k.from.fullName)} · '
                    '${timeAgo(context, k.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String badgeLabel(AppLocalizations l10n, KudosBadge b) => switch (b) {
  KudosBadge.thanks => l10n.badgeThanks,
  KudosBadge.teamwork => l10n.badgeTeamwork,
  KudosBadge.helpful => l10n.badgeHelpful,
  KudosBadge.mvp => l10n.badgeMvp,
  KudosBadge.creative => l10n.badgeCreative,
  KudosBadge.speed => l10n.badgeSpeed,
};

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge});

  final KudosBadge badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.primary.withValues(alpha: .16),
      ),
      child: Text(
        '${badge.emoji} ${badgeLabel(AppLocalizations.of(context), badge)}',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HeroesCard extends StatelessWidget {
  const _HeroesCard({required this.heroes});

  final List<(Person, int)> heroes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    const medals = ['🥇', '🥈', '🥉'];
    return SideCard(
      key: const Key('heroesCard'),
      emoji: '🏆',
      title: l10n.sideHeroes,
      child: heroes.isEmpty
          ? SideHint(l10n.sideNoHeroes)
          : Column(
              children: [
                for (final (i, (p, n)) in heroes.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            i < 3 ? medals[i] : '${i + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: i < 3 ? 18 : 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                        PersonAvatar(p, radius: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          l10n.heroKudosCount(n),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _OnlineCard extends ConsumerWidget {
  const _OnlineCard({required this.me});

  final MyProfile me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final people = (ref.watch(onlineCardsProvider).value ?? const <Person>[])
        .where((p) => p.id != me.id)
        .toList();
    return SideCard(
      key: const Key('onlineCard'),
      emoji: '🟢',
      title: l10n.sideOnline(people.length),
      child: people.isEmpty
          ? SideHint(l10n.sideNoOnline)
          : Wrap(
              spacing: 6,
              runSpacing: 10,
              children: [
                for (final p in people.take(24))
                  Tooltip(
                    message: p.fullName,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => openChatWith(ref, p),
                      child: Stack(
                        children: [
                          PersonAvatar(p, radius: 20),
                          PositionedDirectional(
                            end: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3DDC84),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.surfaceContainerLow,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
