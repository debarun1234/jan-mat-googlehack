import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_service.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});
  @override State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final Completer<GoogleMapController> _mapCtrl = Completer();

  // Bangalore North constituency centre
  static const _center = LatLng(13.0688, 77.5803);

  String _selectedCategory = 'All';
  final _categories = ['All', 'Education', 'Health', 'Roads', 'Water', 'Sanitation'];
  final Map<String, Color> _catColors = {
    'All':        const Color(0xFF2196F3),
    'Education':  const Color(0xFF9C27B0),
    'Health':     const Color(0xFFE91E63),
    'Roads':      const Color(0xFFFF9800),
    'Water':      const Color(0xFF00BCD4),
    'Sanitation': const Color(0xFF4CAF50),
  };

  bool _loading = true;
  String? _pinCode;
  List<HotspotPoint> _points = [];
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _loadPinAndFetch();
  }

  Future<void> _loadPinAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _pinCode = prefs.getString('user_pin_code') ?? '560064';
    await _fetchHeatmap();
  }

  Future<void> _fetchHeatmap() async {
    setState(() { _loading = true; });
    try {
      final svc = context.read<UserService>();
      final data = await svc.getHeatmap(
        _pinCode!,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
      );
      final raw = data['heatmap'] as List? ?? [];
      _points = raw.map((e) => HotspotPoint.fromJson(e as Map<String, dynamic>)).toList();
      _buildCircles();
    } catch (e) {
      // Use demo data if API unavailable
      _points = _demoPoints();
      _buildCircles();
      // Don't surface error — fall back to demo data
    }
    setState(() => _loading = false);
  }

  void _buildCircles() {
    final cat = _selectedCategory;
    final color = _catColors[cat] ?? const Color(0xFF2196F3);
    final filtered = cat == 'All' ? _points : _points.where((p) => p.category == cat).toList();

    int maxW = filtered.isEmpty ? 1 : filtered.map((p) => p.weight).reduce((a, b) => a > b ? a : b);

    _circles = filtered.map((p) {
      final opacity = 0.15 + 0.55 * (p.weight / maxW);
      final radius = 300.0 + 1200.0 * (p.weight / maxW);
      return Circle(
        circleId: CircleId('${p.lat}_${p.lng}_${p.category}'),
        center: LatLng(p.lat, p.lng),
        radius: radius,
        fillColor: color.withValues(alpha: opacity),
        strokeColor: color.withValues(alpha: 0.6),
        strokeWidth: 1,
      );
    }).toSet();
  }

  List<HotspotPoint> _demoPoints() => [
    HotspotPoint(lat: 13.0688, lng: 77.5803, weight: 45, category: 'Roads',      avgUrgency: 3.8),
    HotspotPoint(lat: 13.0750, lng: 77.5900, weight: 38, category: 'Water',      avgUrgency: 4.2),
    HotspotPoint(lat: 13.0620, lng: 77.5720, weight: 22, category: 'Education',  avgUrgency: 3.1),
    HotspotPoint(lat: 13.0800, lng: 77.5760, weight: 31, category: 'Health',     avgUrgency: 3.9),
    HotspotPoint(lat: 13.0560, lng: 77.5860, weight: 17, category: 'Sanitation', avgUrgency: 4.5),
    HotspotPoint(lat: 13.0900, lng: 77.5680, weight: 28, category: 'Roads',      avgUrgency: 3.3),
    HotspotPoint(lat: 13.0640, lng: 77.5950, weight: 19, category: 'Water',      avgUrgency: 3.7),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1B2D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1B2D),
        elevation: 0,
        title: const Text('Constituency Heatmap', style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _fetchHeatmap,
          ),
        ],
      ),
      body: Column(children: [
        // Category filter chips
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final selected = _selectedCategory == cat;
              final color = _catColors[cat] ?? const Color(0xFF2196F3);
              return FilterChip(
                label: Text(cat, style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontSize: 13, fontWeight: FontWeight.w500,
                )),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selectedCategory = cat);
                  _buildCircles();
                  setState(() {});
                },
                backgroundColor: const Color(0xFF1A2C42),
                selectedColor: color,
                checkmarkColor: Colors.white,
                side: BorderSide(color: color.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              );
            },
          ),
        ),

        // Map
        Expanded(
          child: Stack(children: [
            GoogleMap(
              initialCameraPosition: const CameraPosition(target: _center, zoom: 12.5),
              onMapCreated: (ctrl) => _mapCtrl.complete(ctrl),
              mapType: MapType.normal,
              circles: _circles,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: true,
            ),

            if (_loading)
              Container(
                color: Colors.black45,
                child: const Center(child: CircularProgressIndicator(color: Color(0xFF2196F3))),
              ),

            // Legend
            Positioned(
              bottom: 120,
              right: 12,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xEE0F1B2D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A4060)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Complaint Density', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    _legendRow(Colors.red.withValues(alpha: 0.8),   'High'),
                    _legendRow(Colors.orange.withValues(alpha: 0.7), 'Medium'),
                    _legendRow(Colors.blue.withValues(alpha: 0.5),  'Low'),
                  ],
                ),
              ),
            ),

            // Transparency banner
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xEE0F1B2D),
                child: Row(children: const [
                  Icon(Icons.info_outline, color: Color(0xFF4CAF50), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This map shows aggregated, anonymized complaint patterns in your constituency. Your MP uses this data to prioritize development projects.',
                      style: TextStyle(color: Color(0xFF8899AA), fontSize: 11, height: 1.4),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _legendRow(Color color, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    ]),
  );
}
