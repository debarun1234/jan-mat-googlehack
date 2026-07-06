import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../theme.dart';
import '../services/user_service.dart';

class HeatmapScreen extends StatefulWidget {
  final String? initialCategory;
  const HeatmapScreen({super.key, this.initialCategory});
  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  final Completer<GoogleMapController> _mapCtrl = Completer();
  static const _center = LatLng(13.0688, 77.5803);

  String _selectedCategory = 'All';
  final _categories = ['All', 'Roads', 'Water', 'Health', 'Education', 'Sanitation'];

  bool _loading = true;
  String? _pinCode;
  List<HotspotPoint> _points = [];
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial != null && _categories.contains(initial)) {
      _selectedCategory = initial;
    }
    _loadPinAndFetch();
  }

  Future<void> _loadPinAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    _pinCode = prefs.getString('user_pin_code') ?? '560064';
    await _fetchHeatmap();
  }

  Future<void> _fetchHeatmap() async {
    setState(() => _loading = true);
    try {
      final app = context.read<AppState>();
      final svc = UserService();
      final data = await svc.getHeatmap(
        _pinCode!,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
        token: app.token,
      );
      final raw = data['heatmap'] as List? ?? [];
      _points = raw.map((e) => HotspotPoint.fromJson(e as Map<String, dynamic>)).toList();
      _buildCircles();
    } catch (_) {
      _points = _demoPoints();
      _buildCircles();
    }
    setState(() => _loading = false);
  }

  void _buildCircles() {
    final cat = _selectedCategory;
    final color = JanMatTheme.catColors[cat] ?? JanMatTheme.primary;
    final filtered = cat == 'All' ? _points : _points.where((p) => p.category == cat).toList();
    final maxW = filtered.isEmpty ? 1 : filtered.map((p) => p.weight).reduce((a, b) => a > b ? a : b);

    _circles = filtered.map((p) {
      final opacity = 0.15 + 0.55 * (p.weight / maxW);
      final radius  = 300.0 + 1200.0 * (p.weight / maxW);
      return Circle(
        circleId: CircleId('${p.lat}_${p.lng}_${p.category}'),
        center: LatLng(p.lat, p.lng),
        radius: radius,
        fillColor: color.withValues(alpha: opacity),
        strokeColor: color.withValues(alpha: 0.7),
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
      backgroundColor: JanMatTheme.background,
      body: Column(children: [
        _AppBar(onRefresh: _fetchHeatmap),
        _CategoryFilter(
          categories: _categories,
          selected: _selectedCategory,
          onSelect: (c) {
            setState(() => _selectedCategory = c);
            _buildCircles();
            setState(() {});
          },
        ),
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
                child: const Center(child: CircularProgressIndicator(color: JanMatTheme.primary)),
              ),
            _Legend(),
            _InfoBanner(),
          ]),
        ),
      ]),
    );
  }
}

class _AppBar extends StatelessWidget {
  final VoidCallback onRefresh;
  const _AppBar({required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: JanMatTheme.background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
          child: Row(children: [
            const Icon(Icons.map_rounded, color: JanMatTheme.primary, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Constituency Heatmap', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                Text('Live complaint density', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 11)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: JanMatTheme.primary),
              onPressed: onRefresh,
            ),
          ]),
        ),
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;
  const _CategoryFilter({required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: JanMatTheme.background,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = categories[i];
          final isSelected = selected == cat;
          final color = JanMatTheme.catColors[cat] ?? JanMatTheme.primary;
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? color : JanMatTheme.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? color : JanMatTheme.border),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 80, right: 12,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JanMatTheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JanMatTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Density', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          _Row(Colors.red.withValues(alpha: 0.8),    'High'),
          _Row(Colors.orange.withValues(alpha: 0.7), 'Medium'),
          _Row(Colors.blue.withValues(alpha: 0.5),  'Low'),
        ]),
      ),
    );
  }

  Widget _Row(Color c, String l) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(l, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 11)),
    ]),
  );
}

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: JanMatTheme.surface.withValues(alpha: 0.95),
        child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: JanMatTheme.accent, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Aggregated, anonymised complaint patterns. Your MP uses this data to prioritise development projects.',
            style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 11, height: 1.4),
          )),
        ]),
      ),
    );
  }
}
