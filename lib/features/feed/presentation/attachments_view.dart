import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../application/feed_controller.dart';
import '../domain/post_attachment.dart';

/// Photos as a grid; videos and other files as tiles that open in the
/// computer's own player/viewer.
class AttachmentsView extends StatelessWidget {
  const AttachmentsView({super.key, required this.attachments});

  final List<PostAttachment> attachments;

  @override
  Widget build(BuildContext context) {
    final images = attachments
        .where((a) => a.kind == AttachmentKind.image)
        .toList();
    final others = attachments
        .where((a) => a.kind != AttachmentKind.image)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty) _ImageGrid(images: images),
        for (final file in others) _FileTile(file: file),
      ],
    );
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images});

  final List<PostAttachment> images;

  @override
  Widget build(BuildContext context) {
    if (images.length == 1) {
      final a = images.first;
      final ratio = (a.width != null && a.height != null && a.height! > 0)
          ? (a.width! / a.height!).clamp(0.6, 2.2)
          : 16 / 10;
      return AspectRatio(
        aspectRatio: ratio.toDouble(),
        child: _SignedImage(attachment: a, all: images, index: 0),
      );
    }
    final shown = images.take(4).toList();
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: shown.length == 2 ? 0.8 : 1.6,
        children: [
          for (final (i, a) in shown.indexed)
            Stack(
              fit: StackFit.expand,
              children: [
                _SignedImage(attachment: a, all: images, index: i),
                if (i == 3 && images.length > 4)
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Text(
                          '+${images.length - 4}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SignedImage extends ConsumerWidget {
  const _SignedImage({
    required this.attachment,
    required this.all,
    required this.index,
  });

  final PostAttachment attachment;
  final List<PostAttachment> all;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(signedUrlProvider(attachment.storagePath));
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    return switch (url) {
      AsyncData(value: final link?) => GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _ImageViewer(images: all, initial: index),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Image.network(
            link,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
            errorBuilder: (context, _, _) => Stack(
              fit: StackFit.expand,
              children: [placeholder, const Icon(Icons.broken_image_outlined)],
            ),
          ),
        ),
      ),
      AsyncLoading() => placeholder,
      _ => Stack(
        fit: StackFit.expand,
        children: [placeholder, const Icon(Icons.broken_image_outlined)],
      ),
    };
  }
}

/// Full-screen photo viewer with zoom and left/right arrows.
class _ImageViewer extends ConsumerStatefulWidget {
  const _ImageViewer({required this.images, required this.initial});

  final List<PostAttachment> images;
  final int initial;

  @override
  ConsumerState<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends ConsumerState<_ImageViewer> {
  late final PageController _pages = PageController(
    initialPage: widget.initial,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView(
            controller: _pages,
            children: [
              for (final a in widget.images)
                Consumer(
                  builder: (context, ref, _) =>
                      switch (ref.watch(signedUrlProvider(a.storagePath))) {
                        AsyncData(value: final link?) => InteractiveViewer(
                          maxScale: 5,
                          child: Center(
                            child: Image.network(link, fit: BoxFit.contain),
                          ),
                        ),
                        _ => const Center(child: CircularProgressIndicator()),
                      },
                ),
            ],
          ),
          PositionedDirectional(
            top: 8,
            end: 8,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (widget.images.length > 1) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _pages.previousPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _pages.nextPage(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({required this.file});

  final PostAttachment file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isVideo = file.kind == AttachmentKind.video;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListTile(
        leading: Icon(
          isVideo ? Icons.play_circle_fill : Icons.insert_drive_file,
          size: 36,
        ),
        title: Text(
          file.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(formatBytes(file.sizeBytes)),
        trailing: Text(l10n.openFile),
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final url = await ref
              .read(signedUrlCacheProvider)
              .urlFor(file.storagePath);
          final ok =
              url != null &&
              await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
          if (!ok) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.cannotOpenFile)),
            );
          }
        },
      ),
    );
  }
}
