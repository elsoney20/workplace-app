import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/storage/signed_urls.dart';
import '../../../core/widgets/motion.dart';
import '../domain/post_attachment.dart';

/// A video that plays right inside the post (like Facebook): it shows a
/// still picture first, a click plays it in place, and it can go full
/// screen and back.
class InlineVideo extends ConsumerStatefulWidget {
  const InlineVideo({
    super.key,
    required this.video,
    required this.bucket,
    this.poster,
    required this.fallback,
  });

  final PostAttachment video;
  final String bucket;

  /// Optional still picture shown before the video starts.
  final PostAttachment? poster;

  /// Shown if this computer can't play the video here (opens it outside).
  final Widget fallback;

  @override
  ConsumerState<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends ConsumerState<InlineVideo> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final url = await ref.read(signedUrlCacheProvider).urlFor((
        bucket: widget.bucket,
        path: widget.video.storagePath,
      ));
      if (url == null || !mounted) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      setState(() => _c = c);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final c = _c;
    if (c != null && c.value.isCompleted && c.value.isPlaying == false) {
      // Back to the start, like Facebook.
      unawaited(c.seekTo(Duration.zero));
    }
    setState(() {});
  }

  @override
  void dispose() {
    final c = _c;
    if (c != null) {
      c.removeListener(_onTick);
      unawaited(c.dispose());
    }
    super.dispose();
  }

  void _toggle() {
    final c = _c;
    if (c == null) return;
    setState(() => _started = true);
    unawaited(c.value.isPlaying ? c.pause() : c.play());
  }

  Future<void> _fullScreen() async {
    final c = _c;
    if (c == null) return;
    setState(() => _started = true);
    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, _, _) => _FullScreenVideo(controller: c),
      transitionBuilder: (context, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(
            begin: .94,
            end: 1,
          ).animate(CurvedAnimation(parent: anim, curve: kSmooth)),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ratio = c != null && c.value.isInitialized && c.value.aspectRatio > 0
        ? c.value.aspectRatio.clamp(.6, 2.2).toDouble()
        : 16 / 9;

    if (_failed) {
      return widget.fallback;
    }

    final poster = widget.poster;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: AspectRatio(
        aspectRatio: ratio,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (c != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
                ),
              if (!_started && poster != null)
                _Poster(poster: poster, bucket: widget.bucket),
              if (c == null)
                const Center(
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else
                _Controls(
                  controller: c,
                  onToggle: _toggle,
                  onFullScreen: _fullScreen,
                  fullScreen: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Poster extends ConsumerWidget {
  const _Poster({required this.poster, required this.bucket});

  final PostAttachment poster;
  final String bucket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(
      signedUrlProvider((bucket: bucket, path: poster.storagePath)),
    );
    return switch (url) {
      AsyncData(value: final link?) => IgnorePointer(
        child: Image.network(link, fit: BoxFit.cover),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Big play button in the middle, and a slim bar (progress, time, sound,
/// full screen) that shows while paused or when the mouse is over it.
class _Controls extends StatefulWidget {
  const _Controls({
    required this.controller,
    required this.onToggle,
    required this.onFullScreen,
    required this.fullScreen,
  });

  final VideoPlayerController controller;
  final VoidCallback onToggle;
  final VoidCallback onFullScreen;
  final bool fullScreen;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final v = widget.controller.value;
    final playing = v.isPlaying;
    final showBar = !playing || _hover;
    final total = v.duration.inMilliseconds;
    final progress = total == 0
        ? 0.0
        : (v.position.inMilliseconds / total).clamp(0.0, 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        onDoubleTap: widget.onFullScreen,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AnimatedScale(
                scale: playing ? .6 : 1,
                duration: const Duration(milliseconds: 260),
                curve: kSpring,
                child: AnimatedOpacity(
                  opacity: playing ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Tooltip(
                    message: l10n.playVideo,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: .55),
                        border: Border.all(color: Colors.white70, width: 2),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: showBar ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 18, 6, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xAA000000)],
                    ),
                  ),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          color: Colors.white,
                          onPressed: widget.onToggle,
                          icon: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                        Text(
                          '${_fmt(v.position)} / ${_fmt(v.duration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'Poppins',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SeekBar(
                            progress: progress,
                            onSeek: (f) => widget.controller.seekTo(
                              Duration(milliseconds: (total * f).round()),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          color: Colors.white,
                          onPressed: () =>
                              widget.controller.setVolume(v.volume > 0 ? 0 : 1),
                          icon: Icon(
                            v.volume > 0
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                          ),
                        ),
                        IconButton(
                          key: const Key('videoFullScreen'),
                          visualDensity: VisualDensity.compact,
                          color: Colors.white,
                          tooltip: widget.fullScreen
                              ? l10n.exitFullScreen
                              : l10n.fullScreen,
                          onPressed: widget.onFullScreen,
                          icon: Icon(
                            widget.fullScreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.progress, required this.onSeek});

  final double progress;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, box) {
        void seek(Offset local) =>
            onSeek((local.dx / box.maxWidth).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition),
          onHorizontalDragUpdate: (d) => seek(d.localPosition),
          child: SizedBox(
            height: 22,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FullScreenVideo extends StatelessWidget {
  const _FullScreenVideo({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.pop(context),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              controller.value.isPlaying
              ? controller.pause()
              : controller.play(),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              ),
              _Controls(
                controller: controller,
                onToggle: () => controller.value.isPlaying
                    ? controller.pause()
                    : controller.play(),
                onFullScreen: () => Navigator.pop(context),
                fullScreen: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
