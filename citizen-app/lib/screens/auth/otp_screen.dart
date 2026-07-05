import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
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
  bool _hasArgs = false;
  String? _phone;
  String? _verificationId;
  bool _autoVerified = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasArgs) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _phone          = args?['phone'] as String?;
      _verificationId = args?['verificationId'] as String?;
      _autoVerified   = args?['autoVerified'] == true;
      _hasArgs = true;
      if (_autoVerified) _handlePostAuth(args?['uid'], args?['idToken'], _phone);
    }
  }

  Future<void> _verify() async {
    if (_otp.length != 6) return;
    setState(() { _loading = true; _error = null; });
    try {
      final auth = AuthService();
      final uc   = await auth.verifyOtp(_otp);
      final uid  = uc.user?.uid ?? '';
      final tok  = await uc.user?.getIdToken() ?? '';
      final ph   = uc.user?.phoneNumber ?? _phone ?? '';
      await _handlePostAuth(uid, tok, ph);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('invalid-verification-code')
          ? 'Incorrect OTP. Please try again.'
          : 'Verification failed. Try again.';
      });
    }
  }

  Future<void> _handlePostAuth(dynamic uid, dynamic idToken, dynamic phone) async {
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
        Navigator.pushReplacementNamed(context, '/profile', arguments: {'phone': phone, 'token': data['access_token']});
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Authentication failed. Please retry.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      appBar: AppBar(
        backgroundColor: JanMatTheme.background,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('Verify OTP'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 24),
            const Text('Enter OTP', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Sent to ${_phone ?? 'your number'}', style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 40),

            PinCodeTextField(
              appContext: context,
              length: 6,
              animationType: AnimationType.fade,
              keyboardType: TextInputType.number,
              textStyle: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w600),
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
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 13))),
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
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Resend OTP', style: TextStyle(color: JanMatTheme.primary, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
