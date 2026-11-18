import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/rich_text.dart';

/// Post/comment text with clickable #hashtags, @mentions and links.
class RichBody extends StatefulWidget {
  const RichBody(
    this.body, {
    super.key,
    this.style,
    this.onHashtag,
    this.onMention,
  });

  final String body;
  final TextStyle? style;
  final void Function(String tag)? onHashtag;
  final void Function(String profileId, String name)? onMention;

  @override
  State<RichBody> createState() => _RichBodyState();
}

class _RichBodyState extends State<RichBody> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodyLarge;
    final accent = base?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[
      for (final segment in parseRichText(widget.body))
        switch (segment) {
          PlainSegment() => TextSpan(text: segment.text),
          MentionSegment() => TextSpan(
            text: '@${segment.text}',
            style: accent,
            recognizer: widget.onMention == null
                ? null
                : _tap(
                    () => widget.onMention!(segment.profileId, segment.text),
                  ),
          ),
          HashtagSegment() => TextSpan(
            text: segment.text,
            style: accent,
            recognizer: widget.onHashtag == null
                ? null
                : _tap(() => widget.onHashtag!(segment.tag)),
          ),
          LinkSegment() => TextSpan(
            text: segment.text,
            style: accent?.copyWith(decoration: TextDecoration.underline),
            recognizer: _tap(
              () => launchUrl(
                Uri.parse(segment.text),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        },
    ];
    return SelectionArea(
      child: Text.rich(TextSpan(style: base, children: spans)),
    );
  }
}
