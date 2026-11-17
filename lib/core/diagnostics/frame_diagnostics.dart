import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Opt-in performance log for support: start the app with the environment
/// variable G2E_DIAG=1 and every 5 seconds it appends to
/// %TEMP%\g2e_diag.txt how many frames were drawn and how many animations
/// (tickers) are running. An idle app should show 0 frames.
class FrameDiagnostics {
  static void startIfEnabled() {
    if (Platform.environment['G2E_DIAG'] != '1') return;
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}g2e_diag.txt',
    );
    var frames = 0;
    var buildUs = 0;
    var rasterUs = 0;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      frames += timings.length;
      for (final t in timings) {
        buildUs += t.buildDuration.inMicroseconds;
        rasterUs += t.rasterDuration.inMicroseconds;
      }
    });
    Timer.periodic(const Duration(seconds: 5), (_) {
      final s = SchedulerBinding.instance;
      final line =
          '${DateTime.now().toIso8601String()} frames=$frames '
          'build_ms=${(buildUs / 1000).toStringAsFixed(1)} '
          'raster_ms=${(rasterUs / 1000).toStringAsFixed(1)} '
          'tickers=${s.transientCallbackCount} '
          'phase=${s.schedulerPhase.name}\n';
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
      frames = 0;
      buildUs = 0;
      rasterUs = 0;
    });
  }
}
