import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../../feed/data/feed_repository.dart';
import '../../feed/domain/person.dart';
import '../../feed/presentation/person_avatar.dart';
import '../data/engagement_repository.dart';
import '../domain/home_sidebar.dart';
import 'home_side_columns.dart';

// ----------------------------------------------------------------- kudos

/// "Thank a colleague": pick someone, a badge and a short note.
/// Returns true when it was sent.
Future<bool> showSendKudosDialog(BuildContext context, {Person? to}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _KudosDialog(to: to),
    ) ??
    false;

class _KudosDialog extends ConsumerStatefulWidget {
  const _KudosDialog({this.to});

  final Person? to;

  @override
  ConsumerState<_KudosDialog> createState() => _KudosDialogState();
}

class _KudosDialogState extends ConsumerState<_KudosDialog> {
  final _search = TextEditingController();
  final _message = TextEditingController();
  late Person? _to = widget.to;
  KudosBadge _badge = KudosBadge.thanks;
  List<Person> _results = const [];
  Timer? _debounce;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _message.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (q.trim().isEmpty) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      try {
        final me = ref.read(myProfileProvider).value?.id;
        final found = await ref.read(feedRepositoryProvider).searchPeople(q);
        if (mounted) {
          setState(() => _results = found.where((p) => p.id != me).toList());
        }
      } catch (_) {}
    });
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    final me = ref.read(myProfileProvider).value;
    final to = _to;
    if (me == null || to == null) {
      setState(() => _error = l10n.kudosPickSomeone);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(engagementRepositoryProvider)
          .sendKudos(
            fromId: me.id,
            toId: to.id,
            badge: _badge,
            message: _message.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _sending = false;
        _error = e.toString().contains('Too many')
            ? l10n.kudosTooMany
            : l10n.errorUnknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      title: Text('🙏 ${l10n.sendKudos}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_to case final to?)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PersonAvatar(to, radius: 20),
                  title: Text(to.fullName),
                  subtitle: to.jobTitle == null ? null : Text(to.jobTitle!),
                  trailing: widget.to == null
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() => _to = null),
                        )
                      : null,
                )
              else ...[
                TextField(
                  key: const Key('kudosSearch'),
                  controller: _search,
                  autofocus: true,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    hintText: l10n.kudosWho,
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                for (final p in _results)
                  ListTile(
                    key: Key('kudosPick-${p.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: PersonAvatar(p, radius: 16),
                    title: Text(p.fullName),
                    subtitle: p.jobTitle == null ? null : Text(p.jobTitle!),
                    onTap: () => setState(() {
                      _to = p;
                      _results = const [];
                    }),
                  ),
              ],
              const SizedBox(height: 14),
              Text(l10n.kudosForWhat, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in KudosBadge.values)
                    ChoiceChip(
                      key: Key('badge-${b.name}'),
                      selected: _badge == b,
                      onSelected: (_) => setState(() => _badge = b),
                      avatar: Text(b.emoji),
                      label: Text(badgeLabel(l10n, b)),
                      selectedColor: scheme.primary.withValues(alpha: .25),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('kudosMessage'),
                controller: _message,
                minLines: 2,
                maxLines: 4,
                maxLength: 280,
                decoration: InputDecoration(
                  hintText: l10n.kudosMessageHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('kudosSend'),
          onPressed: _sending || _to == null ? null : _send,
          child: _sending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.send),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- birthday

/// Asks for my birthday. Returns true when it was saved.
Future<bool> showBirthdayDialog(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final repo = ref.read(engagementRepositoryProvider);
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    helpText: l10n.addMyBirthday,
    initialEntryMode: DatePickerEntryMode.calendar,
    initialDatePickerMode: DatePickerMode.year,
    initialDate: DateTime(now.year - 28, now.month, now.day),
    firstDate: DateTime(1940),
    lastDate: now,
  );
  if (picked == null) return false;
  try {
    await repo.setMyBirthday(picked);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.birthdaySaved)));
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.errorUnknown)));
    }
    return false;
  }
}

// ----------------------------------------------------------------- events

