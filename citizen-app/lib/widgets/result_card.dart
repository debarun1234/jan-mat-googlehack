import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ResultCard extends StatelessWidget {
  final SubmissionResult result;
  const ResultCard({super.key, required this.result});

  Color get _urgencyColor {
    final u = result.urgencyRating ?? 3;
    if (u >= 4) return Colors.red[700]!;
    if (u >= 3) return Colors.orange[700]!;
    return Colors.green[700]!;
  }

  String get _categoryEmoji {
    switch (result.category) {
      case 'Education': return '🏫';
      case 'Health': return '🏥';
      case 'Roads': return '🛣️';
      case 'Water': return '💧';
      case 'Sanitation': return '🚽';
      default: return '📋';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✅', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Submission Received!',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1B5E20)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (result.category != null) ...[
            _Row(label: 'Category', value: '$_categoryEmoji ${result.category}'),
            const SizedBox(height: 6),
          ],

          if (result.urgencyRating != null)
            _Row(
              label: 'Urgency',
              value: '${result.urgencyRating}/5',
              valueColor: _urgencyColor,
            ),

          if (result.summaryEn != null) ...[
            const SizedBox(height: 10),
            const Text('Summary', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              result.summaryEn!,
              style: const TextStyle(fontSize: 13, color: Color(0xFF263238)),
            ),
          ],

          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                const Text('ID: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  result.submissionId,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          Text(
            '🔒 Your submission is anonymous and has been sent to the development planning system.',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _Row({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor ?? const Color(0xFF263238))),
      ],
    );
  }
}
