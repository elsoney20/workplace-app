import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/motion.dart';

enum OtpStatus { idle, checking, success, error }

/// The 6-digit code as a 3 x 2 grid of tiles (like the reference video).
///
/// * Typing: a glowing frame slides to the next tile, digits pop in.
/// * Wrong code: the tiles get a red outline (the screen then clears them).
/// * Right code: every tile flips over and shows one slice of a picture (a
///   check mark in a ring), but shuffled. One tile disappears and the others
///   slide into the gap one by one, like a sliding puzzle, until the picture
///   is whole; then the gaps close and it glows green.
///
/// A hidden text field does the typing (keyboard, paste, backspace).
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

  /// How long the "right code" puzzle takes; the screen waits for it.
  static const Duration successDuration = Duration(milliseconds: 3400);

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

// Grid geometry.
const int _cols = 3;
const int _rows = 2;
const double _tile = 66;
const double _gap = 10;
const double _pad = 10;
const double _panelW = _cols * _tile + (_cols - 1) * _gap + 2 * _pad;
const double _panelH = _rows * _tile + (_rows - 1) * _gap + 2 * _pad;

/// The cell that is empty during the puzzle (bottom right).
const int _hole = 5;

/// Path of the empty cell while shuffling (from the solved picture). The
/// puzzle then plays it backwards, so it always ends solved.
const List<int> _shufflePath = [2, 1, 0, 3, 4, 1, 2, 5];

/// cell -> picture slice, for each step of the solve (first = shuffled).
final List<List<int>> _solveSteps = () {
  var cells = List<int>.generate(_cols * _rows, (i) => i);
  var empty = _hole;
  final states = [List<int>.of(cells)];
  for (final next in _shufflePath) {
    cells = List<int>.of(cells);
    cells[empty] = cells[next];
    cells[next] = _hole;
    empty = next;
    states.add(cells);
  }
  return states.reversed.toList();
}();

int _cellOf(List<int> state, int slice) => state.indexOf(slice);

