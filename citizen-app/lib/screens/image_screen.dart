import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../main.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'heatmap_screen.dart';

class ImageScreen extends StatefulWidget {
  const ImageScreen({super.key});
  @override
  State<ImageScreen> createState() => _ImageScreenState();
}

class _ImageScreenState extends State<ImageScreen> {
  File? _image;
  final _descCtrl = TextEditingController();
  bool _submitting = false;
  String? _result;
  String? _error;
  String? _selectedCategory;

  @override
  void dispose() { _descCtrl.dispose(); super.dispose(); }

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1920);
    if (xfile == null) return;
    setState(() { _image = File(xfile.path); _result = null; _error = null; });
  }

  Future<void> _submit() async {
    if (_image == null) return;
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
      final res = await svc.submitImage(
        _image!,
        description: _descCtrl.text.trim(),
        token: app.token,
        lat: loc.lat,
        lng: loc.lng,
      );
      if (mounted) setState(() { _result = res['submission_id'] ?? 'submitted'; _submitting = false; });
    } on DioException catch (e) {
      final detail = (e.response?.data as Map?)?['detail']?.toString()
          ?? e.message ?? 'Submission failed';
      debugPrint('[JanMat Image] ${e.response?.statusCode}: $detail');
      if (mounted) setState(() { _error = detail; _submitting = false; });
    } catch (e) {
      debugPrint('[JanMat Image] $e');
      if (mounted) setState(() { _error = e.toString(); _submitting = false; });
    }
  }

  void _reset() {
    _descCtrl.clear();
    setState(() { _image = null; _result = null; _error = null; _selectedCategory = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      appBar: AppBar(
        backgroundColor: JanMatTheme.background,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: const Text('Photo Evidence'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Header(),
            const SizedBox(height: 24),
            if (_result == null) ...[
              if (_image == null)
                _PickerButtons(onCamera: () => _pick(ImageSource.camera), onGallery: () => _pick(ImageSource.gallery))
              else ...[
                _ImagePreview(image: _image!, onReplace: () => _showSourceSheet()),
                const SizedBox(height: 16),
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Add a description (optional) — e.g. "Water leak on MG Road near bus stop"',
                    hintStyle: const TextStyle(color: JanMatTheme.textMuted, fontSize: 13),
                    fillColor: JanMatTheme.card, filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: JanMatTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: JanMatTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: JanMatTheme.primary, width: 1.5)),
                  ),
                ),
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
                const SizedBox(height: 20),
                JMButton(label: 'Submit Photo', loading: _submitting, icon: Icons.send_rounded, onPressed: _submitting ? null : _submit),
              ],
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

  void _showSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: JanMatTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: JanMatTheme.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ListTile(leading: const Icon(Icons.camera_alt_rounded, color: JanMatTheme.primary), title: const Text('Take Photo', style: TextStyle(color: JanMatTheme.textPrimary)), onTap: () { Navigator.pop(context); _pick(ImageSource.camera); }),
          ListTile(leading: const Icon(Icons.photo_library_rounded, color: JanMatTheme.primary), title: const Text('Choose from Gallery', style: TextStyle(color: JanMatTheme.textPrimary)), onTap: () { Navigator.pop(context); _pick(ImageSource.gallery); }),
        ]),
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
          gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF4D6D)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
      ),
      const SizedBox(height: 16),
      const Text('Photo Evidence', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Capture or upload a photo showing the issue — broken roads, water leaks, garbage, etc.', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 13)),
    ]);
  }
}

class _PickerButtons extends StatelessWidget {
  final VoidCallback onCamera, onGallery;
  const _PickerButtons({required this.onCamera, required this.onGallery});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: onCamera,
        child: Container(
          width: double.infinity, height: 180,
          decoration: BoxDecoration(
            color: JanMatTheme.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: JanMatTheme.primary.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF4D6D)]), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 12),
            const Text('Take a Photo', style: TextStyle(color: JanMatTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
            const Text('Use camera to capture the issue', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 12)),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: onGallery,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: JanMatTheme.cardBox(),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.photo_library_rounded, color: JanMatTheme.primary),
            SizedBox(width: 10),
            Text('Choose from Gallery', style: TextStyle(color: JanMatTheme.primary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    ]);
  }
}

class _ImagePreview extends StatelessWidget {
  final File image;
  final VoidCallback onReplace;
  const _ImagePreview({required this.image, required this.onReplace});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(children: [
        Image.file(image, width: double.infinity, height: 220, fit: BoxFit.cover),
        Positioned(top: 10, right: 10,
          child: GestureDetector(
            onTap: onReplace,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 20),
            ),
          ),
        ),
      ]),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String submissionId;
  const _SuccessBanner({required this.submissionId});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: JanMatTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: JanMatTheme.accent.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.check_circle_rounded, color: JanMatTheme.accent, size: 28),
          SizedBox(width: 12),
          Text('Photo Submitted!', style: TextStyle(color: JanMatTheme.accent, fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        const SizedBox(height: 10),
        const Text('Your photo has been uploaded and will be analysed by our AI pipeline.', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        Text('ID: $submissionId', style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
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
        const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor),
        const SizedBox(width: 10),
        Expanded(child: Text(error, style: const TextStyle(color: JanMatTheme.errorColor, fontSize: 13))),
      ]),
    );
  }
}
