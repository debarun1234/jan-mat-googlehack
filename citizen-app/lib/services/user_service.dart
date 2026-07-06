import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBaseUrl = 'https://janmat-backend-w2w3osjaua-el.a.run.app';

class UserProfile {
  final String userId;
  final String phoneNumber;
  final String? fullName;
  final String? town;
  final String? city;
  final String? state;
  final String? pinCode;
  final String? constituencyId;
  final bool profileComplete;
  final int submissionCount;

  const UserProfile({
    required this.userId,
    required this.phoneNumber,
    this.fullName,
    this.town,
    this.city,
    this.state,
    this.pinCode,
    this.constituencyId,
    this.profileComplete = false,
    this.submissionCount = 0,
  });

  String get name => fullName ?? 'Citizen';
  String get constituency => constituencyId ?? city ?? 'Your Area';

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    userId:          j['user_id'] ?? '',
    phoneNumber:     j['phone_number'] ?? '',
    fullName:        j['full_name'],
    town:            j['town'],
    city:            j['city'],
    state:           j['state'],
    pinCode:         j['pin_code'],
    constituencyId:  j['constituency_id'],
    profileComplete: j['profile_complete'] ?? false,
    submissionCount: j['submission_count'] ?? 0,
  );
}

class HotspotPoint {
  final double lat;
  final double lng;
  final int weight;
  final String category;
  final double avgUrgency;

  const HotspotPoint({
    required this.lat, required this.lng, required this.weight,
    required this.category, required this.avgUrgency,
  });

  factory HotspotPoint.fromJson(Map<String, dynamic> j) => HotspotPoint(
    lat:        (j['lat'] as num).toDouble(),
    lng:        (j['lng'] as num).toDouble(),
    weight:     (j['weight'] as num).toInt(),
    category:   j['category'] ?? 'Other',
    avgUrgency: (j['avg_urgency'] as num?)?.toDouble() ?? 3.0,
  );
}

class UserService {
  late final Dio _dio;

  UserService() {
    _dio = Dio(BaseOptions(
      baseUrl: _kBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  Options _auth(String? token) => Options(
    headers: token != null ? {'Authorization': 'Bearer $token'} : {},
  );

  // ── Auth ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> authenticate({
    required String firebaseUid,
    required String phoneNumber,
    String? idToken,
  }) async {
    final resp = await _dio.post('/users/auth', data: {
      'firebase_uid': firebaseUid,
      'phone_number': phoneNumber,
      if (idToken != null) 'id_token': idToken,
    });
    final token = resp.data['access_token'] as String?;
    if (token != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('janmat_token', token);
      await prefs.setString('janmat_user_id', resp.data['user_id'] ?? '');
    }
    return Map<String, dynamic>.from(resp.data);
  }

  // ── Profile ──────────────────────────────────────────────────────────
  Future<UserProfile> saveProfile({
    required String fullName,
    required String city,
    required String state,
    required String pinCode,
    required String phoneNumber,
    String? token,
    String? town,
  }) async {
    final resp = await _dio.post(
      '/users/profile',
      data: {
        'full_name': fullName, 'city': city, 'state': state,
        'pin_code': pinCode, 'phone_number': phoneNumber,
        if (town != null && town.isNotEmpty) 'town': town,
      },
      options: _auth(token),
    );
    return UserProfile.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<UserProfile?> getProfile(String token) async {
    try {
      final resp = await _dio.get('/users/profile', options: _auth(token));
      return UserProfile.fromJson(Map<String, dynamic>.from(resp.data));
    } catch (_) { return null; }
  }

  // ── Stats ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getStats(String token) async {
    try {
      final resp = await _dio.get('/users/stats', options: _auth(token));
      return Map<String, dynamic>.from(resp.data);
    } catch (_) {
      return {'total_submissions': 0, 'processed': 0, 'pending': 0};
    }
  }

  // ── Heatmap ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getHeatmap(String pinCode, {String? category, String? token}) async {
    final resp = await _dio.get(
      '/users/heatmap/$pinCode',
      queryParameters: {if (category != null) 'category': category},
      options: _auth(token),
    );
    return Map<String, dynamic>.from(resp.data);
  }

  // ── Delete account ───────────────────────────────────────────────────
  Future<void> deleteAccount(String token) async {
    await _dio.delete('/users/account', options: _auth(token));
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ── Session ───────────────────────────────────────────────────────────
  Future<bool> hasStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('janmat_token');
  }
}
