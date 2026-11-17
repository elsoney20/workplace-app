/// Parsing of post/comment text.
///
/// Stored format (what the database keeps):
///   "Thanks @[Sara Ali](3f0c...-uuid) for #Sales"
/// Display format (what people type and see in the text box):
///   "Thanks @Sara Ali for #Sales"
///
/// The server reads the same markup to save mentions and send notifications,
/// so these patterns must stay in sync with
/// supabase/migrations/20261117160000_phase3_feed.sql.
library;

final RegExp mentionMarkup = RegExp(
  r'@\[([^\]\n]{1,120})\]\(([0-9a-fA-F-]{36})\)',
);

/// Latin/other letters + digits + underscore, plus the Arabic block.
final RegExp hashtagPattern = RegExp(
  r'#([\p{L}\p{N}_؀-ۿ]{1,64})',
  unicode: true,
);

final RegExp urlPattern = RegExp(r'https?://[^\s<>()]+', caseSensitive: false);

sealed class TextSegment {
  const TextSegment(this.text);
  final String text;
}

class PlainSegment extends TextSegment {
  const PlainSegment(super.text);
}

class MentionSegment extends TextSegment {
  const MentionSegment(super.text, this.profileId);

  /// Display text without '@'.
  final String profileId;
}

class HashtagSegment extends TextSegment {
  const HashtagSegment(super.text);

  /// Lower-case tag without '#', as stored on the server.
  String get tag => text.substring(1).toLowerCase();
}

class LinkSegment extends TextSegment {
  const LinkSegment(super.text);
}

/// Splits stored text into pieces for display.
List<TextSegment> parseRichText(String body) {
  final segments = <TextSegment>[];
  var index = 0;
  for (final match in mentionMarkup.allMatches(body)) {
    if (match.start > index) {
      segments.addAll(_parsePlain(body.substring(index, match.start)));
    }
    segments.add(MentionSegment(match.group(1)!, match.group(2)!));
    index = match.end;
  }
  if (index < body.length) segments.addAll(_parsePlain(body.substring(index)));
  return segments;
}

List<TextSegment> _parsePlain(String text) {
  final segments = <TextSegment>[];
  final matches = [
    ...hashtagPattern.allMatches(text).map((m) => (m, true)),
    ...urlPattern.allMatches(text).map((m) => (m, false)),
  ]..sort((a, b) => a.$1.start.compareTo(b.$1.start));

  var index = 0;
  for (final (match, isTag) in matches) {
    if (match.start < index) continue; // overlaps a previous match
    // A '#' in the middle of a word (e.g. "C#") is not a hashtag.
    if (isTag && match.start > 0 && _isWordChar(text[match.start - 1])) {
      continue;
    }
    if (match.start > index) {
      segments.add(PlainSegment(text.substring(index, match.start)));
    }
    final value = match.group(0)!;
    segments.add(isTag ? HashtagSegment(value) : LinkSegment(value));
    index = match.end;
  }
  if (index < text.length) segments.add(PlainSegment(text.substring(index)));
  return segments;
}

bool _isWordChar(String char) =>
    RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(char);

/// Plain text without markup, e.g. for previews and search.
String plainText(String body) =>
    body.replaceAllMapped(mentionMarkup, (m) => '@${m.group(1)}');

/// A person picked from the "@" suggestions while writing.
class PickedMention {
  const PickedMention(this.profileId, this.name);
  final String profileId;
  final String name;

  String get display => '@$name';
  String get markup => '@[${sanitizeMentionName(name)}]($profileId)';
}

/// Names cannot contain the characters used by the markup.
String sanitizeMentionName(String name) =>
    name.replaceAll(RegExp(r'[\[\]\(\)\n]'), ' ').trim();

/// Turns what the person typed back into stored text: every "@Name" that was
/// picked from the suggestions becomes markup. Longer names first, so that
/// "@Sara Ali" wins over "@Sara".
String toStoredText(String display, Iterable<PickedMention> picked) {
  final unique = {for (final p in picked) p.display: p}.values.toList()
    ..sort((a, b) => b.display.length.compareTo(a.display.length));
  var result = display;
  for (final mention in unique) {
    result = result.replaceAll(mention.display, mention.markup);
  }
  return result.trim();
}

/// The opposite of [toStoredText], used when editing an existing post.
(String, List<PickedMention>) toDisplayText(String stored) {
  final picked = <PickedMention>[];
  final display = stored.replaceAllMapped(mentionMarkup, (m) {
    final mention = PickedMention(m.group(2)!, m.group(1)!);
    picked.add(mention);
    return mention.display;
  });
  return (display, picked);
}

/// If the cursor is right after "@something", returns that query (may be
/// empty) and where the '@' is. Used to show people suggestions.
({int start, String query})? activeMentionQuery(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  if (at > 0 && !RegExp(r'\s').hasMatch(before[at - 1])) return null;
  final query = before.substring(at + 1);
  if (query.length > 40 || query.contains('\n')) return null;
  // Allow one space inside a name ("Sara A"), but not two words + space.
  if (RegExp(r'\s\S*\s').hasMatch(query)) return null;
  return (start: at, query: query);
}
