import 'dart:async';

import 'package:workplace_app/core/widgets/motion.dart';

/// Runs before every test file: turn off entrance animations so frames
/// settle immediately and no animation timers are left pending.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FadeSlideIn.enabled = false;
  await testMain();
}
