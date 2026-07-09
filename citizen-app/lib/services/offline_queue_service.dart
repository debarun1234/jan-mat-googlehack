/// Offline Queue Service
///
/// Saves failed submissions to SharedPreferences when the device has no
/// network connectivity, then replays them automatically the next time a
/// submission attempt succeeds (or when the home screen loads).
///
/// Each item stores the submission type, payload (text / file path), GPS
/// coords, and the user's JWT token so the retry is fully authenticated.
/// Audio/image files are copied from the OS temp dir to the app documents
/// dir so they survive across app restarts before the upload goes through.

library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api_service.dart';
import 'notification_service.dart';
import 'package:dio/dio.dart';

const _kPrefKey = 'janmat_offline_queue_v1';
const _uuid = Uuid();

// ── Dio error-type helper ─────────────────────────────────────────────────
// Call this from submission screens to decide whether to queue or just
// show an error. We only queue on genuine network failures, not 4xx/5xx.


bool isNetworkError(DioException e) {
  return e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError;
}

// ── Model ─────────────────────────────────────────────────────────────────

class QueuedSubmission {
  final String id;

  /// 'text' | 'audio' | 'image'
  final String type;

  final Map<String, dynamic> payload;
  final DateTime queuedAt;

  const QueuedSubmission({
    required this.id,
    required this.type,
    required this.payload,
    required this.queuedAt,
  });

  factory QueuedSubmission.fromJson(Map<String, dynamic> m) =>
      QueuedSubmission(
        id: m['id'] as String,
        type: m['type'] as String,
        payload: Map<String, dynamic>.from(m['payload'] as Map),
        queuedAt: DateTime.parse(m['queued_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'queued_at': queuedAt.toIso8601String(),
      };
}

// ── Service ───────────────────────────────────────────────────────────────

class OfflineQueueService {
  // Singleton
  static final OfflineQueueService _instance = OfflineQueueService._();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._();

  /// Reactive count — listen to this instead of polling pendingCount.
  /// Updated immediately whenever items are enqueued or sent.
  static final ValueNotifier<int> pendingNotifier = ValueNotifier(0);

  /// Call once in main() after WidgetsFlutterBinding.ensureInitialized()
  /// to pre-load the count from storage into the notifier.
  Future<void> init() async {
    final q = await getQueue();
    pendingNotifier.value = q.length;
  }

  // ── Queue persistence ─────────────────────────────────────────────────

  Future<List<QueuedSubmission>> getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => QueuedSubmission.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveQueue(List<QueuedSubmission> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kPrefKey, jsonEncode(queue.map((e) => e.toJson()).toList()));
    pendingNotifier.value = queue.length; // keep notifier in sync
  }

  Future<int> get pendingCount async => (await getQueue()).length;

  // ── Enqueue ───────────────────────────────────────────────────────────

  Future<void> enqueueText({
    required String text,
    required double lat,
    required double lng,
    String? token,
  }) async {
    final queue = await getQueue();
    queue.add(QueuedSubmission(
      id: _uuid.v4(),
      type: 'text',
      payload: {'text': text, 'lat': lat, 'lng': lng, 'token': token},
      queuedAt: DateTime.now(),
    ));
    await _saveQueue(queue);
  }

  Future<void> enqueueAudio({
    required String filePath,
    required double lat,
    required double lng,
    String? token,
  }) async {
    final dest = await _persistFile(filePath, 'audio');
    final queue = await getQueue();
    queue.add(QueuedSubmission(
      id: _uuid.v4(),
      type: 'audio',
      payload: {'path': dest, 'lat': lat, 'lng': lng, 'token': token},
      queuedAt: DateTime.now(),
    ));
    await _saveQueue(queue);
  }

  Future<void> enqueueImage({
    required String filePath,
    String? caption,
    required double lat,
    required double lng,
    String? token,
  }) async {
    final dest = await _persistFile(filePath, 'images');
    final queue = await getQueue();
    queue.add(QueuedSubmission(
      id: _uuid.v4(),
      type: 'image',
      payload: {
        'path': dest,
        'caption': caption,
        'lat': lat,
        'lng': lng,
        'token': token,
      },
      queuedAt: DateTime.now(),
    ));
    await _saveQueue(queue);
  }

  // ── Persist media file outside of OS temp dir ─────────────────────────

  Future<String> _persistFile(String sourcePath, String subfolder) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final destDir =
        Directory('${docsDir.path}/janmat_offline_queue/$subfolder');
    await destDir.create(recursive: true);
    final filename =
        '${_uuid.v4()}_${sourcePath.split('/').last}';
    final dest = '${destDir.path}/$filename';
    await File(sourcePath).copy(dest);
    return dest;
  }

  // ── Retry ─────────────────────────────────────────────────────────────

  /// Attempt to flush all queued submissions in order.
  /// Returns the number of items successfully uploaded.
  /// Items that still fail remain in the queue for the next attempt.
  Future<int> retryPending({ApiService? api}) async {
    final queue = await getQueue();
    if (queue.isEmpty) return 0;

    final svc = api ?? ApiService();
    final remaining = <QueuedSubmission>[];
    int sent = 0;

    for (final item in queue) {
      try {
        switch (item.type) {
          case 'text':
            await svc.submitText(
              item.payload['text'] as String,
              token: item.payload['token'] as String?,
              lat: (item.payload['lat'] as num?)?.toDouble(),
              lng: (item.payload['lng'] as num?)?.toDouble(),
            );

          case 'audio':
            final path = item.payload['path'] as String;
            if (!File(path).existsSync()) {
              // Original file is gone — silently drop to prevent permanent block
              continue;
            }
            await svc.submitAudio(
              path,
              token: item.payload['token'] as String?,
              lat: (item.payload['lat'] as num?)?.toDouble(),
              lng: (item.payload['lng'] as num?)?.toDouble(),
            );
            try {
              File(path).deleteSync();
            } catch (_) {}

          case 'image':
            final path = item.payload['path'] as String;
            if (!File(path).existsSync()) {
              continue;
            }
            await svc.submitImage(
              File(path),
              description: item.payload['caption'] as String?,
              token: item.payload['token'] as String?,
              lat: (item.payload['lat'] as num?)?.toDouble(),
              lng: (item.payload['lng'] as num?)?.toDouble(),
            );
            try {
              File(path).deleteSync();
            } catch (_) {}
        }
        sent++;
      } catch (_) {
        // Still no connectivity — keep this item for the next attempt
        remaining.add(item);
      }
    }

    await _saveQueue(remaining);

    // Fire a phone notification for every automatic background sync
    if (sent > 0) {
      await NotificationService().showSyncSuccess(sent);
    }

    return sent;
  }

  /// Manually remove one item (e.g. user dismisses it from queue view).
  Future<void> remove(String id) async {
    final queue = await getQueue();
    queue.removeWhere((e) => e.id == id);
    await _saveQueue(queue);
  }
}