const _eventKinds = [
  'event',
  'tournament',
  'celebration',
  'training',
  'meeting',
];

String eventKindLabel(AppLocalizations l10n, String kind) => switch (kind) {
  'tournament' => l10n.eventKindTournament,
  'celebration' => l10n.eventKindCelebration,
  'training' => l10n.eventKindTraining,
  'meeting' => l10n.eventKindMeeting,
  _ => l10n.eventKindEvent,
};

/// New company event (managers and admins). Returns true when saved.
Future<bool> showNewEventDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => const _NewEventDialog(),
    ) ??
    false;

class _NewEventDialog extends ConsumerStatefulWidget {
  const _NewEventDialog();

  @override
  ConsumerState<_NewEventDialog> createState() => _NewEventDialogState();
}

class _NewEventDialogState extends ConsumerState<_NewEventDialog> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();
  String _kind = 'event';
  late DateTime _starts = () {
    final t = DateTime.now().add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 18);
  }();
  int _hours = 2;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _starts,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_starts),
    );
    if (time == null) return;
    setState(
      () => _starts = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_title.text.trim().isEmpty) {
      setState(() => _error = l10n.eventNeedsTitle);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref
          .read(engagementRepositoryProvider)
          .createEvent(
            title: _title.text.trim(),
            kind: _kind,
            startsAt: _starts,
            endsAt: _starts.add(Duration(hours: _hours)),
            location: opt(_location),
            description: opt(_description),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      setState(() {
        _saving = false;
        _error = l10n.errorUnknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return AlertDialog(
      title: Text('📅 ${l10n.newEvent}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('eventTitle'),
                controller: _title,
                autofocus: true,
                maxLength: 160,
                decoration: InputDecoration(
                  labelText: l10n.eventTitle,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in _eventKinds)
                    ChoiceChip(
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                      label: Text(eventKindLabel(l10n, k)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('eventWhen'),
                onPressed: _pickWhen,
                icon: const Icon(Icons.schedule_rounded),
                label: Text(
                  '${DateFormat.yMMMEd(locale).format(_starts)} · '
                  '${DateFormat.jm(locale).format(_starts)}',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(l10n.eventDuration),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _hours,
                    items: [
                      for (final h in [1, 2, 3, 4, 6, 8])
                        DropdownMenuItem(
                          value: h,
                          child: Text(l10n.hoursCount(h)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _hours = v ?? 2),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _location,
                maxLength: 160,
                decoration: InputDecoration(
                  labelText: l10n.eventLocation,
                  prefixIcon: const Icon(Icons.place_outlined),
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: l10n.eventDescription,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('eventSave'),
          onPressed: _saving ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Details of one event (and delete, for its creator or an admin).
Future<void> showEventDetails(
  BuildContext context,
  CompanyEvent e, {
  required bool canDelete,
  required VoidCallback onDeleted,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => Consumer(
    builder: (context, ref, _) {
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final locale = Localizations.localeOf(context).toLanguageTag();
      final end = e.endsAt;
      return AlertDialog(
        title: Text('${e.emoji} ${e.title}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eventKindLabel(l10n, e.kind),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${DateFormat.yMMMMEEEEd(locale).format(e.startsAt)}\n'
                      '${DateFormat.jm(locale).format(e.startsAt)}'
                      '${end == null ? '' : ' – ${DateFormat.jm(locale).format(end)}'}',
                    ),
                  ),
                ],
              ),
              if (e.location != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.location!)),
                  ],
                ),
              ],
              if (e.description != null) ...[
                const SizedBox(height: 12),
                Text(e.description!),
              ],
              if (e.going.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    AvatarStack(people: e.going, size: 26),
                    const SizedBox(width: 8),
                    Text(l10n.eventGoingCount(e.goingCount)),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (canDelete)
            TextButton(
              onPressed: () async {
                await ref.read(engagementRepositoryProvider).deleteEvent(e.id);
                onDeleted();
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(
                l10n.delete,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.close),
          ),
        ],
      );
    },
  ),
);
