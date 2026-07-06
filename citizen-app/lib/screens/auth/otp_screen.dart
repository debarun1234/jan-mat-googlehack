import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import '../../theme.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _otp = '';
  bool _loading = false;
  String? _error;
  String? _info;
  bool _hasArgs = false;
  String? _phone;
  String? _verificationId;
  int? _resendToken;

  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasArgs) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _phone          = args?['phone'] as String?;
      _verificationId = args?['verificationId'] as String?;
      _resendToken    = args?['resendToken'] as int?;
      final autoVerified = args?['autoVerified'] == true;
      _hasArgs = true;
      _startCooldown(30);
      if (autoVerified) {
        WidgetsBinding.instance.addPostFrameCallback((_) =>
          _handlePostAuth(args?['uid'], args?['idToken'], _phone));
      }
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) { _cooldown = 0; t.cancel(); }
      });
    });
  }

  Future<void> _resend() async {
    if (_phone == null || _cooldown > 0) return;
    setState(() { _loading = true; _error = null; _info = null; });

    await AuthService().verifyPhone(
      phoneNumber: _phone!,
      resendToken: _resendToken,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _verificationId = verificationId;
          _resendToken = resendToken;
          _otp = '';
          _info = 'OTP resent to $_phone';
        });
        _startCooldown(30);
      },
      onError: (e) {
        if (!mounted) return;
        setState(() { _loading = false; _error = e.message ?? 'Failed to resend OTP'; });
      },
      onAutoVerified: (cred) async {
        if (!mounted) return;
        try {
          final uc  = await AuthService().signInWithCredential(cred);
          final tok = await uc.user?.getIdToken();
          await _handlePostAuth(uc.user?.uid, tok, uc.user?.phoneNumber ?? _phone);
        } catch (e) {
          if (mounted) setState(() { _loading = false; _error = 'Auto-verify failed — enter OTP manually.'; });
        }
      },
    );
  }

  Future<void> _verify() async {
    if (_otp.length != 6) return;
    setState(() { _loading = true; _error = null; _info = null; });

    // Firebase may have auto-verified during resend — currentUser is already set
    final currentUser = FirebaseAuth.instance.currentUser;

    if (_verificationId == null) {
      if (currentUser != null) {
        // Already signed in via auto-verify; just exchange with backend
        final tok = await currentUser.getIdToken(true);
        await _handlePostAuth(currentUser.uid, tok, currentUser.phoneNumber ?? _phone ?? '');
        return;
      }
      setState(() { _loading = false; _error = 'Session expired — tap Resend OTP.'; });
      return;
    }

    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otp,
      );
      final uc  = await FirebaseAuth.instance.signInWithCredential(cred);
      final uid = uc.user?.uid ?? '';
      final tok = await uc.user?.getIdToken() ?? '';
      final ph  = uc.user?.phoneNumber ?? _phone ?? '';
      await _handlePostAuth(uid, tok, ph);
    } on FirebaseAuthException catch (e) {
      // These codes mean Firebase already consumed the credential (auto-verify raced us)
      if ((e.code == 'session-expired' || e.code == 'credential-already-in-use') &&
          currentUser != null) {
        final tok = await currentUser.getIdToken(true);
        await _handlePostAuth(currentUser.uid, tok, currentUser.phoneNumber ?? _phone ?? '');
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == 'invalid-verification-code'
          ? 'Incorrect OTP. Please try again.'
          : '[${e.code}] ${e.message ?? 'Verification failed'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _handlePostAuth(dynamic uid, dynamic idToken, dynamic phone) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final svc  = UserService();
      final data = await svc.authenticate(
        firebaseUid: uid?.toString() ?? '',
        phoneNumber: phone?.toString() ?? '',
        idToken: idToken?.toString(),
      );
      if (!mounted) return;
      final profile = data['profile_complete'] == true
          ? await svc.getProfile(data['access_token'])
          : null;
      if (profile != null) context.read<AppState>().setProfile(profile);
      context.read<AppState>().setToken(data['access_token']);

      if (data['profile_complete'] == true) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/profile',
            arguments: {'phone': phone, 'token': data['access_token']});
      }
    } catch (e) {
      debugPrint('[JanMat OTP] _handlePostAuth error: $e');
      if (mounted) setState(() { _loading = false; _error = 'Backend error: ${e.toString()}'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      appBar: AppBar(
        backgroundColor: JanMatTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Verify OTP'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 24),
            const Text('Enter OTP',
                style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Sent to ${_phone ?? 'your number'}',
                style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 40),

            PinCodeTextField(
              appContext: context,
              length: 6,
              animationType: AnimationType.fade,
              keyboardType: TextInputType.number,
              textStyle: const TextStyle(
                  color: JanMatTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w600),
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(12),
                fieldHeight: 56,
                fieldWidth: 46,
                activeFillColor: JanMatTheme.card,
                inactiveFillColor: JanMatTheme.card,
                selectedFillColor: JanMatTheme.cardHover,
                activeColor: JanMatTheme.primary,
                inactiveColor: JanMatTheme.border,
                selectedColor: JanMatTheme.primary,
              ),
              enableActiveFill: true,
              onChanged: (val) => setState(() => _otp = val),
              onCompleted: (_) => _verify(),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!,
                    style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 13))),
              ]),
            ],

            if (_info != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.check_circle_outline_rounded, color: JanMatTheme.accent, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(_info!,
                    style: const TextStyle(color: JanMatTheme.accent, fontSize: 13))),
              ]),
            ],

            const SizedBox(height: 28),
            JMButton(
              label: 'Verify',
              loading: _loading,
              icon: Icons.check_rounded,
              onPressed: (_loading || _otp.length < 6) ? null : _verify,
            ),

            const SizedBox(height: 20),
            Center(
              child: _cooldown > 0
                  ? Text('Resend OTP in ${_cooldown}s',
                      style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 14))
                  : TextButton(
                      onPressed: _loading ? null : _resend,
                      child: const Text('Resend OTP',
                          style: TextStyle(color: JanMatTheme.primary, fontWeight: FontWeight.w600)),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
