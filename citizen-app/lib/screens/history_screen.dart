import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../theme.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _selectedCategory = 'All';

  static const _categories = ['All', 'Roads', 'Water', 'Health', 'Education', 'Sanitation', 'Other'];

  List<Map<String, dynamic>> get _filteredItems => _selectedCategory == 'All'
      ? _items
      : _items.where((e) => (e['category'] ?? 'Other') == _selectedCategory).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final app = context.read<AppState>();
    if (app.token == null) { setState(() => _loading = false); return; }
    try {
      final svc = ApiService();
      final data = await svc.getHistory(app.token!);
      if (mounted) setState(() { _items = List<Map<String, dynamic>>.from(data); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _openDetail(Map<String, dynamic> item) {
    final app = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubmissionDetailSheet(item: item, token: app.token),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      body: RefreshIndicator(
        color: JanMatTheme.primary,
        backgroundColor: JanMatTheme.surface,
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          _AppBar(count: _filteredItems.length, total: _items.length),
          SliverToBoxAdapter(
            child: _CategoryFilter(
              categories: _categories,
              selected: _selectedCategory,
              onSelect: (c) => setState(() => _selectedCategory = c),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: JanMatTheme.primary)))
          else if (_error != null)
            SliverFillRemaining(child: _ErrorState(error: _error!, onRetry: _load))
          else if (_filteredItems.isEmpty)
            SliverFillRemaining(child: _EmptyState(filtered: _selectedCategory != 'All'))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HistoryCard(
                    item: _filteredItems[i],
                    onTap: () => _openDetail(_filteredItems[i]),
                  ),
                ),
                childCount: _filteredItems.length,
              )),
            ),
        ]),
      ),
    );
  }
}

// ── Detail bottom sheet ─────────────────────────────────────────────────

class _SubmissionDetailSheet extends StatefulWidget {
  final Map<String, dynamic> item;
  final String? token;
  const _SubmissionDetailSheet({required this.item, this.token});

  @override
  State<_SubmissionDetailSheet> createState() => _SubmissionDetailSheetState();
}

class _SubmissionDetailSheetState extends State<_SubmissionDetailSheet> {
  List<int>? _mediaBytes;
  bool _mediaLoading = false;
  String? _mediaError;

  // Audio player state
  final _player = AudioPlayer();
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    final type = widget.item['input_type'] as String? ?? 'text';
    final hasMedia = (widget.item['raw_gcs_uri'] as String? ?? '').isNotEmpty;
    if ((type == 'image' || type == 'audio') && hasMedia && widget.token != null) {
      _fetchMedia();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _fetchMedia() async {
    setState(() { _mediaLoading = true; _mediaError = null; });
    final subId = widget.item['submission_id'] as String? ?? '';
    try {
      final bytes = await ApiService().getMediaBytes(subId, widget.token!);
      if (mounted) setState(() { _mediaBytes = bytes; _mediaLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _mediaError = 'Could not load media'; _mediaLoading = false; });
    }
  }

  Future<void> _togglePlay() async {
    if (_mediaBytes == null) return;
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(Uint8List.fromList(_mediaBytes!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final type = item['input_type'] as String? ?? 'text';
    final category = item['category'] as String? ?? 'Other';
    final summary = item['summary_en'] as String? ?? item['translated_text'] as String? ?? '';
    final lat = item['latitude'] as num?;
    final lng = item['longitude'] as num?;
    final date = _formatDate(item['submitted_at']);
    final urgency = item['urgency_rating'] as int? ?? 0;
    final catColor = JanMatTheme.catColors[category] ?? JanMatTheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: JanMatTheme.border, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: ListView(controller: ctrl, padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), children: [

              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_typeIcon(type), color: catColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(category, style: TextStyle(color: catColor, fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('${_typeName(type)} · $date', style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 12)),
                ])),
                if (urgency > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _urgencyColor(urgency).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _urgencyColor(urgency).withValues(alpha: 0.4)),
                    ),
                    child: Text('Urgency $urgency/5', style: TextStyle(color: _urgencyColor(urgency), fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ]),
              const SizedBox(height: 20),

              // Media section
              if (type == 'image') _buildImageSection(),
              if (type == 'audio') _buildAudioSection(),

              // Summary
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionLabel(label: 'AI Summary'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: JanMatTheme.cardBox(),
                  child: Text(summary, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 14, height: 1.6)),
                ),
              ],

              // Geotag
              if (lat != null && lng != null) ...[
                const SizedBox(height: 16),
                _SectionLabel(label: 'Location'),
                const SizedBox(height: 8),
                _GeoTag(lat: lat.toDouble(), lng: lng.toDouble()),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildImageSection() {
    if (_mediaLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: JanMatTheme.primary)),
      );
    }
    if (_mediaBytes != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionLabel(label: 'Photo Evidence'),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(
            Uint8List.fromList(_mediaBytes!),
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _MediaError(),
          ),
        ),
      ]);
    }
    if (_mediaError != null) return _MediaError(message: _mediaError);
    return const SizedBox.shrink();
  }

  Widget _buildAudioSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel(label: 'Voice Recording'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: JanMatTheme.cardBox(),
        child: _mediaLoading
            ? const Center(child: CircularProgressIndicator(color: JanMatTheme.primary))
            : _mediaError != null
                ? _MediaError(message: _mediaError)
                : _mediaBytes == null
                    ? const Center(child: Text('No audio file', style: TextStyle(color: JanMatTheme.textMuted)))
                    : Column(children: [
                        // Progress bar
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: JanMatTheme.primary,
                            inactiveTrackColor: JanMatTheme.border,
                            thumbColor: JanMatTheme.primary,
                          ),
                          child: Slider(
                            value: _duration.inSeconds > 0
                                ? _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble())
                                : 0,
                            max: _duration.inSeconds.toDouble().clamp(1, double.infinity),
                            onChanged: (v) => _player.seek(Duration(seconds: v.toInt())),
                          ),
                        ),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(_fmtDur(_position), style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
                          GestureDetector(
                            onTap: _togglePlay,
                            child: Container(
                              width: 52, height: 52,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [JanMatTheme.primary, JanMatTheme.accent]),
                              ),
                              child: Icon(
                                _playerState == PlayerState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white, size: 30,
                              ),
                            ),
                          ),
                          Text(_fmtDur(_duration), style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
                        ]),
                      ]),
      ),
    ]);
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  IconData _typeIcon(String t) {
    switch (t) {
      case 'audio': return Icons.mic_rounded;
      case 'image': return Icons.camera_alt_rounded;
      default: return Icons.edit_rounded;
    }
  }

  String _typeName(String t) {
    switch (t) {
      case 'audio': return 'Voice note';
      case 'image': return 'Photo';
      default: return 'Text';
    }
  }

  Color _urgencyColor(int u) {
    if (u >= 4) return JanMatTheme.errorColor;
    if (u >= 3) return JanMatTheme.amber;
    return JanMatTheme.accent;
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return ''; }
  }
}

