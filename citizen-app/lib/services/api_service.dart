import 'dart:io';
import 'package:dio/dio.dart';

class SubmissionResult {
  final String submissionId;
  final String status;
  final String? category;
  final int? urgencyRating;
  final String? summaryEn;
  final String message;

  SubmissionResult({
    required this.submissionId,
    required this.status,
    this.category,
    this.urgencyRating,
    this.summaryEn,
    required this.message,
  });

  factory SubmissionResult.fromJson(Map<String, dynamic> json) {
    return SubmissionResult(
      submissionId: json['submission_id'] ?? '',
      status: json['status'] ?? 'processing',
      category: json['category'],
      urgencyRating: json['urgency_rating'],
      summaryEn: json['summary_en'],
      message: json['message'] ?? 'Submitted',
    );
  }
}

class ApiService {
  final String baseUrl;
  late final Dio _dio;

  ApiService({required this.baseUrl}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    ));
  }

  /// Submit a text grievance
  Future<SubmissionResult> submitText({
    required String text,
    String? languageCode,
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{
      'text': text,
      if (languageCode != null) 'language_code': languageCode,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
    final resp = await _dio.post('/intake/text', data: body);
    return SubmissionResult.fromJson(resp.data);
  }

  /// Submit an audio voice note
  Future<SubmissionResult> submitAudio({
    required File audioFile,
    String languageCode = 'auto',
    double? latitude,
    double? longitude,
  }) async {
    final formData = FormData.fromMap({
      'audio_file': await MultipartFile.fromFile(
        audioFile.path,
        filename: 'voice_note.webm',
        contentType: DioMediaType('audio', 'webm'),
      ),
      'language_code': languageCode,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    });
    final resp = await _dio.post('/intake/audio', data: formData);
    return SubmissionResult.fromJson(resp.data);
  }

  /// Submit a photo
  Future<SubmissionResult> submitImage({
    required File imageFile,
    double? latitude,
    double? longitude,
    String? caption,
  }) async {
    final ext = imageFile.path.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
    final formData = FormData.fromMap({
      'image_file': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'complaint.$ext',
        contentType: DioMediaType.parse(mimeType),
      ),
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
      if (caption != null && caption.isNotEmpty) 'caption': caption,
    });
    final resp = await _dio.post('/intake/image', data: formData);
    return SubmissionResult.fromJson(resp.data);
  }

  Future<bool> checkHealth() async {
    try {
      final resp = await _dio.get('/health');
      return resp.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }
}
