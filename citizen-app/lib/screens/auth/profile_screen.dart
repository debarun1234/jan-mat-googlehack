import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/user_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _townCtrl    = TextEditingController();
  final _cityCtrl    = TextEditingController();
  final _stateCtrl   = TextEditingController();
  final _pinCtrl     = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _phone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _phone = args?['phone'] as String?;
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
      final svc = context.read<UserService>();
      await svc.saveProfile(
        fullName: _nameCtrl.text.trim(),
        town:     _townCtrl.text.trim(),
        city:     _cityCtrl.text.trim(),
        state:    _stateCtrl.text.trim(),
        pinCode:  _pinCtrl.text.trim(),
        phoneNumber: _phone ?? '',
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      setState(() { _loading = false; _error = 'Failed to save profile. Try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1B2D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Complete Profile', style: TextStyle(color: Colors.white)),
        leading: const SizedBox.shrink(),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your details are shared with your constituency\'s MP to understand local needs.',
                  style: TextStyle(color: Color(0xFF8899AA), fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 24),

                // Phone display (read-only)
                if (_phone != null) ...[
                  _label('Phone Number'),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2C42),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2A4060)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.phone, color: Color(0xFF4CAF50), size: 18),
                      const SizedBox(width: 10),
                      Text(_phone!, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                      const Spacer(),
                      const Icon(Icons.lock_outline, color: Color(0xFF445566), size: 16),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                _label('Full Name *'),
                _field(_nameCtrl, 'e.g. Priya Sharma', validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null),

                _label('Town / Village'),
                _field(_townCtrl, 'e.g. Yelahanka'),

                _label('City *'),
                _field(_cityCtrl, 'e.g. Bangalore', validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'City is required' : null),

                _label('State *'),
                _field(_stateCtrl, 'e.g. Karnataka', validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'State is required' : null),

                _label('Pin Code *'),
                _field(_pinCtrl, '560001',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  validator: (v) {
                    if (v == null || v.length != 6) return '6-digit pin code required';
                    return null;
                  }),

                const SizedBox(height: 8),
                // Transparency note
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D2137),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E4060)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Row(children: [
                        Icon(Icons.visibility_outlined, color: Color(0xFF2196F3), size: 16),
                        SizedBox(width: 8),
                        Text('Transparency & Control', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                      SizedBox(height: 8),
                      Text(
                        '• Your name and location help your MP prioritize development projects.\n'
                        '• You can view the live heatmap to see where concerns are highest.\n'
                        '• Your data is never sold or shared outside your constituency.\n'
                        '• You can delete your account anytime from Settings.',
                        style: TextStyle(color: Color(0xFF8899AA), fontSize: 12, height: 1.6),
                      ),
                    ],
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Color(0xFFFF5252), fontSize: 13)),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Save & Continue', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(color: Color(0xFFAABBCC), fontSize: 13, fontWeight: FontWeight.w500)),
  );

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF445566)),
        filled: true,
        fillColor: const Color(0xFF1A2C42),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A4060)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2A4060)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2196F3), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF5252)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
  );
}
