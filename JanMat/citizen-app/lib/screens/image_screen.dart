import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

import '../main.dart';
import '../services/api_service.dart';
import '../widgets/result_card.dart';

class ImageSubmissionScreen extends StatefulWidget {
  const ImageSubmissionScreen({super.key});

  @override
  State<ImageSubmissionScreen> createState() => _ImageSubmissionScreenState();
}

class _ImageSubmissionScreenState extends State<ImageSubmissionScreen> {
  File? _imageFile;
  final _captionController = TextEditingController();
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
      await Geolocator.requestPermission();
      _position = await Geolocator.getCurrentPosition();
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() { _imageFile = File(picked.path); _result = null; _error = null; });
    }
  }

  Future<void> _submit() async {
    if (_imageFile == null) return;
    setState(() { _loading = true; _error = null; _result = null; });

    try {
      final api = context.read<ApiService>();
      final result = await api.submitImage(
        imageFile: _imageFile!,
        latitude: _position?.latitude,
        longitude: _position?.longitude,
        caption: _captionController.text.trim().isEmpty ? null : _captionController.text.trim(),
      );
      setState(() { _result = result; _loading = false; });

      if (result.category != null) {
        context.read<SubmissionState>().addSubmission(SubmissionRecord(
          submissionId: result.submissionId,
          type: 'image',
          category: result.category!,
          urgency: result.urgencyRating ?? 3,
          summary: result.summaryEn ?? 'Photo submission',
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
      appBar: AppBar(title: const Text('📷  Photo Submission')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image picker area
            GestureDetector(
              onTap: () => _showPickerDialog(),
              child: Container(
                width: double.infinity,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _imageFile != null ? const Color(0xFF1A237E) : Colors.grey[300]!,
                    width: _imageFile != null ? 2 : 1,
                    style: BorderStyle.solid,
                  ),
                ),
                child: _imageFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: Image.file(_imageFile!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('📷', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          const Text(
                            'Tap to take a photo\nor choose from gallery',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Max 5MB · JPG, PNG, WEBP',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
              ),
            ),

            if (_imageFile != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _showPickerDialog,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Change photo'),
              ),
            ],

            const SizedBox(height: 20),

            // Caption
            const Text(
              'Add a description (optional)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _captionController,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Describe what\'s in the photo — in any language\nयह फ़ोटो किस समस्या की है?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1A237E), width: 2),
                ),
              ),
            ),

            if (_position != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    'Location will be tagged automatically',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                child: Text(_error!, style: TextStyle(color: Colors.red[700], fontSize: 13)),
              ),
            ],

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_imageFile == null || _loading) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('Submit Photo / फ़ोटो जमा करें',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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

  void _showPickerDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF1A237E)),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF1A237E)),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
