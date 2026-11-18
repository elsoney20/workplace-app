import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/domain/my_profile.dart';
import '../data/feed_repository.dart';
import '../domain/feed_post.dart';
import '../domain/feed_scope.dart';
import '../domain/post_attachment.dart';
import 'emoji_grid.dart';
import 'mention_text_field.dart';

/// New post (or edit the text of an existing one).
/// Returns true when something was saved.
Future<bool> showPostComposer(
  BuildContext context, {
  required MyProfile me,
  required FeedScope scope,
  FeedPost? editing,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PostComposerDialog(me: me, scope: scope, editing: editing),
  );
  return saved ?? false;
}

class PostComposerDialog extends ConsumerStatefulWidget {
  const PostComposerDialog({
    super.key,
    required this.me,
    required this.scope,
    this.editing,
  });

  final MyProfile me;
  final FeedScope scope;
  final FeedPost? editing;

  @override
  ConsumerState<PostComposerDialog> createState() => _PostComposerDialogState();
}

class _PostComposerDialogState extends ConsumerState<PostComposerDialog> {
  late final MentionController _text = MentionController(
    widget.editing?.body ?? '',
  );
  final List<PendingUpload> _uploads = [];
  bool _announcement = false;

  /// Quick poll: null = no poll.
  TextEditingController? _pollQuestion;
  final List<TextEditingController> _pollOptions = [];
  bool _saving = false;
  (int, int)? _progress;
  String? _error;

  bool get _isEdit => widget.editing != null;

  /// Announcements: feed moderators only (same rule as the database).
  bool get _canAnnounce => widget.scope.canModerate && !_isEdit;

  @override
  void dispose() {
    _text.dispose();
    _pollQuestion?.dispose();
    for (final c in _pollOptions) {
      c.dispose();
    }
    super.dispose();
  }

  void _togglePoll() {
    setState(() {
      if (_pollQuestion == null) {
        _pollQuestion = TextEditingController();
        _pollOptions.addAll([TextEditingController(), TextEditingController()]);
      } else {
        _pollQuestion!.dispose();
        _pollQuestion = null;
        for (final c in _pollOptions) {
          c.dispose();
        }
        _pollOptions.clear();
      }
    });
  }

  Future<void> _pick({required bool media}) async {
    final l10n = AppLocalizations.of(context);
    final files = await FilePicker.pickFiles(
      type: media ? FileType.media : FileType.any,
    );
    final added = <PendingUpload>[];
    String? error;
    for (final f in files) {
      final size = await f.length();
      if (size != null && size > maxUploadBytes) {
        error = l10n.fileTooBig(f.name);
        continue;
      }
      final upload = PendingUpload(name: f.name, bytes: await f.readAsBytes());
      if (upload.tooBig) {
        error = l10n.fileTooBig(f.name);
        continue;
      }
      added.add(upload);
    }
    if (!mounted) return;
    setState(() {
      _uploads.addAll(added);
      _error = error;
    });
  }

