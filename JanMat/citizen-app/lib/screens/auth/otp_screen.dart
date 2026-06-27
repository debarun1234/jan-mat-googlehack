import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/user_service.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});
  @override State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _otp = '';
  bool _loading = false;
  String? _error;
  bool _hasArgs = false;
  String? _phone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasArgs) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      _phone = args?['phone'] as String?;
      _hasArgs = true;
    }
  }

  Future<void> _verify() async {
    if (_otp.length != 6) return;
    setState(() { _loading = true; _error = null; });

    try {
      final auth = context.read<AuthService>();
      final userSvc = context.read<UserService>();

      final uc = await auth.verifyOtp(_otp);
      final uid = uc.user?.uid ?? '';
      final idToken = await uc.user?.getIdToken() ?? '';
      final phone = uc.user?.phoneNumber ?? _phone ?? '';

      // Exchange Firebase token for our JWT
      final data = await userSvc.authenticate(
        firebaseUid: uid,
        phoneNumber: phone,
        idToken: idToken,
      );

      if (!mounted) return;
      // If profile incomplete → profile screen, else → home
      if (data['profile_complete'] == true) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/profile', arguments: {'phone': phone});
      }
    } on Exception catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().contains('invalid-verification-code')
          ? 'Incorrect OTP. Please try again.'
          : 'Verification failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1B2D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text('Enter OTP',
                style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'Sent to ${_phone ?? 'your number'}',
                style: const TextStyle(color: Color(0xFF8899AA), fontSize: 15),
              ),
              const SizedBox(height: 48),

              // 6-digit pin field
              PinCodeTextField(
                appContext: context,
                length: 6,
                obscureText: false,
                animationType: AnimationType.fade,
                keyboardType: TextInputType.number,
                textStyle: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                pinTheme: PinTheme(
                  shape: PinCodeFieldShape.box,
                  borderRadius: BorderRadius.circular(12),
                  fieldHeight: 58,
                  fieldWidth: 48,
                  activeFillColor: const Color(0xFF1A2C42),
                  inactiveFillColor: const Color(0xFF1A2C42),
                  selectedFillColor: const Color(0xFF1E3A5F),
                  activeColor: const Color(0xFF2196F3),
                  inactiveColor: const Color(0xFF2A4060),
                  selectedColor: const Color(0xFF2196F3),
                ),
                enableActiveFill: true,
                onChanged: (val) => _otp = val,
                onCompleted: (_) => _verify(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 16),
                  const SizedBox(width: 6),
                  Text(_error!, style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                ]),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: (_loading || _otp.length < 6) ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    disabledBackgroundColor: const Color(0xFF1A2C42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('Verify', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),

              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Resend OTP', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
