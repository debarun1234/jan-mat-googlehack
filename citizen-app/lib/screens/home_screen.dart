import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<SubmissionState>().history;
    final auth = context.read<AuthService>();
    final phone = auth.phoneNumber ?? '';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero header ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.layers_outlined, color: Colors.white),
                tooltip: 'Heatmap',
                onPressed: () => Navigator.pushNamed(context, '/heatmap'),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white70),
                tooltip: 'Sign out',
                onPressed: () async {
                  await auth.signOut();
                  if (context.mounted) Navigator.pushReplacementNamed(context, '/phone');
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF1565C0)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('⚖️', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        const Text(
                          'JanMat',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          phone.isNotEmpty ? phone : 'लोगों की प्राथमिकता · People\'s Priority Engine',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Subtitle ─────────────────────────────────────
                  const Text(
                    'Submit your grievance',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Voice • Text • Photo — any Indian language',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),

                  // ── Submission options ────────────────────────────
                  _SubmissionCard(
                    icon: '🎙️',
                    title: 'बोलें / Speak',
                    subtitle: 'Hindi, Kannada, Tamil, Telugu, Bengali, Marathi',
                    color: const Color(0xFF1A237E),
                    onTap: () => Navigator.pushNamed(context, '/audio'),
                  ),
                  const SizedBox(height: 12),
                  _SubmissionCard(
                    icon: '✍️',
                    title: 'लिखें / Write',
                    subtitle: 'Type in any language or English',
                    color: const Color(0xFF1B5E20),
                    onTap: () => Navigator.pushNamed(context, '/text'),
                  ),
                  const SizedBox(height: 12),
                  _SubmissionCard(
                    icon: '📷',
                    title: 'फ़ोटो / Photo',
                    subtitle: 'Click a photo of the problem',
                    color: const Color(0xFFE65100),
                    onTap: () => Navigator.pushNamed(context, '/image'),
                  ),

                  const SizedBox(height: 32),

                  // ── Recent submissions ────────────────────────────
                  if (history.isNotEmpty) ...[
                    const Text(
                      'Recent Submissions',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ...history.take(3).map((s) => _HistoryItem(record: s)),
                  ],

                  // ── Heatmap CTA ───────────────────────────────────
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(context, '/heatmap'),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF00796B), Color(0xFF0288D1)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: const [
                        Icon(Icons.layers, color: Colors.white, size: 22),
                        SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('View Constituency Heatmap', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                          Text('See where local needs are highest — same view as your MP', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ])),
                        Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
                      ]),
                    ),
                  ),

                  // ── Privacy note ──────────────────────────────────
                  Container(
                    margin: const EdgeInsets.only(top: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Text('🔒', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your privacy is protected',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              Text(
                                'Submissions are anonymized. Your name is never shared with anyone.',
                                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SubmissionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(icon, style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final SubmissionRecord record;
  const _HistoryItem({required this.record});

  @override
  Widget build(BuildContext context) {
    final typeIcon = record.type == 'audio' ? '🎙️' : record.type == 'image' ? '📷' : '✍️';
    final urgencyColor = record.urgency >= 4
        ? Colors.red[700]!
        : record.urgency >= 3
            ? Colors.orange[700]!
            : Colors.green[700]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
      ),
      child: Row(
        children: [
          Text(typeIcon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.summary,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo[50],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        record.category,
                        style: TextStyle(fontSize: 10, color: Colors.indigo[700], fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Urgency ${record.urgency}/5',
                      style: TextStyle(fontSize: 11, color: urgencyColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            record.submissionId.substring(4, 10).toUpperCase(),
            style: TextStyle(fontSize: 10, color: Colors.grey[400], fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
