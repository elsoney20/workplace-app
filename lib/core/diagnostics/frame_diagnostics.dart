import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Opt-in performance log for support: start the app with the environment
/// variable G2E_DIAG=1 and every 5 seconds it appends to
/// %TEMP%\g2e_diag.txt how many frames were drawn and how many animations
/// (tickers) are running. An idle app should show 0 frames.
///
/// Errors are logged in every build. A debug build also logs which widgets
/// were rebuilt, which render objects were repainted, and one sample of
/// what asked for a new frame, so a busy idle app can be pinned down.
class FrameDiagnostics {
  static void startIfEnabled() {
    if (Platform.environment['G2E_DIAG'] != '1') return;
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}g2e_diag.txt',
    );
    void write(String s) =>
        file.writeAsStringSync(s, mode: FileMode.append, flush: true);

    var frames = 0;
    var buildUs = 0;
    var rasterUs = 0;
    final rebuilt = <String, int>{};
    final painted = <String, int>{};
    final errors = <String>[];
    final stack = <String>[];
    var capturing = false;

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (errors.length < 3) {
        errors.add(details.exceptionAsString().split('\n').first);
      }
      previousOnError?.call(details);
    };

    if (kDebugMode) {
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final w = element.widget;
        var k = w.runtimeType.toString();
        if (w is Image) {
          // Which picture: file name without the signed-link token.
          final d = w.image.toString().split('?').first;
          k = 'Image(${d.length > 90 ? d.substring(d.length - 90) : d})';
        }
        rebuilt[k] = (rebuilt[k] ?? 0) + 1;
      };
      debugOnProfilePaint = (renderObject) {
        final k = renderObject.runtimeType.toString();
        painted[k] = (painted[k] ?? 0) + 1;
      };
      debugProfilePaintsEnabled = true;
      // Keep the first "who scheduled a frame" stack of each 5 s window.
      debugPrintScheduleFrameStacks = true;
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        final m = message ?? '';
        if (m.startsWith('scheduleFrame() called')) {
          capturing = stack.isEmpty;
        }
        if (capturing && stack.length < 30) {
          stack.add(m);
          return;
        }
        if (!m.startsWith('#') && !m.startsWith('scheduleFrame')) {
          original(message, wrapWidth: wrapWidth);
        }
      };
    }

    SchedulerBinding.instance.addTimingsCallback((timings) {
      frames += timings.length;
      for (final t in timings) {
        buildUs += t.buildDuration.inMicroseconds;
        rasterUs += t.rasterDuration.inMicroseconds;
      }
    });

    String top(Map<String, int> m) {
      final e = m.entries.toList()..sort((a, b) => b.value - a.value);
      return e.take(8).map((x) => '${x.key}:${x.value}').join(' ');
    }

    Timer.periodic(const Duration(seconds: 5), (_) {
      final s = SchedulerBinding.instance;
      final b = StringBuffer(
        '${DateTime.now().toIso8601String()} frames=$frames '
        'build_ms=${(buildUs / 1000).toStringAsFixed(1)} '
        'raster_ms=${(rasterUs / 1000).toStringAsFixed(1)} '
        'tickers=${s.transientCallbackCount} '
        'phase=${s.schedulerPhase.name}\n',
      );
      if (errors.isNotEmpty) b.writeln('  errors: ${errors.join(' | ')}');
      if (rebuilt.isNotEmpty) b.writeln('  rebuilt: ${top(rebuilt)}');
      if (painted.isNotEmpty) b.writeln('  painted: ${top(painted)}');
      if (frames > 0 && stack.isNotEmpty) {
        b.writeln('  scheduled by:');
        for (final l in stack) {
          b.writeln('    $l');
        }
      }
      write(b.toString());
      frames = 0;
      buildUs = 0;
      rasterUs = 0;
      rebuilt.clear();
      painted.clear();
      errors.clear();
      stack.clear();
      capturing = false;
    });
  }
}
