import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wraps Firebase phone OTP authentication.
/// Flow:
///   1. verifyPhone()   → sends OTP via Firebase
///   2. verifyOtp()     → confirms OTP, returns Firebase ID token
///   3. getIdToken()    → returns current user's ID token for backend
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _verificationId;

  bool get isLoggedIn => _auth.currentUser != null;
  User? get currentUser => _auth.currentUser;

  /// Step 1: Start phone verification — sends OTP to the given number
  Future<void> verifyPhone({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException e) onError,
    required void Function(PhoneAuthCredential credential) onAutoVerified,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: onAutoVerified,
      verificationFailed: onError,
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Step 2: Verify the OTP entered by the user
  Future<UserCredential> verifyOtp(String otp) async {
    final cred = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );
    return _auth.signInWithCredential(cred);
  }

  /// Step 2b: Sign in with auto-verified credential (Android auto-read)
  Future<UserCredential> signInWithCredential(PhoneAuthCredential cred) {
    return _auth.signInWithCredential(cred);
  }

  /// Get Firebase ID token (send to backend for exchange)
  Future<String?> getIdToken() async {
    return _auth.currentUser?.getIdToken();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('janmat_token');
    await prefs.remove('janmat_user_id');
  }

  String? get phoneNumber => _auth.currentUser?.phoneNumber;
  String? get uid => _auth.currentUser?.uid;
}
