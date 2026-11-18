import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/motion.dart';

enum OtpStatus { idle, checking, success, error }

/// Six code tiles. Each digit flips in as it is typed; when the code is
/// being checked the tiles slide together and merge into a round badge with
/// a spinner, which draws a check mark when the code is right. A wrong code
/// shakes the tiles and outlines them in red.
///
/// A hidden text field does the typing (keyboard, paste, backspace), so it
/// works like any normal field.
class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.status = OtpStatus.idle,
    this.autofocus = true,
  });

  final TextEditingController controller;

  /// Called when all six digits are in.
  final VoidCallback onCompleted;
  final OtpStatus status;
  final bool autofocus;

  static const int length = 6;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput>
    with TickerProviderStateMixin {
  late final AnimationController _merge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _check = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  final FocusNode _focus = FocusNode();
  String _last = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(() => setState(() {}));
    _last = widget.controller.text;
    _apply(null);
  }

  @override
  void didUpdateWidget(OtpCodeInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.status != widget.status) _apply(old.status);
  }

  void _apply(OtpStatus? from) {
    final animate = FadeSlideIn.enabled;
    switch (widget.status) {
      case OtpStatus.checking:
        animate ? _merge.forward() : _merge.value = 1;
        _check.value = 0;
      case OtpStatus.success:
        if (animate) {
          _merge.forward();
          _check.forward();
        } else {
          _merge.value = 1;
          _check.value = 1;
        }
      case OtpStatus.error:
        _check.value = 0;
        if (animate) {
          _merge.reverse();
          _shake.forward(from: 0);
        } else {
          _merge.value = 0;
        }
        _focus.requestFocus();
      case OtpStatus.idle:
        _check.value = 0;
        animate ? _merge.reverse() : _merge.value = 0;
    }
  }

  void _changed() {
    final text = widget.controller.text;
    if (text == _last) return;
    _last = text;
    setState(() {});
    if (text.length == OtpCodeInput.length &&
        widget.status != OtpStatus.checking &&
        widget.status != OtpStatus.success) {
      widget.onCompleted();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _merge.dispose();
    _check.dispose();
    _shake.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = widget.controller.text;
    final status = widget.status;

    final caption = switch (status) {
      OtpStatus.checking => l10n.codeChecking,
      OtpStatus.success => l10n.codeVerified,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Directionality(
          // Codes always read left to right, even in Arabic.
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 68,
            child: LayoutBuilder(
              builder: (context, box) {
                const gap = 10.0;
                final tile = math.min(
                  56.0,
                  (box.maxWidth - gap * (OtpCodeInput.length - 1)) /
                      OtpCodeInput.length,
                );
                final rowWidth =
                    tile * OtpCodeInput.length +
                    gap * (OtpCodeInput.length - 1);
                final left0 = (box.maxWidth - rowWidth) / 2;
                final center = box.maxWidth / 2;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The real (invisible) field: typing, paste, backspace.
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          key: const Key('codeField'),
                          controller: widget.controller,
                          focusNode: _focus,
                          autofocus: widget.autofocus,
                          enabled:
                              status != OtpStatus.checking &&
                              status != OtpStatus.success,
                          keyboardType: TextInputType.number,
                          maxLength: OtpCodeInput.length,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_merge, _shake]),
                        builder: (context, _) {
                          final m = kSmooth.transform(_merge.value);
                          final s = _shake.value;
                          final shakeDx = _shake.isAnimating
                              ? math.sin(s * math.pi * 6) * 10 * (1 - s)
                              : 0.0;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (var i = 0; i < OtpCodeInput.length; i++)
                                _placedTile(
                                  i: i,
                                  text: text,
                                  tile: tile,
                                  left: left0 + i * (tile + gap),
                                  center: center,
                                  merge: m,
                                  dx: shakeDx,
                                  scheme: scheme,
                                  theme: theme,
                                ),
                              if (m > 0.35)
                                Positioned(
                                  left: center - 30,
                                  top: 4,
                                  child: Opacity(
                                    opacity: ((m - 0.35) / 0.65).clamp(0, 1),
                                    child: Transform.scale(
                                      scale: 0.6 + 0.4 * m,
                                      child: _Badge(
                                        check: _check,
                                        color: scheme.primary,
                                        onColor: scheme.onPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: kSmooth,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: caption == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    key: ValueKey(caption),
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      caption,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: status == OtpStatus.success
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _placedTile({
    required int i,
    required String text,
    required double tile,
    required double left,
    required double center,
    required double merge,
    required double dx,
    required ColorScheme scheme,
    required ThemeData theme,
  }) {
    final status = widget.status;
    final digit = i < text.length ? text[i] : null;
    final active =
        _focus.hasFocus && i == text.length && status == OtpStatus.idle;
    final error = status == OtpStatus.error;
    final borderColor = error
        ? scheme.error
        : active
        ? scheme.primary
        : digit != null
        ? scheme.primary.withValues(alpha: .55)
        : scheme.outlineVariant;

    // Slide toward the middle, shrink and fade while merging.
    final tileCenter = left + tile / 2;
    final x = left + (center - tileCenter) * merge + dx;
    final scale = 1 - 0.45 * merge;
    final opacity = (1 - merge * 1.4).clamp(0.0, 1.0);

    return Positioned(
      left: x,
      top: (68 - tile * 1.15) / 2,
      width: tile,
      height: tile * 1.15,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: digit != null
                  ? scheme.primary.withValues(alpha: .10)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: active || error ? 2 : 1.2,
              ),
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: kSpring,
              transitionBuilder: (child, anim) => AnimatedBuilder(
                animation: anim,
                child: child,
                builder: (context, child) => Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.002)
                    ..rotateX((1 - anim.value) * math.pi / 2),
                  child: Opacity(opacity: anim.value.clamp(0, 1), child: child),
                ),
              ),
              child: Text(
                digit ?? '',
                key: ValueKey('$i-$digit'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round badge the tiles merge into: a spinner, then a check mark.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.check,
    required this.color,
    required this.onColor,
  });

  final Animation<double> check;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .45), blurRadius: 18),
        ],
      ),
      child: AnimatedBuilder(
        animation: check,
        builder: (context, _) => check.value == 0
            ? Padding(
                padding: const EdgeInsets.all(17),
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: onColor,
                ),
              )
            : CustomPaint(
                painter: _CheckPainter(kSmooth.transform(check.value), onColor),
              ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Offset(size.width * .28, size.height * .52);
    final b = Offset(size.width * .44, size.height * .67);
    final c = Offset(size.width * .73, size.height * .36);
    final first = (b - a).distance;
    final second = (c - b).distance;
    var left = (first + second) * t;
    final path = Path()..moveTo(a.dx, a.dy);
    if (left <= first) {
      final p = Offset.lerp(a, b, left / first)!;
      path.lineTo(p.dx, p.dy);
    } else {
      path.lineTo(b.dx, b.dy);
      left -= first;
      final p = Offset.lerp(b, c, left / second)!;
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// "Resend code" with a small ring that empties as the wait runs out.
class ResendCountdown extends StatelessWidget {
  const ResendCountdown({
    super.key,
    required this.secondsLeft,
    required this.total,
    required this.onResend,
  });

  final int secondsLeft;
  final int total;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final waiting = secondsLeft > 0;
    return TextButton(
      key: const Key('resendCode'),
      onPressed: waiting ? null : onResend,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (waiting) ...[
            SizedBox.square(
              dimension: 16,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: secondsLeft / total),
                duration: const Duration(milliseconds: 900),
                builder: (context, v, _) =>
                    CircularProgressIndicator(value: v, strokeWidth: 2.2),
              ),
            ),
            const SizedBox(width: 8),
          ] else ...[
            const Icon(Icons.refresh_rounded, size: 18),
            const SizedBox(width: 6),
          ],
          Text(waiting ? l10n.resendIn(secondsLeft) : l10n.resendCode),
        ],
      ),
    );
  }
}
