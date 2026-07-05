import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../theme.dart';
import '../services/api_service.dart';

class AudioScreen extends StatefulWidget {
  const AudioScreen({super.key});
  @override
  State<AudioScreen> createState() => _AudioScreenState();
}

class _AudioScreenState extends State<AudioScreen> with TickerProviderStateMixin {
  final _record = AudioRecorder();
  bool _recording = false;
  bool _hasRecording = false;
  bool _submitting = false;
  String? _filePath;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _result;
  String? _error;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.9, end: 1.1).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _timer?.cancel();
    _record.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _record.hasPermission();
    if (!hasPermission) {
      _showError('Microphone permission denied. Please enable it in Settings.');
      return;
    }
    final dir = await getTemporaryDirectory();
    _filePath = '${dir.path}/janmat_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _record.start(const RecordConfig(), path: _filePath!);
    _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
    setState(() { _recording = true; _hasRecording = false; _result = null; _error = null; });
  }

  Future<void> _stopRecording() async {
    await _record.stop();
    _timer?.cancel();
    setState(() { _recording = false; _hasRecording = true; });
  }

  void _discard() {
    setState(() { _hasRecording = false; _filePath = null; _elapsed = Duration.zero; _result = null; _error = null; });
  }

  Future<void> _submit() async {
    if (_filePath == null) return;
    setState(() { _submitting = true; _error = null; });
    final app = context.read<AppState>();
    try {
      final svc = ApiService();
      final res = await svc.submitAudio(_filePath!, token: app.token);
      if (mounted) setState(() { _result = res['submission_id'] ?? 'submitted'; _submitting = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Submission failed. Please try again.'; _submitting = false; });
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: JanMatTheme.errorColor,
    ));
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      appBar: AppBar(
        backgroundColor: JanMatTheme.background,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: const Text('Voice Note'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            // Timer
            Text(_fmtDuration(_elapsed), style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 56, fontWeight: FontWeight.w200, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(
              _recording ? 'Recording...' : (_hasRecording ? 'Recording complete' : 'Tap to record'),
              style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 48),
            // Pulse rings + mic button
            SizedBox(
              width: 200, height: 200,
              child: Stack(alignment: Alignment.center, children: [
                if (_recording) ...[
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      width: 180 * _pulseAnim.value, height: 180 * _pulseAnim.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: JanMatTheme.primary.withValues(alpha: 0.08),
                        border: Border.all(color: JanMatTheme.primary.withValues(alpha: 0.2)),
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      width: 140 * _pulseAnim.value, height: 140 * _pulseAnim.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: JanMatTheme.primary.withValues(alpha: 0.1),
                      ),
                    ),
                  ),
                ],
                GestureDetector(
                  onTap: _recording ? _stopRecording : (_hasRecording ? null : _startRecording),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _recording
                        ? const LinearGradient(colors: [Color(0xFFFF4D6D), Color(0xFFFF6B35)])
                        : (_hasRecording ? const LinearGradient(colors: [JanMatTheme.accent, JanMatTheme.primary]) : JanMatTheme.primaryGradient),
                      boxShadow: [BoxShadow(
                        color: (_recording ? JanMatTheme.errorColor : JanMatTheme.primary).withValues(alpha: 0.4),
                        blurRadius: 24, spreadRadius: 4,
                      )],
                    ),
                    child: Icon(
                      _recording ? Icons.stop_rounded : (_hasRecording ? Icons.check_rounded : Icons.mic_rounded),
                      color: Colors.white, size: 44,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 48),
            // Action buttons
            if (_hasRecording && _result == null) ...[
              JMButton(label: 'Submit Recording', loading: _submitting, icon: Icons.send_rounded, onPressed: _submitting ? null : _submit),
              const SizedBox(height: 12),
              JMButton(label: 'Discard & Re-record', outlined: true, onPressed: _discard),
            ],
            if (_result != null) ...[
              _SuccessBanner(submissionId: _result!),
              const SizedBox(height: 16),
              JMButton(label: 'Submit Another', outlined: true, onPressed: _discard),
            ],
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: JanMatTheme.errorColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: JanMatTheme.errorColor.withValues(alpha: 0.3))),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 13))),
                ]),
              ),
            const Spacer(),
            const _LanguageNote(),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String submissionId;
  const _SuccessBanner({required this.submissionId});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JanMatTheme.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JanMatTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_rounded, color: JanMatTheme.accent, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Submitted Successfully!', style: TextStyle(color: JanMatTheme.accent, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 2),
          Text('ID: $submissionId', style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
        ])),
      ]),
    );
  }
}

class _LanguageNote extends StatelessWidget {
  const _LanguageNote();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: JanMatTheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: JanMatTheme.border),
      ),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.translate_rounded, color: JanMatTheme.primary, size: 16),
        SizedBox(width: 8),
        Text('Supports Hindi, Kannada, Tamil, Telugu, Bengali & English', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 11)),
      ]),
    );
  }
}
