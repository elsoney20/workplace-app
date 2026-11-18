import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../admin/presentation/admin_errors.dart';
import '../../auth/application/auth_providers.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/presentation/chat_drawer.dart';
import '../../feed/domain/person.dart';
import '../../feed/presentation/person_avatar.dart';
import '../data/directory_repository.dart';

final _departmentsProvider =
    FutureProvider.autoDispose<List<(String, String, String)>>(
      (ref) => ref.watch(directoryRepositoryProvider).departments(),
    );

final directoryProvider = FutureProvider.autoDispose
    .family<List<DirectoryEntry>, (String, String?)>(
      (ref, args) => ref
          .watch(directoryRepositoryProvider)
          .list(query: args.$1, departmentId: args.$2),
    );

/// Searchable list of all active employees.
class DirectoryScreen extends ConsumerStatefulWidget {
  const DirectoryScreen({super.key});

  static const String routePath = '/directory';
  static const String routeName = 'directory';

  @override
  ConsumerState<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends ConsumerState<DirectoryScreen> {
  String _query = '';
  String? _department;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final departments = ref.watch(_departmentsProvider).value ?? const [];
    final people = ref.watch(directoryProvider((_query, _department)));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.directoryTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('directorySearch'),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: l10n.searchEmployees,
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String?>(
                      value: _department,
                      hint: Text(l10n.allDepartments),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l10n.allDepartments),
                        ),
                        for (final (id, ar, en) in departments)
                          DropdownMenuItem(
                            value: id,
                            child: Text(lang == 'ar' ? ar : en),
                          ),
                      ],
                      onChanged: (v) => setState(() => _department = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: switch (people) {
                  AsyncData(:final value) when value.isEmpty => Center(
                    child: Text(l10n.employeesEmpty),
                  ),
                  AsyncData(:final value) => ListView(
                    children: [
                      for (final e in value)
                        ListTile(
                          key: Key('directory-${e.person.id}'),
                          leading: PersonAvatar(e.person),
                          title: Text(e.person.fullName),
                          subtitle: Text(
                            [
                              ?e.person.jobTitle,
                              ?e.department(lang),
                            ].join(' · '),
                          ),
                          onTap: () => showPersonCard(context, e),
                        ),
                    ],
                  ),
                  AsyncError() => Center(child: Text(l10n.errorNetwork)),
                  _ => const Center(child: CircularProgressIndicator()),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Profile card with "Send message" and the phone (if allowed).
Future<void> showPersonCard(BuildContext context, DirectoryEntry e) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final lang = Localizations.localeOf(context).languageCode;
        final me = ref.watch(myProfileProvider).value;
        final theme = Theme.of(context);
        return AlertDialog(
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PersonAvatar(e.person, radius: 44),
                const SizedBox(height: 12),
                Text(
                  e.person.fullName,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                Text(
                  [
                    roleLabel(l10n, e.role),
                    ?e.person.jobTitle,
                    ?e.department(lang),
                  ].join(' · '),
                  textAlign: TextAlign.center,
                ),
                if (e.bio != null && e.bio!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(e.bio!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(
                    e.phone ?? l10n.phoneHidden,
                    textDirection: e.phone == null ? null : TextDirection.ltr,
                  ),
                  trailing: e.phone == null
                      ? null
                      : IconButton(
                          tooltip: l10n.callOrCopy,
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: e.phone!),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.copied)),
                              );
                            }
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.ok),
            ),
            if (me != null && me.id != e.person.id)
              FilledButton.icon(
                key: const Key('messagePersonButton'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: Text(l10n.sendMessage),
                onPressed: () async {
                  final drawer = ref.read(chatDrawerProvider.notifier);
                  final id = await ref
                      .read(chatRepositoryProvider)
                      .openDirect(e.person.id);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  drawer.openChat(id);
                },
              ),
          ],
        );
      },
    ),
  );
}

/// Edit my bio, photo and who sees my phone number.
class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  static const String routePath = '/me';
  static const String routeName = 'me';

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  final _bio = TextEditingController();
  String _visibility = 'everyone';
  String? _avatarPath;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(directoryRepositoryProvider).mySettings();
      if (!mounted) return;
      setState(() {
        _bio.text = s.bio ?? '';
        _visibility = s.phoneVisibility;
        _avatarPath = s.avatarPath;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      ref.invalidate(myProfileProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.savedMessage)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorUnknown)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = ref.watch(myProfileProvider).value;
    final repo = ref.read(directoryRepositoryProvider);
    if (me == null || !_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final person = Person(
      id: me.id,
      fullName: me.fullName,
      jobTitle: me.jobTitle,
      avatarPath: _avatarPath,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myProfile)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: PersonAvatar(person, radius: 52)),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('changePhotoButton'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final file = await FilePicker.pickFile(
                              type: FileType.image,
                            );
                            if (file == null) return;
                            final bytes = await file.readAsBytes();
                            final type =
                                lookupMimeType(file.name, headerBytes: bytes) ??
                                'image/jpeg';
                            await _run(
                              () => repo.setAvatar(me.id, bytes, type),
                            );
                          },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(l10n.changePhoto),
                  ),
                  if (_avatarPath != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => repo.removeAvatar(me.id)),
                      child: Text(l10n.removePhoto),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                me.fullName,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              Text(
                me.phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('bioField'),
                controller: _bio,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: l10n.bioLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.phoneVisibilityLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              RadioGroup<String>(
                groupValue: _visibility,
                onChanged: (v) =>
                    setState(() => _visibility = v ?? _visibility),
                child: Column(
                  children: [
                    RadioListTile(
                      value: 'everyone',
                      title: Text(l10n.visibilityEveryone),
                    ),
                    RadioListTile(
                      value: 'managers',
                      title: Text(l10n.visibilityManagers),
                    ),
                    RadioListTile(
                      value: 'nobody',
                      title: Text(l10n.visibilityNobody),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('saveProfileButton'),
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => repo.saveSettings(
                          me.id,
                          bio: _bio.text.trim().isEmpty
                              ? null
                              : _bio.text.trim(),
                          phoneVisibility: _visibility,
                        ),
                      ),
                child: Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