class _OtpCodeInputState extends State<OtpCodeInput>
    with TickerProviderStateMixin {
  late final AnimationController _success = AnimationController(
    vsync: this,
    duration: OtpCodeInput.successDuration,
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  final FocusNode _focus = FocusNode();
  String _last = '';

  /// Digits shown on the tiles' front faces while they flip.
  String _frozen = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(() => setState(() {}));
    _last = widget.controller.text;
    _apply();
  }

  @override
  void didUpdateWidget(OtpCodeInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (old.status != widget.status) _apply();
  }

  void _apply() {
    switch (widget.status) {
      case OtpStatus.success:
        _frozen = widget.controller.text;
        FadeSlideIn.enabled ? _success.forward(from: 0) : _success.value = 1;
      case OtpStatus.error:
        _success.value = 0;
        if (FadeSlideIn.enabled) _shake.forward(from: 0);
        _focus.requestFocus();
      case OtpStatus.idle:
      case OtpStatus.checking:
        _success.value = 0;
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
    _success.dispose();
    _shake.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = widget.status;
    final busy = status == OtpStatus.checking || status == OtpStatus.success;

    final caption = switch (status) {
      OtpStatus.checking => l10n.codeChecking,
      OtpStatus.success => l10n.codeVerified,
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Directionality(
            // Codes always read left to right, even in Arabic.
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: _panelW,
              height: _panelH,
              child: Stack(
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
                        readOnly: busy,
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
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_success, _shake]),
                        builder: (context, _) => _buildPanel(scheme, theme),
                      ),
                    ),
                  ),
                ],
              ),
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
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      caption,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: status == OtpStatus.success
                            ? _successGreen
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

  static const Color _successGreen = Color(0xFF5FD39A);

  double _interval(double begin, double end, [Curve curve = Curves.linear]) {
    final v = ((_success.value - begin) / (end - begin)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  Widget _buildPanel(ColorScheme scheme, ThemeData theme) {
    final status = widget.status;
    final success = status == OtpStatus.success;
    final text = success ? _frozen : widget.controller.text;

    // Timeline of the "right code" puzzle (fractions of successDuration).
    final hideHole = _interval(.20, .27, Curves.easeOut);
    final solve = _interval(.28, .80) * (_solveSteps.length - 1);
    final merge = _interval(.80, .93, kSmooth);
    final gap = _gap * (1 - merge);
    final radius = 12 * (1 - merge);
    final sliceColor = Color.lerp(
      scheme.primary,
      _successGreen,
      _interval(.78, .93),
    )!;

    // Grid origin, so the tiles stay centred as the gaps close.
    final gridW = _cols * _tile + (_cols - 1) * gap;
    final gridH = _rows * _tile + (_rows - 1) * gap;
    final ox = (_panelW - gridW) / 2;
    final oy = (_panelH - gridH) / 2;
    Offset cellPos(double col, double row) =>
        Offset(ox + col * (_tile + gap), oy + row * (_tile + gap));

    final shake = _shake.isAnimating
        ? math.sin(_shake.value * math.pi * 6) * 9 * (1 - _shake.value)
        : 0.0;

    final children = <Widget>[];
    for (var cell = 0; cell < _cols * _rows; cell++) {
      // Before the puzzle every cell shows its digit tile; after the flip
      // each cell holds a picture slice that may move.
      final flip = success
          ? _interval(.02 + cell * .022, .15 + cell * .022, Curves.easeInOut)
          : 0.0;
      if (flip < .5) {
        final pos = cellPos((cell % _cols).toDouble(), (cell ~/ _cols) * 1.0);
        children.add(
          Positioned(
            left: pos.dx + shake,
            top: pos.dy,
            width: _tile,
            height: _tile,
            child: _flipped(
              flip * math.pi,
              _DigitTile(
                digit: cell < text.length ? text[cell] : null,
                error: status == OtpStatus.error,
                dim: status == OtpStatus.checking,
                scheme: scheme,
                theme: theme,
              ),
            ),
          ),
        );
        continue;
      }
      // Back face: the slice that starts in this cell, wherever it is now.
      final slice = _solveSteps.first[cell];
      final step = solve.floor().clamp(0, _solveSteps.length - 1);
      final next = (step + 1).clamp(0, _solveSteps.length - 1);
      final frac = Curves.easeInOutCubic.transform(solve - step);
      final from = _cellOf(_solveSteps[step], slice);
      final to = _cellOf(_solveSteps[next], slice);
      final col = (from % _cols) + ((to % _cols) - (from % _cols)) * frac;
      final row = (from ~/ _cols) + ((to ~/ _cols) - (from ~/ _cols)) * frac;
      final pos = cellPos(col, row.toDouble());
      var opacity = 1.0;
      if (slice == _hole) opacity = merge > 0 ? merge : 1 - hideHole;
      children.add(
        Positioned(
          left: pos.dx,
          top: pos.dy,
          width: _tile,
          height: _tile,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: _flipped(
              (flip - 1) * math.pi,
              _SliceTile(
                slice: slice,
                color: sliceColor,
                radius: radius,
                merge: merge,
                scheme: scheme,
              ),
            ),
          ),
        ),
      );
    }

    // The glowing frame that slides to the tile you type in next.
    final focusCell = text.length.clamp(0, OtpCodeInput.length - 1);
    final showFocus =
        _focus.hasFocus &&
        (status == OtpStatus.idle ||
            status == OtpStatus.checking ||
            (status == OtpStatus.error && !_shake.isAnimating));
    final focusPos = cellPos(
      (focusCell % _cols).toDouble(),
      (focusCell ~/ _cols).toDouble(),
    );

    return Container(
      decoration: BoxDecoration(
        color: Color.lerp(
          scheme.surfaceContainerLowest,
          _successGreen.withValues(alpha: .10),
          merge,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Color.lerp(
            scheme.outlineVariant,
            _successGreen.withValues(alpha: .7),
            merge,
          )!,
        ),
        boxShadow: [
          if (merge > 0)
            BoxShadow(
              color: _successGreen.withValues(alpha: .35 * merge),
              blurRadius: 28 * merge,
              spreadRadius: 2 * merge,
            ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ...children,
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: kSmooth,
            left: focusPos.dx - 3,
            top: focusPos.dy - 3,
            width: _tile + 6,
            height: _tile + 6,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: showFocus && !success ? 1 : 0,
              child: _FocusFrame(
                color: scheme.primary,
                caret:
                    text.length < OtpCodeInput.length &&
                    status == OtpStatus.idle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Turns [child] around the vertical axis (with a little perspective).
  static Widget _flipped(double angle, Widget child) {
    if (angle == 0) return child;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0018)
        ..rotateY(angle),
      child: child,
    );
  }
}

class _DigitTile extends StatelessWidget {
  const _DigitTile({
    required this.digit,
    required this.error,
    required this.dim,
    required this.scheme,
    required this.theme,
  });

  final String? digit;
  final bool error;
  final bool dim;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: error ? scheme.error : scheme.outlineVariant,
          width: error ? 2 : 1,
        ),
        boxShadow: [
          if (error)
            BoxShadow(
              color: scheme.error.withValues(alpha: .35),
              blurRadius: 10,
            ),
        ],
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: kSpring,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: .6, end: 1).animate(anim),
            child: child,
          ),
        ),
        child: digit == null
            ? Container(
                key: const ValueKey('dot'),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outline,
                  shape: BoxShape.circle,
                ),
              )
            : Text(
                digit!,
                key: ValueKey(digit),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                  color: dim
                      ? scheme.onSurface.withValues(alpha: .55)
                      : scheme.onSurface,
                ),
              ),
      ),
    );
  }
}

