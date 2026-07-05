import 'package:flutter/material.dart';
import '../theme.dart';
import 'audio_screen.dart';
import 'text_screen.dart';
import 'image_screen.dart';

class SubmitScreen extends StatelessWidget {
  final ValueChanged<int> onTabChange;
  const SubmitScreen({super.key, required this.onTabChange});

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      body: CustomScrollView(slivers: [
        _AppBar(),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(delegate: SliverChildListDelegate([
            const SizedBox(height: 8),
            _TypeCard(
              index: 0,
              icon: Icons.mic_rounded,
              title: 'Voice Note',
              subtitle: 'Record in any language — Hindi, Kannada, Tamil, Telugu, Bengali or English. Gemini transcribes and translates automatically.',
              gradient: JanMatTheme.primaryGradient,
              badge: 'Most Popular',
              badgeColor: JanMatTheme.primary,
              onTap: () => _push(context, const AudioScreen()),
            ),
            const SizedBox(height: 14),
            _TypeCard(
              index: 1,
              icon: Icons.edit_note_rounded,
              title: 'Text Message',
              subtitle: 'Type your concern in any language. Our AI extracts the category, location and urgency automatically.',
              gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFF4F8EF7)]),
              badge: 'Quick & Easy',
              badgeColor: Color(0xFF7B2FF7),
              onTap: () => _push(context, const TextScreen()),
            ),
            const SizedBox(height: 14),
            _TypeCard(
              index: 2,
              icon: Icons.camera_alt_rounded,
              title: 'Photo Evidence',
              subtitle: 'Capture a photo of the issue — broken roads, water problems, garbage. Adds visual proof to your report.',
              gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF4D6D)]),
              badge: 'High Impact',
              badgeColor: Color(0xFFFF6B35),
              onTap: () => _push(context, const ImageScreen()),
            ),
            const SizedBox(height: 28),
            _InfoBox(),
            const SizedBox(height: 32),
          ])),
        ),
      ]),
    );
  }
}

class _AppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 100,
      backgroundColor: JanMatTheme.background,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        title: const Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submit a Concern', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
            Text('Choose how you want to report', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title, subtitle;
  final LinearGradient gradient;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _TypeCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: JanMatTheme.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: JanMatTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(16)),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              JMBadge(label: badge, color: badgeColor),
            ])),
            const Icon(Icons.arrow_forward_ios_rounded, color: JanMatTheme.textMuted, size: 16),
          ]),
          const SizedBox(height: 14),
          Text(subtitle, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 13, height: 1.55)),
        ]),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JanMatTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JanMatTheme.primary.withValues(alpha: 0.2)),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_rounded, color: JanMatTheme.primary, size: 20),
        SizedBox(width: 12),
        Expanded(child: Text(
          'Your submissions are encrypted and shared only with your elected representative. They are used to create data-backed development projects.',
          style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 12, height: 1.55),
        )),
      ]),
    );
  }
}
