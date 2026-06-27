import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    userId:         j['user_id'] ?? '',
    phoneNumber:    j['phone_number'] ?? '',
    fullName:       j['full_name'],
    town:           j['town'],
    city:           j['city'],
    state:          j['state'],
    pinCode:        j['pin_code'],
    constituencyId: j['constituency_id'],
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
    required this.lat,required this.lng,required this.weight,
    required this.category,required this.avgUrgency,
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
  final Dio _dio;
  String? _token;

  UserService({required String baseUrl})
    : _dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
      ));

  Future<void> _loadToken() async {
    if (_token != null) return;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('janmat_token');
  }

  Map<String, String> get _authHeaders =>
    _token != null ? {'Authorization': 'Bearer $_token'} : {};

  /// Exchange Firebase UID + ID token for our JWT
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
    _token = resp.data['access_token'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('janmat_token', _token!);
    await prefs.setString('janmat_user_id', resp.data['user_id'] ?? '');
    return resp.data;
  }

  /// Create or update user profile
  Future<UserProfile> saveProfile({
    required String fullName,
    required String city,
    required String state,
    required String pinCode,
    required String phoneNumber,
    String? town,
  }) async {
    await _loadToken();
    final resp = await _dio.post(
      '/users/profile',
      data: {
        'full_name':    fullName,
        'city':         city,
        'state':        state,
        'pin_code':     pinCode,
        'phone_number': phoneNumber,
        if (town != null && town.isNotEmpty) 'town': town,
      },
      options: Options(headers: _authHeaders),
    );
    return UserProfile.fromJson(resp.data);
  }

  /// Get own profile
  Future<UserProfile> getProfile() async {
    await _loadToken();
    final resp = await _dio.get('/users/profile',
      options: Options(headers: _authHeaders));
    return UserProfile.fromJson(resp.data);
  }

  /// Constituency heatmap data for citizen view
  Future<Map<String, dynamic>> getHeatmap(String pinCode, {String? category}) async {
    await _loadToken();
    final resp = await _dio.get(
      '/users/heatmap/$pinCode',
      queryParameters: { if (category != null) 'category': category },
      options: Options(headers: _authHeaders),
    );
    return resp.data;
  }

  /// Check if token is stored (user was previously logged in)
  Future<bool> hasStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('janmat_token');
  }
}
