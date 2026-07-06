import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../theme.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import 'audio_screen.dart';
import 'text_screen.dart';
import 'image_screen.dart';
import 'about_screen.dart';
import 'edit_profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final app = context.read<AppState>();
    if (app.token == null) return;
    try {
      final svc = UserService();
      final data = await svc.getStats(app.token!);
      if (mounted) setState(() { _stats = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AppState>().profile;
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      body: RefreshIndicator(
        color: JanMatTheme.primary,
        backgroundColor: JanMatTheme.surface,
        onRefresh: _loadStats,
        child: CustomScrollView(
          slivers: [
            _HeroHeader(profile: profile),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(delegate: SliverChildListDelegate([
                const SizedBox(height: 20),
                if (_loading)
                  const Center(child: CircularProgressIndicator(color: JanMatTheme.primary))
                else ...[
                  _StatsRow(stats: _stats),
                  const SizedBox(height: 24),
                ],
                _SectionLabel(label: 'Submit a Concern', icon: Icons.campaign_rounded),
                const SizedBox(height: 12),
                _SubmitCards(),
                const SizedBox(height: 24),
                _SectionLabel(label: 'About JanMat', icon: Icons.info_outline_rounded),
                const SizedBox(height: 12),
                _AboutCard(),
                const SizedBox(height: 32),
              ])),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero header ───────────────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final UserProfile? profile;
  const _HeroHeader({this.profile});

  @override
  Widget build(BuildContext context) {
    final greeting = _greeting();
    final name = profile?.name ?? 'Citizen';
    final constituency = profile?.constituency ?? 'Your Constituency';
    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(gradient: JanMatTheme.heroGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.account_balance, color: Colors.white, size: 22),
                const SizedBox(width: 8),
                const Text('JanMat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                const Spacer(),
                _ProfileChip(name: name, profile: profile),
              ]),
              const SizedBox(height: 20),
              Text('$greeting,', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.location_on_rounded, color: Colors.white60, size: 14),
                const SizedBox(width: 4),
                Text(constituency, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}

class _ProfileChip extends StatelessWidget {
  final String name;
  final UserProfile? profile;
  const _ProfileChip({required this.name, this.profile});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showLogoutSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.white.withValues(alpha: 0.3),
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Text(name.split(' ').first, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 16),
        ]),
      ),
    );
  }

  void _showLogoutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: JanMatTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: JanMatTheme.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          // Avatar + name
          CircleAvatar(
            radius: 30,
            backgroundColor: JanMatTheme.primary.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'C',
              style: const TextStyle(color: JanMatTheme.primary, fontSize: 26, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (profile?.phoneNumber != null && profile!.phoneNumber.isNotEmpty)
            Text(profile!.phoneNumber, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          // Info tiles
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: JanMatTheme.card, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              if (profile?.city != null || profile?.state != null)
                _InfoRow(icon: Icons.location_city_rounded, label: 'Location',
                  value: [profile?.city, profile?.state].where((e) => e != null && e.isNotEmpty).join(', ')),
              if (profile?.pinCode != null)
                _InfoRow(icon: Icons.pin_drop_rounded, label: 'PIN Code', value: profile!.pinCode!),
              if (profile?.constituencyId != null)
                _InfoRow(icon: Icons.how_to_vote_rounded, label: 'Constituency', value: profile!.constituencyId!),
              _InfoRow(icon: Icons.campaign_rounded, label: 'Submissions', value: '${profile?.submissionCount ?? 0}'),
            ]),
          ),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: JanMatTheme.card,
            leading: const Icon(Icons.edit_rounded, color: JanMatTheme.primary),
            title: const Text('Edit Profile', style: TextStyle(color: JanMatTheme.textPrimary, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded, color: JanMatTheme.textMuted, size: 18),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: JanMatTheme.card,
            leading: const Icon(Icons.info_outline_rounded, color: JanMatTheme.primary),
            title: const Text('About JanMat', style: TextStyle(color: JanMatTheme.textPrimary, fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded, color: JanMatTheme.textMuted, size: 18),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: JanMatTheme.errorColor.withValues(alpha: 0.08),
            leading: const Icon(Icons.logout_rounded, color: JanMatTheme.errorColor),
            title: const Text('Sign Out', style: TextStyle(color: JanMatTheme.errorColor, fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(context);
              await AuthService().signOut();
              context.read<AppState>().logout();
              if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, '/phone', (_) => false);
            },
          ),
        ]),
      ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, color: JanMatTheme.primary, size: 18),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final Map<String, dynamic>? stats;
  const _StatsRow({this.stats});

  @override
  Widget build(BuildContext context) {
    final total      = stats?['total_submissions'] ?? 0;
    final processed  = stats?['processed'] ?? 0;
    final pending    = stats?['pending'] ?? 0;

    return Row(children: [
      Expanded(child: _StatCard(label: 'Submitted', value: '$total', icon: Icons.send_rounded, color: JanMatTheme.primary)),
      const SizedBox(width: 10),
      Expanded(child: _StatCard(label: 'Processed', value: '$processed', icon: Icons.check_circle_rounded, color: JanMatTheme.accent)),
      const SizedBox(width: 10),
      Expanded(child: _StatCard(label: 'Pending', value: '$pending', icon: Icons.hourglass_empty_rounded, color: JanMatTheme.amber)),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: JanMatTheme.cardBox(),
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 10)),
      ]),
    );
  }
}

// ── Submit quick cards ────────────────────────────────────────────────
class _SubmitCards extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _QuickCard(
        icon: Icons.mic_rounded,
        gradient: JanMatTheme.primaryGradient,
        title: 'Voice Note',
        subtitle: 'Record in any language',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AudioScreen())),
      ),
      const SizedBox(height: 10),
      _QuickCard(
        icon: Icons.edit_rounded,
        gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFF4F8EF7)]),
        title: 'Text Message',
        subtitle: 'Type your concern',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TextScreen())),
      ),
      const SizedBox(height: 10),
      _QuickCard(
        icon: Icons.camera_alt_rounded,
        gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF4D6D)]),
        title: 'Photo Evidence',
        subtitle: 'Capture the issue',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageScreen())),
      ),
    ]);
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final LinearGradient gradient;
  final String title, subtitle;
  final VoidCallback? onTap;

  const _QuickCard({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: JanMatTheme.cardBox(),
        child: Row(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 13)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: JanMatTheme.textMuted),
        ]),
      ),
    );
  }
}

// ── About card ────────────────────────────────────────────────────────
class _AboutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: JanMatTheme.cardBox(),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.verified_rounded, color: JanMatTheme.accent, size: 18),
          SizedBox(width: 8),
          Text('Transparent & Data-Driven', style: TextStyle(color: JanMatTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        SizedBox(height: 10),
        Text(
          'JanMat collects citizen feedback across all languages and converts it into prioritised development projects for your Member of Parliament. Your voice directly shapes infrastructure decisions.',
          style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 13, height: 1.55),
        ),
      ]),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: JanMatTheme.primary, size: 18),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
    ]);
  }
}
