import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../theme.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _townCtrl  = TextEditingController();
  final _cityCtrl  = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pinCtrl   = TextEditingController();

  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AppState>().profile;
    if (profile != null) {
      _nameCtrl.text  = profile.fullName ?? '';
      _townCtrl.text  = profile.town ?? '';
      _cityCtrl.text  = profile.city ?? '';
      _stateCtrl.text = profile.state ?? '';
      _pinCtrl.text   = profile.pinCode ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _townCtrl, _cityCtrl, _stateCtrl, _pinCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    final app = context.read<AppState>();
    try {
      final svc = UserService();
      final updated = await svc.saveProfile(
        fullName:    _nameCtrl.text.trim(),
        town:        _townCtrl.text.trim(),
        city:        _cityCtrl.text.trim(),
        state:       _stateCtrl.text.trim(),
        pinCode:     _pinCtrl.text.trim(),
        phoneNumber: app.profile?.phoneNumber ?? '',
        token:       app.token,
      );
      if (!mounted) return;
      app.setProfile(updated);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Color(0xFF00D4AA),
        ),
      );
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Failed to update profile. Please try again.'; });
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: JanMatTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: JanMatTheme.errorColor, size: 22),
          SizedBox(width: 10),
          Text('Delete Account?', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 17)),
        ]),
        content: const Text(
          'This will permanently delete your account and all submissions you have made. '
          'This action cannot be undone.',
          style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: JanMatTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: JanMatTheme.errorColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Forever', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteAccount();
  }

  Future<void> _deleteAccount() async {
    setState(() { _deleting = true; _error = null; });
    final app = context.read<AppState>();
    try {
      final svc = UserService();
      await svc.deleteAccount(app.token!);
      await AuthService().signOut();
      if (!mounted) return;
      app.logout();
      Navigator.pushNamedAndRemoveUntil(context, '/phone', (_) => false);
    } catch (_) {
      if (mounted) setState(() { _deleting = false; _error = 'Failed to delete account. Please try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile;
    final busy = _saving || _deleting;

    return Scaffold(
      backgroundColor: JanMatTheme.background,
      appBar: AppBar(
        backgroundColor: JanMatTheme.background,
        title: const Text('Edit Profile'),
        centerTitle: true,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(color: JanMatTheme.primary, strokeWidth: 2))),
            )
          else
            TextButton(
              onPressed: busy ? null : _save,
              child: const Text('Save', style: TextStyle(color: JanMatTheme.primary, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── Avatar ──────────────────────────────────────────────
              Center(
                child: Stack(children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: JanMatTheme.primary.withValues(alpha: 0.15),
                    child: Text(
                      (profile?.name.isNotEmpty == true) ? profile!.name[0].toUpperCase() : 'C',
                      style: const TextStyle(color: JanMatTheme.primary, fontSize: 32, fontWeight: FontWeight.w800),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              if (profile?.phoneNumber != null)
                Center(child: Text(profile!.phoneNumber,
                    style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 13))),

              const SizedBox(height: 24),

              // ── Form fields ─────────────────────────────────────────
              _Label('Full Name *'),
              _Field(ctrl: _nameCtrl, hint: 'e.g. Priya Sharma',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),

              _Label('Town / Village'),
              _Field(ctrl: _townCtrl, hint: 'e.g. Yelahanka'),

              _Label('City *'),
              _Field(ctrl: _cityCtrl, hint: 'e.g. Bangalore',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'City is required' : null),

              _Label('State *'),
              _Field(ctrl: _stateCtrl, hint: 'e.g. Karnataka',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'State is required' : null),

              _Label('Pin Code *'),
              _Field(
                ctrl: _pinCtrl, hint: '560001',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                validator: (v) => (v == null || v.length != 6) ? '6-digit pin code required' : null,
              ),

              if (_error != null) ...[
                const SizedBox(height: 4),
                _ErrorBox(error: _error!),
              ],

              const SizedBox(height: 28),

              // ── Save button ─────────────────────────────────────────
              JMButton(
                label: 'Save Changes',
                loading: _saving,
                icon: Icons.check_rounded,
                gradient: JanMatTheme.accentGradient,
                onPressed: busy ? null : _save,
              ),

              const SizedBox(height: 36),

              // ── Danger zone ─────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: JanMatTheme.errorColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JanMatTheme.errorColor.withValues(alpha: 0.25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Icons.dangerous_rounded, color: JanMatTheme.errorColor, size: 16),
                    SizedBox(width: 8),
                    Text('Danger Zone', style: TextStyle(color: JanMatTheme.errorColor, fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                    'Deleting your account is permanent and cannot be undone. '
                    'All your submissions will be removed.',
                    style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _confirmDelete,
                      icon: _deleting
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(color: JanMatTheme.errorColor, strokeWidth: 2))
                          : const Icon(Icons.delete_forever_rounded, color: JanMatTheme.errorColor, size: 18),
                      label: Text(
                        _deleting ? 'Deleting...' : 'Delete My Account',
                        style: const TextStyle(color: JanMatTheme.errorColor, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: JanMatTheme.errorColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
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
      decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: JanMatTheme.textMuted)),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: JanMatTheme.errorColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: JanMatTheme.errorColor.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(error, style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 12))),
    ]),
  );
}
