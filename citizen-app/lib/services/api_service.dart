import 'dart:io';
import 'package:dio/dio.dart';

const _kBaseUrl = 'https://janmat-backend-w2w3osjaua-el.a.run.app';

class ApiService {
  late final Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: _kBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (e, handler) {
        // Log and pass through
        handler.next(e);
      },
    ));
  }

  // ── Auth header ────────────────────────────────────────────────────
  Options _auth(String? token) => Options(
    headers: token != null ? {'Authorization': 'Bearer $token'} : {},
  );

  // ── Health check ───────────────────────────────────────────────────
  Future<bool> checkHealth() async {
    try {
      final r = await _dio.get('/health');
      return r.data['status'] == 'healthy';
    } catch (_) { return false; }
  }

  // ── Text submission ────────────────────────────────────────────────
  Future<Map<String, dynamic>> submitText(String text, {String? token, double? lat, double? lng}) async {
    final r = await _dio.post(
      '/intake/text',
      data: {
        'text': text,
        if (lat != null) 'latitude': lat,
        if (lng != null) 'longitude': lng,
      },
      options: _auth(token),
    );
    return Map<String, dynamic>.from(r.data);
  }

  // ── Audio submission ───────────────────────────────────────────────
  // Backend field: audio_file (not audio). Content-Type must be audio/mp4 for .m4a files.
  Future<Map<String, dynamic>> submitAudio(String filePath, {String? token, double? lat, double? lng}) async {
    final form = FormData.fromMap({
      'audio_file': await MultipartFile.fromFile(
        filePath,
        filename: 'audio.m4a',
        contentType: DioMediaType('audio', 'mp4'),
      ),
      if (lat != null) 'latitude': lat.toString(),
      if (lng != null) 'longitude': lng.toString(),
    });
    final r = await _dio.post('/intake/audio', data: form, options: _auth(token));
    return Map<String, dynamic>.from(r.data);
  }

  // ── Image submission ───────────────────────────────────────────────
  // Backend field: image_file (not image), caption (not description).
  Future<Map<String, dynamic>> submitImage(File file, {String? description, String? token, double? lat, double? lng}) async {
    final form = FormData.fromMap({
      'image_file': await MultipartFile.fromFile(
        file.path,
        filename: 'photo.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
      if (description != null && description.isNotEmpty) 'caption': description,
      if (lat != null) 'latitude': lat.toString(),
      if (lng != null) 'longitude': lng.toString(),
    });
    final r = await _dio.post('/intake/image', data: form, options: _auth(token));
    return Map<String, dynamic>.from(r.data);
  }

  // ── Submission history ─────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getHistory(String token, {int limit = 50}) async {
    try {
      final r = await _dio.get(
        '/users/submissions',
        queryParameters: {'limit': limit},
        options: _auth(token),
      );
      final list = r.data['submissions'] as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) { return []; }
  }
}