// ── Supporting widgets ──────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
  );
}

class _GeoTag extends StatelessWidget {
  final double lat;
  final double lng;
  const _GeoTag({required this.lat, required this.lng});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: JanMatTheme.cardBox(),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: JanMatTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.location_on_rounded, color: JanMatTheme.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GPS Coordinates', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
            style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11, fontFamily: 'monospace'),
          ),
        ]),
      ]),
    );
  }
}

class _MediaError extends StatelessWidget {
  final String? message;
  const _MediaError({this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: JanMatTheme.errorColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message ?? 'Media unavailable', style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 13)),
    );
  }
}


// ── History card ────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  const _HistoryCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final category = item['category'] ?? 'Other';
    final status   = item['processing_status'] ?? 'processed';
    final summary  = item['summary_en'] ?? item['translated_text'] ?? 'No summary';
    final type     = item['input_type'] ?? 'text';
    final date     = _formatDate(item['submitted_at']);
    final urgency  = item['urgency_rating'] ?? 0;
    final hasMedia = (item['raw_gcs_uri'] as String? ?? '').isNotEmpty;

    final catColor   = JanMatTheme.catColors[category] ?? JanMatTheme.catColors['Other']!;
    final statusInfo = _statusInfo(status);
    final typeIcon   = _typeIcon(type);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: JanMatTheme.cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: catColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(typeIcon, color: catColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(category, style: TextStyle(color: catColor, fontSize: 13, fontWeight: FontWeight.w700)),
              Text(date, style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
            ])),
            JMBadge(label: statusInfo.$1, color: statusInfo.$2),
          ]),
          const SizedBox(height: 12),
          Text(summary, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 13, height: 1.5), maxLines: 3, overflow: TextOverflow.ellipsis),
          if (urgency > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Text('Urgency', style: TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
              const SizedBox(width: 8),
              ...List.generate(5, (i) => Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Icon(Icons.circle, size: 8, color: i < urgency ? JanMatTheme.amber : JanMatTheme.border),
              )),
            ]),
          ],
          // "Tap to view" hint when media is available
          if (hasMedia) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(
                type == 'image' ? Icons.image_rounded : Icons.play_circle_outline_rounded,
                color: JanMatTheme.primary, size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                type == 'image' ? 'Tap to view photo' : 'Tap to play recording',
                style: const TextStyle(color: JanMatTheme.primary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded, color: JanMatTheme.textMuted, size: 16),
            ]),
          ],
        ]),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'audio': return Icons.mic_rounded;
      case 'image': return Icons.camera_alt_rounded;
      default: return Icons.edit_rounded;
    }
  }

  (String, Color) _statusInfo(String status) {
    switch (status) {
      case 'processed': return ('Processed', JanMatTheme.accent);
      case 'processing': return ('Processing', JanMatTheme.primary);
      case 'failed': return ('Failed', JanMatTheme.errorColor);
      default: return ('Pending', JanMatTheme.amber);
    }
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) {
        if (diff.inHours == 0) return '${diff.inMinutes}m ago';
        return '${diff.inHours}h ago';
      }
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return ''; }
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final int count;
  final int total;
  const _AppBar({required this.count, required this.total});
  @override
  Widget build(BuildContext context) {
    final subtitle = count == total
        ? '$total submission${total == 1 ? "" : "s"}'
        : '$count of $total submission${total == 1 ? "" : "s"}';
    return SliverAppBar(
      pinned: true,
      expandedHeight: 90,
      backgroundColor: JanMatTheme.background,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        title: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Reports', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
            Text(subtitle, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 11)),
          ],
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
          final color = cat == 'All' ? JanMatTheme.primary : (JanMatTheme.catColors[cat] ?? JanMatTheme.primary);
          return GestureDetector(
            onTap: () => onSelect(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
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

class _EmptyState extends StatelessWidget {
  final bool filtered;
  const _EmptyState({this.filtered = false});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(filtered ? Icons.filter_list_off_rounded : Icons.inbox_rounded, color: JanMatTheme.textMuted, size: 64),
      const SizedBox(height: 16),
      Text(filtered ? 'No reports in this category' : 'No submissions yet',
          style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(
        filtered ? 'Try selecting a different category or "All".' : 'Your reports will appear here after you submit them.',
        style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    ]));
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline_rounded, color: JanMatTheme.errorColor, size: 48),
      const SizedBox(height: 12),
      const Text('Failed to load reports', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(error, style: const TextStyle(color: JanMatTheme.textMuted, fontSize: 12), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
    ]));
  }
}
