import 'package:flutter_test/flutter_test.dart';
import 'package:workplace_app/features/feed/domain/feed_post.dart';
import 'package:workplace_app/features/feed/domain/person.dart';
import 'package:workplace_app/features/feed/domain/rich_text.dart';

const _sara = '00000000-0000-0000-0000-0000000000a1';

void main() {
  test('mentions, hashtags and links are recognised', () {
    final segments = parseRichText(
      'Hi @[Sara Ali]($_sara) see #Sales and #مبيعات at https://x.com ok',
    );
    expect(segments.whereType<MentionSegment>().single.profileId, _sara);
    expect(segments.whereType<MentionSegment>().single.text, 'Sara Ali');
    expect(segments.whereType<HashtagSegment>().map((h) => h.tag), [
      'sales',
      'مبيعات',
    ]);
    expect(segments.whereType<LinkSegment>().single.text, 'https://x.com');
    expect(
      segments.map((s) => s.text).join(),
      'Hi Sara Ali see #Sales and #مبيعات at https://x.com ok',
    );
  });

  test('a # inside a word is not a hashtag', () {
    expect(
      parseRichText('I like C# a lot').whereType<HashtagSegment>(),
      isEmpty,
    );
  });

  test('picked mentions become markup and back', () {
    const picked = [PickedMention(_sara, 'Sara Ali')];
    final stored = toStoredText('Thanks @Sara Ali!', picked);
    expect(stored, 'Thanks @[Sara Ali]($_sara)!');
    final (display, back) = toDisplayText(stored);
    expect(display, 'Thanks @Sara Ali!');
    expect(back.single.profileId, _sara);
    expect(plainText(stored), 'Thanks @Sara Ali!');
  });

  test('longer names win over shorter ones', () {
    const picked = [
      PickedMention('00000000-0000-0000-0000-000000000001', 'Sara'),
      PickedMention(_sara, 'Sara Ali'),
    ];
    expect(
      toStoredText('@Sara Ali and @Sara', picked),
      '@[Sara Ali]($_sara) and @[Sara](00000000-0000-0000-0000-000000000001)',
    );
  });

  test('the @ query is found at the cursor', () {
    expect(activeMentionQuery('Hello @Sa', 9), (start: 6, query: 'Sa'));
    expect(activeMentionQuery('Hello @', 7), (start: 6, query: ''));
    expect(activeMentionQuery('mail a@b', 8), isNull);
    expect(activeMentionQuery('no mention', 10), isNull);
  });

  test('changing my reaction updates the counts', () {
    final post = FeedPost(
      id: 'p',
      author: const Person(id: 'a', fullName: 'A'),
      body: '',
      createdAt: DateTime(2026),
      reactions: const {'👍': 2},
      myReaction: '👍',
    );
    final changed = post.withMyReaction('❤️');
    expect(changed.reactions, {'👍': 1, '❤️': 1});
    expect(changed.withMyReaction(null).reactions, {'👍': 1});
  });

  test('initials work for Arabic and English names', () {
    expect(const Person(id: '1', fullName: 'sara ali').initials, 'SA');
    expect(const Person(id: '1', fullName: 'محمد').initials, 'م');
  });
}
