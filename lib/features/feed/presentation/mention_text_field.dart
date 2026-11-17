import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/feed_repository.dart';
import '../domain/person.dart';
import '../domain/rich_text.dart';
import 'person_avatar.dart';

/// Holds the text box state plus the people picked with "@".
class MentionController {
  MentionController([String stored = '']) {
    final (display, picked) = toDisplayText(stored);
    text = TextEditingController(text: display);
    _picked.addAll(picked);
  }

  late final TextEditingController text;
  final List<PickedMention> _picked = [];

  /// The text in the stored format, with mention markup.
  String get storedText => toStoredText(
    text.text,
    _picked.where((p) => text.text.contains(p.display)),
  );

  bool get isEmpty => text.text.trim().isEmpty;

  void clear() {
    text.clear();
    _picked.clear();
  }

  /// Replaces the content with stored text (e.g. to edit a comment).
  void load(String stored) {
    final (display, picked) = toDisplayText(stored);
    _picked
      ..clear()
      ..addAll(picked);
    text.value = TextEditingValue(
      text: display,
      selection: TextSelection.collapsed(offset: display.length),
    );
  }

  void insertAtCursor(String value) {
    final selection = text.selection;
    final start = selection.isValid ? selection.start : text.text.length;
    final end = selection.isValid ? selection.end : text.text.length;
    final newText = text.text.replaceRange(start, end, value);
    text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  void _pick(Person person, int start) {
    final mention = PickedMention(
      person.id,
      sanitizeMentionName(person.fullName),
    );
    _picked.add(mention);
    final cursor = text.selection.isValid
        ? text.selection.baseOffset
        : text.text.length;
    final replacement = '${mention.display} ';
    final newText = text.text.replaceRange(start, cursor, replacement);
    text.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  void dispose() => text.dispose();
}

/// A text box that suggests people after typing "@".
class MentionTextField extends ConsumerStatefulWidget {
  const MentionTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.minLines = 1,
    this.maxLines = 8,
    this.autofocus = false,
    this.onSubmit,
    this.fieldKey,
  });

  final MentionController controller;
  final String? hintText;
  final int minLines;
  final int maxLines;
  final bool autofocus;

  /// Called on Ctrl+Enter.
  final VoidCallback? onSubmit;
  final Key? fieldKey;

  @override
  ConsumerState<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends ConsumerState<MentionTextField> {
  Timer? _debounce;
  ({int start, String query})? _active;
  List<Person> _suggestions = const [];
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.text.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final value = widget.controller.text.value;
    final active = activeMentionQuery(value.text, value.selection.baseOffset);
    if (active?.query == _active?.query && active?.start == _active?.start) {
      return;
    }
    _active = active;
    _debounce?.cancel();
    if (active == null) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        final people = await ref
            .read(feedRepositoryProvider)
            .searchPeople(active.query);
        if (!mounted || _active != active) return;
        setState(() {
          _suggestions = people;
          _highlight = 0;
        });
      } catch (_) {
        // Suggestions are a convenience; ignore network errors.
      }
    });
  }

  void _choose(Person person) {
    final active = _active;
    if (active == null) return;
    widget.controller._pick(person, active.start);
    setState(() {
      _suggestions = const [];
      _active = null;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_suggestions.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _highlight = (_highlight + 1) % _suggestions.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(
          () => _highlight =
              (_highlight - 1 + _suggestions.length) % _suggestions.length,
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
        _choose(_suggestions[_highlight]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        setState(() => _suggestions = const []);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isControlPressed &&
        widget.onSubmit != null) {
      widget.onSubmit!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          onKeyEvent: _onKey,
          child: TextField(
            key: widget.fieldKey,
            controller: widget.controller.text,
            autofocus: widget.autofocus,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: widget.hintText,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        if (_active != null &&
            _suggestions.isEmpty &&
            _active!.query.length >= 2)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.noPeopleFound,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_suggestions.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            elevation: 3,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, person) in _suggestions.indexed)
                    ListTile(
                      dense: true,
                      selected: i == _highlight,
                      leading: PersonAvatar(person, radius: 16),
                      title: Text(person.fullName),
                      subtitle: person.jobTitle == null
                          ? null
                          : Text(person.jobTitle!),
                      onTap: () => _choose(person),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
