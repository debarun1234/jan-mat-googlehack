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
                  child: _HistoryCard(item: _filteredItems[i]),
                ),
                childCount: _filteredItems.length,
              )),
            ),
        ]),
      ),
    );
  }
}

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

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final category = item['category'] ?? 'Other';
    final status   = item['processing_status'] ?? 'pending';
    final summary  = item['summary_en'] ?? item['translated_text'] ?? 'No summary';
    final type     = item['input_type'] ?? 'text';
    final date     = _formatDate(item['submitted_at']);
    final urgency  = item['urgency_rating'] ?? 0;

    final catColor   = JanMatTheme.catColors[category] ?? JanMatTheme.catColors['Other']!;
    final statusInfo = _statusInfo(status);
    final typeIcon   = _typeIcon(type);

    return Container(
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
      ]),
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
