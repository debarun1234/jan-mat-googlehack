import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:country_code_picker/country_code_picker.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../theme.dart';
import '../../services/auth_service.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
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
    final auth = AuthService();

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
        setState(() { _loading = false; _error = e.message ?? 'Failed to send OTP. Try again.'; });
      },
      onAutoVerified: (cred) async {
        if (!mounted) return;
        try {
          final uc  = await auth.signInWithCredential(cred);
          final tok = await uc.user?.getIdToken();
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/otp', arguments: {
            'phone': fullNumber,
            'uid': uc.user?.uid,
            'idToken': tok,
            'autoVerified': true,
          });
        } catch (_) {}
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      body: SingleChildScrollView(
        child: Column(children: [
          _HeroPanel(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Enter your phone number', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text("We'll send you a one-time password to verify your identity.", style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 14)),
              const SizedBox(height: 28),

              // Phone input
              Container(
                decoration: BoxDecoration(
                  color: JanMatTheme.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JanMatTheme.border),
                ),
                child: Row(children: [
                  CountryCodePicker(
                    onChanged: (code) => setState(() => _countryCode = code.dialCode ?? '+91'),
                    initialSelection: 'IN',
                    favorite: const ['+91', 'IN'],
                    showCountryOnly: false,
                    showOnlyCountryWhenClosed: false,
                    alignLeft: false,
                    textStyle: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 15),
                    dialogTextStyle: const TextStyle(color: Colors.black87),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  Container(width: 1, height: 40, color: JanMatTheme.border),
                  Expanded(
                    child: TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 18),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        hintText: '9876543210',
                        hintStyle: TextStyle(color: JanMatTheme.textMuted),
                      ),
                      onSubmitted: (_) => _sendOtp(),
                    ),
                  ),
                ]),
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
              JMButton(label: 'Send OTP', loading: _loading, icon: Icons.send_rounded, onPressed: _loading ? null : _sendOtp),

              const SizedBox(height: 28),
              _PrivacyNote(),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: JanMatTheme.heroGradient,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.account_balance, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              const Text('JanMat', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 28),
            const Text('Voice of the People', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
            const SizedBox(height: 10),
            const Text('Submit concerns directly to your MP. Powered by AI to ensure your voice creates real change.', style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
          ]),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JanMatTheme.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JanMatTheme.accent.withValues(alpha: 0.2)),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_rounded, color: JanMatTheme.accent, size: 18),
        SizedBox(width: 10),
        Expanded(child: Text(
          'Your phone number is used only for secure login. JanMat does not share your personal data with any third party.',
          style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 12, height: 1.5),
        )),
      ]),
    );
  }
}
