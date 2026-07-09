/// NotificationService
///
/// Thin wrapper around flutter_local_notifications for JanMat.
/// Used only for offline-sync confirmation toasts at the OS level.
///
/// Call [init] once in main() before runApp().
/// Call [showSyncSuccess] after a successful offline flush.

library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId   = 'janmat_sync';
  static const _channelName = 'Submission Sync';
  static const _channelDesc = 'Alerts when offline submissions are synced to JanMat';

  // ── Init ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    // Create the notification channel (Android 8+)
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.defaultImportance,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Request permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _ready = true;
  }

  // ── Notifications ─────────────────────────────────────────────────────

  /// Show "N submission(s) synced" notification after offline flush.
  Future<void> showSyncSuccess(int count) async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
        // Subtle — no sound, no vibration for a background sync
        playSound: false,
        enableVibration: false,
      ),
    );
    await _plugin.show(
      1001, // fixed ID — replaces itself if shown again before dismissed
      'JanMat — Submission Synced ✅',
      count == 1
          ? 'Your offline submission has been sent successfully.'
          : '$count offline submissions have been sent successfully.',
      details,
    );
  }
}