/// One slice of the check-in-a-ring picture.
class _SliceTile extends StatelessWidget {
  const _SliceTile({
    required this.slice,
    required this.color,
    required this.radius,
    required this.merge,
    required this.scheme,
  });

  final int slice;
  final Color color;
  final double radius;
  final double merge;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CustomPaint(
        painter: _SlicePainter(
          slice: slice,
          color: color,
          background: Color.lerp(
            scheme.surfaceContainerHigh,
            color.withValues(alpha: .14),
            merge,
          )!,
          lines: scheme.outlineVariant.withValues(alpha: .5 * (1 - merge * .6)),
        ),
      ),
    );
  }
}

class _SlicePainter extends CustomPainter {
  _SlicePainter({
    required this.slice,
    required this.color,
    required this.background,
    required this.lines,
  });

  final int slice;
  final Color color;
  final Color background;
  final Color lines;

  @override
  void paint(Canvas canvas, Size size) {
    final t = size.width;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    canvas.save();
    // Draw the whole picture (3 x 2 tiles) shifted so this slice shows.
    canvas.translate(-(slice % _cols) * t, -(slice ~/ _cols) * t);
    final w = _cols * t;
    final h = _rows * t;
    final c = Offset(w / 2, h / 2);
    final r = h * .40;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * .065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawCircle(c, r, stroke);
    final check = Path()
      ..moveTo(c.dx - r * .48, c.dy + r * .02)
      ..lineTo(c.dx - r * .12, c.dy + r * .36)
      ..lineTo(c.dx + r * .52, c.dy - r * .34);
    canvas.drawPath(check, stroke..strokeWidth = h * .085);
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(.5),
        const Radius.circular(2),
      ),
      Paint()
        ..color = lines
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SlicePainter old) =>
      old.slice != slice ||
      old.color != color ||
      old.background != background ||
      old.lines != lines;
}

class _FocusFrame extends StatelessWidget {
  const _FocusFrame({required this.color, required this.caret});

  final Color color;
  final bool caret;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .45), blurRadius: 14),
        ],
      ),
      alignment: Alignment.center,
      child: caret ? Container(width: 2, height: 26, color: color) : null,
    );
  }
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
