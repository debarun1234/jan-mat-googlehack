import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    final currentUser = FirebaseAuth.instance.currentUser;

    if (_verificationId == null) {
      if (currentUser != null) {
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

            _OtpInputWidget(
              onChanged: (val) => setState(() => _otp = val),
              onCompleted: () => _verify(),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 13))),
              ]),
            ],
            if (_info != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.check_circle_outline_rounded, color: JanMatTheme.accent, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(_info!, style: const TextStyle(color: JanMatTheme.accent, fontSize: 13))),
              ]),
            ],

            const SizedBox(height: 32),

            // Verify button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_loading || _otp.length != 6) ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: JanMatTheme.primary,
                  disabledBackgroundColor: JanMatTheme.primary.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify OTP',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),

            const SizedBox(height: 20),

            // Resend
            Center(
              child: TextButton(
                onPressed: _cooldown > 0 ? null : _resend,
                child: Text(
                  _cooldown > 0 ? 'Resend OTP in ${_cooldown}s' : 'Resend OTP',
                  style: TextStyle(
                    color: _cooldown > 0 ? JanMatTheme.textMuted : JanMatTheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Custom OTP input — 6 boxes, no external package ───────────────────

class _OtpInputWidget extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final VoidCallback onCompleted;

  const _OtpInputWidget({required this.onChanged, required this.onCompleted});

  @override
  State<_OtpInputWidget> createState() => _OtpInputWidgetState();
}

class _OtpInputWidgetState extends State<_OtpInputWidget> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: SizedBox(
        height: 60,
        child: Stack(
          children: [
            // Hidden text field that captures keyboard input
            Opacity(
              opacity: 0,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                autofocus: true,
                decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                onChanged: (val) {
                  setState(() {});
                  widget.onChanged(val);
                  if (val.length == 6) widget.onCompleted();
                },
              ),
            ),
            // Digit boxes overlay
            Positioned.fill(
              child: ListenableBuilder(
                listenable: _ctrl,
                builder: (_, __) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (i) {
                    final ch = _ctrl.text.length > i ? _ctrl.text[i] : '';
                    final cursorHere = _focus.hasFocus &&
                        (_ctrl.text.length == i || (i == 5 && _ctrl.text.length >= 6));
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 46,
                      height: 56,
                      decoration: BoxDecoration(
                        color: JanMatTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cursorHere ? JanMatTheme.primary : JanMatTheme.border,
                          width: cursorHere ? 2 : 1.2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        ch,
                        style: const TextStyle(
                          color: JanMatTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
