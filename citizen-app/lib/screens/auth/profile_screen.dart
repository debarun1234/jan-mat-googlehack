import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import '../../theme.dart';
import '../../services/user_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _townCtrl   = TextEditingController();
  final _cityCtrl   = TextEditingController();
  final _stateCtrl  = TextEditingController();
  final _pinCtrl    = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _phone;
  String? _token;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _phone = args?['phone'] as String?;
    _token = args?['token'] as String?;
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _townCtrl, _cityCtrl, _stateCtrl, _pinCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      final svc = UserService();
      final profile = await svc.saveProfile(
        fullName:    _nameCtrl.text.trim(),
        town:        _townCtrl.text.trim(),
        city:        _cityCtrl.text.trim(),
        state:       _stateCtrl.text.trim(),
        pinCode:     _pinCtrl.text.trim(),
        phoneNumber: _phone ?? '',
        token:       _token,
      );
      if (!mounted) return;
      context.read<AppState>().setProfile(profile);
      Navigator.pushReplacementNamed(context, '/home');
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to save profile. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      appBar: AppBar(
        backgroundColor: JanMatTheme.background,
        automaticallyImplyLeading: false,
        title: const Text('Complete Your Profile'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Help your MP understand your area\'s needs by sharing your location details.',
                style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),

              if (_phone != null) ...[
                _Label('Phone Number'),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: JanMatTheme.cardBox(),
                  child: Row(children: [
                    const Icon(Icons.phone_rounded, color: JanMatTheme.accent, size: 18),
                    const SizedBox(width: 10),
                    Text(_phone!, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 15)),
                    const Spacer(),
                    const Icon(Icons.lock_outline_rounded, color: JanMatTheme.textMuted, size: 15),
                  ]),
                ),
                const SizedBox(height: 16),
              ],

              _Label('Full Name *'),
              _Field(ctrl: _nameCtrl, hint: 'e.g. Priya Sharma', validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name is required' : null),

              _Label('Town / Village'),
              _Field(ctrl: _townCtrl, hint: 'e.g. Yelahanka'),

              _Label('City *'),
              _Field(ctrl: _cityCtrl, hint: 'e.g. Bangalore', validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'City is required' : null),

              _Label('State *'),
              _Field(ctrl: _stateCtrl, hint: 'e.g. Karnataka', validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'State is required' : null),

              _Label('Pin Code *'),
              _Field(
                ctrl: _pinCtrl, hint: '560001',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                validator: (v) => (v == null || v.length != 6) ? '6-digit pin code required' : null,
              ),

              const SizedBox(height: 8),
              _TransparencyBox(),

              if (_error != null) ...[
                const SizedBox(height: 16),
                _ErrorBox(error: _error!),
              ],

              const SizedBox(height: 28),
              JMButton(
                label: 'Save & Continue',
                loading: _loading,
                icon: Icons.arrow_forward_rounded,
                gradient: JanMatTheme.accentGradient,
                onPressed: _loading ? null : _submit,
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _Field({required this.ctrl, required this.hint, this.keyboardType, this.inputFormatters, this.validator});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: JanMatTheme.textMuted),
      ),
    ),
  );
}

class _TransparencyBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JanMatTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: JanMatTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.info_outline_rounded, color: JanMatTheme.primary, size: 16),
          SizedBox(width: 8),
          Text('How this data is used', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        const Text(
          '• Your location helps group concerns by area for accurate prioritisation.\n'
          '• Data is only shared with your elected MP — never sold or published.\n'
          '• You can view the live heatmap of concerns in your constituency.',
          style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 12, height: 1.6),
        ),
      ]),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: JanMatTheme.errorColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: JanMatTheme.errorColor.withValues(alpha: 0.3))),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(error, style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 12))),
    ]),
  );
}
