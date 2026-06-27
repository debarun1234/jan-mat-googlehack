import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../widgets/result_card.dart';

class AudioSubmissionScreen extends StatefulWidget {
  const AudioSubmissionScreen({super.key});

  @override
  State<AudioSubmissionScreen> createState() => _AudioSubmissionScreenState();
}

class _AudioSubmissionScreenState extends State<AudioSubmissionScreen>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _hasRecording = false;
  String? _audioPath;
  bool _loading = false;
  SubmissionResult? _result;
  String? _error;
  Position? _position;
  Duration _elapsed = Duration.zero;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _getLocation();
  }

  Future<void> _getLocation() async {
    try {
      await Geolocator.requestPermission();
      _position = await Geolocator.getCurrentPosition();
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      setState(() => _error = 'Microphone permission required');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/janmat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
      path: path,
    );
    _audioPath = path;
    _elapsed = Duration.zero;
    setState(() { _isRecording = true; _error = null; });
    _pulseCtrl.repeat(reverse: true);

    // Timer for elapsed
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!_isRecording) return false;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed.inSeconds >= 120) { await _stopRecording(); return false; }
      return true;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    _pulseCtrl.stop();
    setState(() { _isRecording = false; _hasRecording = true; });
  }

  Future<void> _submit() async {
    if (_audioPath == null) return;
    setState(() { _loading = true; _error = null; _result = null; });

    try {
      final api = context.read<ApiService>();
      final result = await api.submitAudio(
        audioFile: File(_audioPath!),
        latitude: _position?.latitude,
        longitude: _position?.longitude,
      );
      setState(() { _result = result; _loading = false; });

      if (result.category != null) {
        context.read<SubmissionState>().addSubmission(SubmissionRecord(
          submissionId: result.submissionId,
          type: 'audio',
          category: result.category!,
          urgency: result.urgencyRating ?? 3,
          summary: result.summaryEn ?? 'Voice submission',
          submittedAt: DateTime.now(),
        ));
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _reset() {
    setState(() {
      _hasRecording = false;
      _audioPath = null;
      _result = null;
      _error = null;
      _elapsed = Duration.zero;
    });
  }

  String get _elapsedStr {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _recorder.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎙️  Voice Submission')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Language hint
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🌐', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    'Hindi • Kannada • Tamil • Telugu\nBengali • Marathi • English',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.blue[800], fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Big record button
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, child) {
                final scale = _isRecording ? 1.0 + _pulseCtrl.value * 0.12 : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: GestureDetector(
                onTap: _isRecording ? _stopRecording : (_hasRecording ? null : _startRecording),
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.red : (_hasRecording ? Colors.green : const Color(0xFF1A237E)),
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? Colors.red : const Color(0xFF1A237E)).withOpacity(0.3),
                        blurRadius: 24,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : (_hasRecording ? Icons.check : Icons.mic),
                    size: 60,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (_isRecording) ...[
              Text(
                _elapsedStr,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 4),
              const Text('Recording... tap to stop', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
            ] else if (_hasRecording) ...[
              const Text('Recording ready', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.green)),
              const SizedBox(height: 4),
              Text('Duration: $_elapsedStr', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 4),
              TextButton(onPressed: _reset, child: const Text('Re-record')),
            ] else ...[
              const Text(
                'Press to start recording',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text('Max 2 minutes', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            ],

            if (!_isRecording && !_hasRecording) ...[
              const SizedBox(height: 32),
              const _Instruction(icon: '1️⃣', text: 'Tap the mic button to start'),
              const SizedBox(height: 8),
              const _Instruction(icon: '2️⃣', text: 'Speak clearly about your problem'),
              const SizedBox(height: 8),
              const _Instruction(icon: '3️⃣', text: 'Tap again to stop, then submit'),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 13)),
              ),
            ],

            if (_hasRecording && _result == null) ...[
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Submit / जमा करें', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],

            if (_result != null) ...[
              const SizedBox(height: 24),
              ResultCard(result: _result!),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _reset,
                child: const Text('Submit Another / फिर से'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  final String icon;
  final String text;
  const _Instruction({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: Colors.grey[700], fontSize: 14)),
      ],
    );
  }
}
