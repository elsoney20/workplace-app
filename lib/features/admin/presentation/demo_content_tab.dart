import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../feed/application/feed_controller.dart';
import '../../feed/data/feed_repository.dart';

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

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    final feed = ref.read(feedRepositoryProvider);
    final client = ref.read(supabaseClientProvider);
    await _run(() async {
      // Posts with media are created as me (Storage uploads can't be
      // done from SQL). The database seed then adds colleagues' reactions
      // and comments to my newest three posts.
      await feed.createPost(
        authorId: widget.myProfileId,
        body: l10n.demoPost3,
        uploads: [
          await _asset('new_arrivals.mp4'),
          await _asset('new_arrivals.jpg'),
        ],
      );
      await feed.createPost(
        authorId: widget.myProfileId,
        body: l10n.demoPost2,
        uploads: [await _asset('g2e_cup.jpg')],
      );
      await feed.createPost(
        authorId: widget.myProfileId,
        body: l10n.demoPost1,
        uploads: [await _asset('black_friday.jpg')],
        announcement: true,
      );
      await client.rpc<void>('seed_demo_content');
    }, l10n.demoLoaded);
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
