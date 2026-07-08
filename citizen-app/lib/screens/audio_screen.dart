import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../main.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/offline_queue_service.dart';
import '../widgets/result_card.dart';
import 'heatmap_screen.dart';

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
  SubmissionResult? _result;
  String? _error;
  String? _selectedCategory;

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
    setState(() { _hasRecording = false; _filePath = null; _elapsed = Duration.zero; _result = null; _error = null; _selectedCategory = null; });
  }

  Future<void> _submit() async {
    if (_filePath == null) return;
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
    // Flush any previously queued submissions first (silent background retry)
    OfflineQueueService().retryPending().ignore();

    try {
      final svc = ApiService();
      final res = await svc.submitAudio(_filePath!, token: app.token, lat: loc.lat, lng: loc.lng);
      if (mounted) {
        setState(() { _result = SubmissionResult.fromMap(res); _submitting = false; });
        app.refreshProfile();
      }
    } on DioException catch (e) {
      if (isNetworkError(e) && loc.lat != null && loc.lng != null) {
        // No connectivity — save to offline queue
        await OfflineQueueService().enqueueAudio(
          filePath: _filePath!,
          lat: loc.lat!,
          lng: loc.lng!,
          token: app.token,
        );
        if (mounted) {
          setState(() { _submitting = false; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Row(children: [
              Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('No connection — saved offline. Will sync when you reconnect.')),
            ]),
            backgroundColor: Color(0xFF7B2FF7),
            duration: Duration(seconds: 5),
          ));
        }
        return;
      }
      final detail = (e.response?.data as Map?)?['detail']?.toString()
          ?? e.message ?? 'Submission failed';
      debugPrint('[JanMat Audio] ${e.response?.statusCode}: $detail');
      if (mounted) setState(() { _error = detail; _submitting = false; });
    } catch (e) {
      debugPrint('[JanMat Audio] $e');
      if (mounted) setState(() { _error = e.toString(); _submitting = false; });
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(children: [
            const SizedBox(height: 24),
            // Timer
            Text(_fmtDuration(_elapsed), style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 56, fontWeight: FontWeight.w200, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(
              _recording ? 'Recording...' : (_hasRecording ? 'Recording complete' : 'Tap to record'),
              style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 36),
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
            const SizedBox(height: 36),
            // Action buttons
            if (_hasRecording && _result == null) ...[
              JMButton(label: 'Submit Recording', loading: _submitting, icon: Icons.send_rounded, onPressed: _submitting ? null : _submit),
              const SizedBox(height: 12),
              JMButton(label: 'Discard & Re-record', outlined: true, onPressed: _discard),
              const SizedBox(height: 12),
            ],
            if (_result != null) ...[
              ResultCard(result: _result!),
              const SizedBox(height: 16),
              JMButton(label: 'Submit Another', outlined: true, onPressed: _discard),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: JanMatTheme.errorColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: JanMatTheme.errorColor.withValues(alpha: 0.3))),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            const _LanguageNote(),
            const SizedBox(height: 16),
            JMCategoryPicker(
              selected: _selectedCategory,
              onSelect: (cat) => setState(() {
                _selectedCategory = _selectedCategory == cat ? null : cat;
              }),
              onViewMap: (cat) => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => HeatmapScreen(initialCategory: cat)),
              ),
            ),
            const SizedBox(height: 16),
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
      child: const Row(children: [
        Icon(Icons.translate_rounded, color: JanMatTheme.primary, size: 16),
        SizedBox(width: 8),
        Flexible(child: Text(
          'Supports Hindi, Kannada, Tamil, Telugu, Bengali & English',
          style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 11),
          overflow: TextOverflow.ellipsis,
        )),
      ]),
    );
  }
}
