import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../feed/application/feed_controller.dart';
import '../../chat/application/chat_providers.dart';
import '../../engagement/application/engagement_providers.dart';
import '../../feed/data/feed_repository.dart';
import '../application/demo_script.dart';

/// Admin-only: fills the app with sample posts (with photos and a video),
/// colleagues, a group and chats, so the app can be tried before launch.
class DemoContentTab extends ConsumerStatefulWidget {
  const DemoContentTab({super.key, required this.myProfileId});

  final String myProfileId;

  @override
  ConsumerState<DemoContentTab> createState() => _DemoContentTabState();
}

class _DemoContentTabState extends ConsumerState<DemoContentTab> {
  bool _busy = false;

  Future<PendingUpload> _asset(String name) async {
    final data = await rootBundle.load('assets/demo/$name');
    return PendingUpload(name: name, bytes: data.buffer.asUint8List());
  }

  Future<void> _run(Future<void> Function() job, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await job();
      ref.invalidate(feedControllerProvider(null));
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.errorNetwork}\n$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bundled demo file, or null if it isn't in this build.
  Future<PendingUpload?> _tryAsset(String name) async {
    try {
      return await _asset(name);
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    final feed = ref.read(feedRepositoryProvider);
    final client = ref.read(supabaseClientProvider);
    await _run(() async {
      // Start clean, so loading twice simply refreshes the demo.
      await client.rpc<void>('remove_demo_content');
      await client.rpc<void>('seed_demo_content');
      // Birthdays, events, kudos and a poll.
      await client.rpc<void>('seed_demo_extras');
      // Photo / video posts: made as me (only a post's author may upload
      // its files), then handed to a demo colleague with its comments.
      for (final post in demoPosts) {
        final uploads = <PendingUpload>[];
        for (final f in post.files) {
          final file = await _tryAsset(f);
          if (file != null) uploads.add(file);
        }
        if (uploads.isEmpty) continue;
        final id = await feed.createPost(
          authorId: widget.myProfileId,
          body: post.body,
          uploads: uploads,
          announcement: post.announcement,
        );
        await client.rpc<void>(
          'adopt_demo_post',
          params: {
            'p_post': id,
            'p_author': post.author,
            'p_minutes_ago': post.minutesAgo,
            'p_comments': [for (final c in post.comments) c.toJson()],
          },
        );
      }
      ref.invalidate(conversationsProvider);
      ref.invalidate(homeSidebarProvider);
    }, l10n.demoLoaded);
  }

  Future<void> _showCredits() async {
    final l10n = AppLocalizations.of(context);
    var text = '';
    try {
      text = await rootBundle.loadString('assets/demo/CREDITS.txt');
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.demoPhotoCredits),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText('${l10n.demoPhotoCreditsBody}\n\n$text'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final client = ref.read(supabaseClientProvider);
    await _run(() => client.rpc<void>('remove_demo_content'), l10n.demoRemoved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      l10n.demoContentTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(l10n.demoContentBody),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      key: const Key('demoLoad'),
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.download),
                      label: Text(l10n.demoLoad),
                    ),
                    TextButton.icon(
                      onPressed: _showCredits,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(l10n.demoPhotoCredits),
                    ),
                    OutlinedButton.icon(
                      key: const Key('demoRemove'),
                      onPressed: _busy ? null : _remove,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(l10n.demoRemove),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
