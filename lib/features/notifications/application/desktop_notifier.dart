import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';

import '../../../core/config/brand_config.dart';

/// Native Windows / macOS / Linux notifications ("toasts").
/// Mobile push (FCM / APNs) comes in Phase 8.
class DesktopNotifier {
  DesktopNotifier({this.enabled = true});

  final bool enabled;
  bool _ready = false;

  /// Set by the app: what to open when a toast is clicked.
  void Function(Map<String, dynamic> target)? onOpen;

  static bool get supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> _setup() async {
    if (_ready || !enabled || !supported) return;
    await localNotifier.setup(
      appName: BrandConfig.appName,
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    _ready = true;
  }

  Future<void> show({
    required String title,
    String? body,
    Map<String, dynamic> target = const {},
  }) async {
    if (!enabled || !supported) return;
    try {
      await _setup();
      final notification = LocalNotification(title: title, body: body);
      notification.onClick = () => onOpen?.call(target);
      await notification.show();
    } catch (_) {
      // A failed toast must never break the app.
    }
  }

  /// Text is generic on purpose: the toast is shown by Windows, so keep
  /// message contents out of it.
  Future<void> showForNotificationRow(Map<String, dynamic> row) async {
    final type = row['type'] as String? ?? '';
    final target = row['target'] is Map
        ? Map<String, dynamic>.from(row['target'] as Map)
        : <String, dynamic>{};
    await show(
      title: BrandConfig.appName,
      body: _titleFor(type),
      target: target,
    );
  }

  String _titleFor(String type) => switch (type) {
    'mention' => 'You were mentioned / تم عمل منشن لك',
    'comment' => 'New comment / تعليق جديد',
    'reply' => 'New reply / رد جديد',
    'reaction' => 'New reaction / تفاعل جديد',
    'announcement' => 'New announcement / إعلان جديد',
    'group_invite' => 'Added to a group / اتضفت لجروب',
    'report_update' => 'Report reviewed / البلاغ اتراجع',
    _ => 'New notification / إشعار جديد',
  };
}

final desktopNotifierProvider = Provider<DesktopNotifier>(
  (ref) => DesktopNotifier(),
);
