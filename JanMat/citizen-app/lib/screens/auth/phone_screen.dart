import 'package:flutter/material.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phoneCtrl = TextEditingController();
  String _countryCode = '+91';
  bool _loading = false;
  String? _error;

  @override
  void dispose() { _phoneCtrl.dispose(); super.dispose(); }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || phone.length < 7) {
      setState(() => _error = 'Enter a valid phone number');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final fullNumber = '$_countryCode$phone';
    final auth = context.read<AuthService>();

    await auth.verifyPhone(
      phoneNumber: fullNumber,
      onCodeSent: (verificationId, _) {
        if (!mounted) return;
        setState(() => _loading = false);
        Navigator.pushNamed(context, '/otp', arguments: {
          'phone': fullNumber,
          'verificationId': verificationId,
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = e.message ?? 'Failed to send OTP. Try again.';
        });
      },
      onAutoVerified: (cred) async {
        if (!mounted) return;
        try {
          final uc = await auth.signInWithCredential(cred);
          final idToken = await uc.user?.getIdToken();
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/otp-success', arguments: {
            'phone': fullNumber,
            'uid': uc.user?.uid,
            'idToken': idToken,
          });
        } catch (_) {}
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1B2D),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo / branding
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF2196F3)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.how_to_vote, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Text('JanMat', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 48),
              const Text('Enter your\nphone number',
                style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700, height: 1.25)),
              const SizedBox(height: 8),
              const Text('We\'ll send you a one-time password',
                style: TextStyle(color: Color(0xFF8899AA), fontSize: 15)),
              const SizedBox(height: 40),

              // Phone input card
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2C42),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2A4060)),
                ),
                child: Row(children: [
                  CountryCodePicker(
                    onChanged: (code) => setState(() => _countryCode = code.dialCode ?? '+91'),
                    initialSelection: 'IN',
                    favorite: const ['+91', 'IN'],
                    showCountryOnly: false,
                    showOnlyCountryWhenClosed: false,
                    alignLeft: false,
                    textStyle: const TextStyle(color: Colors.white, fontSize: 16),
                    dialogTextStyle: const TextStyle(color: Colors.black87),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  Container(width: 1, height: 40, color: const Color(0xFF2A4060)),
                  Expanded(
                    child: TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        hintText: '9876543210',
                        hintStyle: TextStyle(color: Color(0xFF445566)),
                      ),
                    ),
                  ),
                ]),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13))),
                ]),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('Send OTP', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),

              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2C42),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E4D2B)),
                ),
                child: Row(children: const [
                  Icon(Icons.shield_outlined, color: Color(0xFF4CAF50), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your number is only used for login. It helps your MP understand your area\'s needs.',
                      style: TextStyle(color: Color(0xFF8899AA), fontSize: 13, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