  Future<void> _addEmoji() async {
    final emoji = await showEmojiGrid(context);
    if (emoji != null) _text.insertAtCursor(emoji);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final question = _pollQuestion?.text.trim();
    final options = [
      for (final c in _pollOptions)
        if (c.text.trim().isNotEmpty) c.text.trim(),
    ];
    if (question != null && (question.isEmpty || options.length < 2)) {
      setState(() => _error = l10n.pollNeedsChoices);
      return;
    }
    if (_text.isEmpty && _uploads.isEmpty && question == null) {
      setState(() => _error = l10n.emptyPost);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(feedRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updatePostBody(widget.editing!.id, _text.storedText);
      } else {
        await repo.createPost(
          authorId: widget.me.id,
          body: _text.storedText,
          uploads: _uploads,
          announcement: _announcement,
          groupId: widget.scope.groupId,
          poll: question == null
              ? null
              : (question: question, options: options),
          onProgress: (done, total) {
            if (mounted && total > 0) setState(() => _progress = (done, total));
          },
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on FileTooBigException {
      setState(() {
        _saving = false;
        _error = l10n.fileTooBig('');
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _progress = null;
        _error = e.toString().toLowerCase().contains('socket')
            ? l10n.errorNetwork
            : l10n.errorUnknown;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_isEdit ? l10n.editPost : l10n.newPost),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MentionTextField(
                fieldKey: const Key('postTextField'),
                controller: _text,
                hintText: l10n.postHint,
                minLines: 4,
                maxLines: 12,
                autofocus: true,
                onSubmit: _saving ? null : _save,
              ),
              if (_uploads.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (i, u) in _uploads.indexed)
                      _UploadChip(
                        upload: u,
                        onRemove: _saving
                            ? null
                            : () => setState(() => _uploads.removeAt(i)),
                      ),
                  ],
                ),
              ],
              if (!_isEdit) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton.icon(
                      key: const Key('addMediaButton'),
                      onPressed: _saving ? null : () => _pick(media: true),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(l10n.addPhotoVideo),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : () => _pick(media: false),
                      icon: const Icon(Icons.attach_file),
                      label: Text(l10n.addFile),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _addEmoji,
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      label: Text(l10n.addEmoji),
                    ),
                    TextButton.icon(
                      key: const Key('addPollButton'),
                      onPressed: _saving ? null : _togglePoll,
                      icon: Icon(
                        _pollQuestion == null
                            ? Icons.poll_outlined
                            : Icons.close_rounded,
                      ),
                      label: Text(
                        _pollQuestion == null ? l10n.addPoll : l10n.removePoll,
                      ),
                    ),
                  ],
                ),
                if (_pollQuestion case final q?) ...[
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('pollQuestion'),
                    controller: q,
                    maxLength: 300,
                    decoration: InputDecoration(
                      labelText: l10n.pollQuestion,
                      prefixIcon: const Icon(Icons.poll_outlined),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                  ),
                  for (final (i, c) in _pollOptions.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        key: Key('pollOption-$i'),
                        controller: c,
                        maxLength: 120,
                        decoration: InputDecoration(
                          labelText: l10n.pollChoice(i + 1),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          counterText: '',
                          suffixIcon: _pollOptions.length > 2
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => setState(
                                    () => _pollOptions.removeAt(i).dispose(),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  if (_pollOptions.length < 6)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('addPollChoice'),
                        onPressed: () => setState(
                          () => _pollOptions.add(TextEditingController()),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l10n.pollAddChoice),
                      ),
                    ),
                ],
              ] else
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _addEmoji,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    label: Text(l10n.addEmoji),
                  ),
                ),
              if (_canAnnounce)
                SwitchListTile(
                  key: const Key('announcementSwitch'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.campaign_outlined),
                  title: Text(l10n.announcementSwitch),
                  value: _announcement,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _announcement = v),
                ),
              if (_progress != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _progress!.$2 == 0
                      ? null
                      : _progress!.$1 / _progress!.$2,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.uploadingProgress(_progress!.$1, _progress!.$2),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
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
          key: const Key('submitPostButton'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? l10n.save : l10n.postAction),
        ),
      ],
    );
  }
}

class _UploadChip extends StatelessWidget {
  const _UploadChip({required this.upload, this.onRemove});

  final PendingUpload upload;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final thumb = upload.kind == AttachmentKind.image
        ? ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(
              upload.bytes,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              cacheWidth: 128,
            ),
          )
        : Icon(
            upload.kind == AttachmentKind.video
                ? Icons.movie_outlined
                : Icons.insert_drive_file_outlined,
            size: 40,
          );
    return Container(
      width: 150,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(width: 64, height: 64, child: Center(child: thumb)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  upload.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  formatBytes(upload.bytes.length),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            InkWell(onTap: onRemove, child: const Icon(Icons.close, size: 18)),
        ],
      ),
    );
  }
}
