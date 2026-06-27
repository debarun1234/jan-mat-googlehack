import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../widgets/result_card.dart';

const _languages = [
  ('auto', 'Auto Detect'),
  ('hi-IN', 'हिन्दी (Hindi)'),
  ('kn-IN', 'ಕನ್ನಡ (Kannada)'),
  ('ta-IN', 'தமிழ் (Tamil)'),
  ('te-IN', 'తెలుగు (Telugu)'),
  ('bn-IN', 'বাংলা (Bengali)'),
  ('mr-IN', 'मराठी (Marathi)'),
  ('en-IN', 'English'),
];

class TextSubmissionScreen extends StatefulWidget {
  const TextSubmissionScreen({super.key});

  @override
  State<TextSubmissionScreen> createState() => _TextSubmissionScreenState();
}

class _TextSubmissionScreenState extends State<TextSubmissionScreen> {
  final _controller = TextEditingController();
  String _selectedLang = 'auto';
  bool _loading = false;
  SubmissionResult? _result;
  String? _error;
  Position? _position;

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    try {
      final permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
      _position = await Geolocator.getCurrentPosition();
    } catch (_) {}
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.length < 5) {
      setState(() => _error = 'Please describe the problem in at least a few words');
      return;
    }

    setState(() { _loading = true; _error = null; _result = null; });

    try {
      final api = context.read<ApiService>();
      final result = await api.submitText(
        text: text,
        languageCode: _selectedLang == 'auto' ? null : _selectedLang,
        latitude: _position?.latitude,
        longitude: _position?.longitude,
      );
      setState(() { _result = result; _loading = false; });

      if (result.category != null) {
        context.read<SubmissionState>().addSubmission(SubmissionRecord(
          submissionId: result.submissionId,
          type: 'text',
          category: result.category!,
          urgency: result.urgencyRating ?? 3,
          summary: result.summaryEn ?? text.substring(0, text.length.clamp(0, 80)),
          submittedAt: DateTime.now(),
        ));
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('✍️  Write Your Complaint')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Language picker
            const Text('Language / भाषा', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLang,
                  isExpanded: true,
                  onChanged: (v) => setState(() => _selectedLang = v!),
                  items: _languages.map((l) => DropdownMenuItem(
                    value: l.$1,
                    child: Text(l.$2),
                  )).toList(),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Text input
            const Text('Describe the problem / समस्या बताएं',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 7,
              maxLength: 2000,
              decoration: InputDecoration(
                hintText: 'Example: हमारे गांव में पानी की कोई सुविधा नहीं है। पास में स्कूल नहीं है...\n\nOr in English: The road to our village is broken and impassable during monsoon...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // GPS status
            if (_position != null)
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    'Location detected (${_position!.latitude.toStringAsFixed(4)}°N)',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 13)),
              ),
            ],

            const SizedBox(height: 20),

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
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text('Submit / जमा करें', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),

            if (_result != null) ...[
              const SizedBox(height: 24),
              ResultCard(result: _result!),
            ],
          ],
        ),
      ),
    );
  }
}
