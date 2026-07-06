import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../main.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';

class TextScreen extends StatefulWidget {
  const TextScreen({super.key});
  @override
  State<TextScreen> createState() => _TextScreenState();
}

class _TextScreenState extends State<TextScreen> {
  final _ctrl = TextEditingController();
  bool _submitting = false;
  String? _result;
  String? _error;
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _charCount = _ctrl.text.length));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your concern.')));
      return;
    }
    setState(() { _submitting = true; _error = null; });

    final loc = await LocationService.getLocation();
    if (!loc.hasLocation) {
      if (mounted) {
        setState(() => _submitting = false);
        await _showLocationError(context, loc);
      }
      return;
    }

    final app = context.read<AppState>();
    try {
      final svc = ApiService();
      final res = await svc.submitText(text, token: app.token, lat: loc.lat, lng: loc.lng);
      if (mounted) setState(() { _result = res['submission_id'] ?? 'submitted'; _submitting = false; });
    } on DioException catch (e) {
      final detail = (e.response?.data as Map?)?['detail']?.toString()
          ?? e.message ?? 'Submission failed';
      debugPrint('[JanMat Text] ${e.response?.statusCode}: $detail');
      if (mounted) setState(() { _error = detail; _submitting = false; });
    } catch (e) {
      debugPrint('[JanMat Text] $e');
      if (mounted) setState(() { _error = e.toString(); _submitting = false; });
    }
  }

  void _reset() {
    _ctrl.clear();
    setState(() { _result = null; _error = null; _charCount = 0; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      appBar: AppBar(
        backgroundColor: JanMatTheme.background,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: const Text('Text Message'),
        centerTitle: true,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Header(),
            const SizedBox(height: 24),
            if (_result == null) ...[
              _TextField(ctrl: _ctrl, charCount: _charCount),
              const SizedBox(height: 20),
              _CategoryHints(),
              const SizedBox(height: 24),
              JMButton(
                label: 'Submit Concern',
                loading: _submitting,
                icon: Icons.send_rounded,
                onPressed: (_submitting || _charCount < 10) ? null : _submit,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _ErrorBox(error: _error!),
              ],
            ] else ...[
              _SuccessBanner(submissionId: _result!),
              const SizedBox(height: 16),
              JMButton(label: 'Submit Another', outlined: true, onPressed: _reset),
            ],
          ]),
        ),
      ),
    );
  }
}

Future<void> _showLocationError(BuildContext context, LocationResult loc) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF111827),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.location_off_rounded, color: Color(0xFFFF4D6D)),
        SizedBox(width: 10),
        Text('Location Required', style: TextStyle(color: Colors.white, fontSize: 17)),
      ]),
      content: Text(
        loc.errorMessage ?? 'Location is required to submit a concern.',
        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel', style: TextStyle(color: Color(0xFF9CA3AF))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F8EF7)),
          onPressed: () async {
            Navigator.pop(ctx);
            if (loc.isPermanentlyDenied) {
              await LocationService.openAppSettings();
            } else {
              await LocationService.openLocationSettings();
            }
          },
          child: Text(
            loc.isPermanentlyDenied ? 'Open App Settings' : 'Enable Location',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 54, height: 54,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFF4F8EF7)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 28),
      ),
      const SizedBox(height: 16),
      const Text('Describe Your Concern', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Write in any language — Hindi, Kannada, Tamil, Telugu, Bengali or English.', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 13)),
    ]);
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController ctrl;
  final int charCount;
  const _TextField({required this.ctrl, required this.charCount});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      TextField(
        controller: ctrl,
        maxLines: 7,
        maxLength: 2000,
        style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 15, height: 1.6),
        decoration: InputDecoration(
          hintText: 'e.g. "Our ward road near the market has large potholes causing accidents and damaging vehicles. Please repair urgently."',
          hintStyle: const TextStyle(color: JanMatTheme.textMuted, fontSize: 13, height: 1.5),
          counterText: '',
          fillColor: JanMatTheme.card,
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: JanMatTheme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: JanMatTheme.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: JanMatTheme.primary, width: 1.5)),
        ),
      ),
      const SizedBox(height: 6),
      Text('$charCount / 2000', style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
    ]);
  }
}

class _CategoryHints extends StatelessWidget {
  static const _categories = ['Roads', 'Water', 'Health', 'Education', 'Sanitation', 'Other'];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Common categories', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8, runSpacing: 8,
        children: _categories.map((c) {
          final color = JanMatTheme.catColors[c] ?? JanMatTheme.catColors['Other']!;
          return JMBadge(label: c, color: color);
        }).toList(),
      ),
    ]);
  }
}

class _SuccessBanner extends StatelessWidget {
  final String submissionId;
  const _SuccessBanner({required this.submissionId});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: JanMatTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: JanMatTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.check_circle_rounded, color: JanMatTheme.accent, size: 28),
          SizedBox(width: 12),
          Text('Submitted Successfully!', style: TextStyle(color: JanMatTheme.accent, fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        const SizedBox(height: 10),
        const Text('Your concern has been received and will be processed by AI. It will appear in the MP\'s priority dashboard.', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 10),
        Text('Submission ID: $submissionId', style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
      ]),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: JanMatTheme.errorColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: JanMatTheme.errorColor.withValues(alpha: 0.3))),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(error, style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 13))),
      ]),
    );
  }
}
