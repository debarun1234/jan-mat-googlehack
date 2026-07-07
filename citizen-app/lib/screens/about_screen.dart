import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JanMatTheme.background,
      appBar: AppBar(
        backgroundColor: JanMatTheme.background,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
        title: const Text('About JanMat'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Hero ──────────────────────────────────────────────────────
          _HeroBanner(),
          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Capabilities ─────────────────────────────────────────
              _SectionTitle(title: 'What JanMat Does', icon: Icons.auto_awesome_rounded),
              const SizedBox(height: 12),
              _CapabilityCard(
                icon: Icons.mic_rounded,
                gradient: JanMatTheme.primaryGradient,
                title: 'Voice Submissions',
                body: 'Record concerns in any language — Hindi, Kannada, Tamil, Telugu, Bengali, or English. AI transcribes and translates automatically.',
              ),
              const SizedBox(height: 10),
              _CapabilityCard(
                icon: Icons.translate_rounded,
                gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFF4F8EF7)]),
                title: 'Multilingual AI Engine',
                body: 'Powered by Google Gemini & Cloud Translation. Every submission is analysed for category, urgency (1–5), and extracted as a structured grievance — regardless of input language.',
              ),
              const SizedBox(height: 10),
              _CapabilityCard(
                icon: Icons.camera_alt_rounded,
                gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF4D6D)]),
                title: 'Photo Evidence',
                body: 'Upload photos of broken roads, water leaks, garbage, or any civic issue. Gemini Vision analyses the image and extracts a structured report.',
              ),
              const SizedBox(height: 10),
              _CapabilityCard(
                icon: Icons.location_on_rounded,
                gradient: const LinearGradient(colors: [Color(0xFF00D4AA), Color(0xFF4F8EF7)]),
                title: 'GPS Geotagging',
                body: 'Every submission is tagged with your precise GPS coordinates. This powers the demand heatmap and ensures issues are correctly mapped to your constituency.',
              ),
              const SizedBox(height: 10),
              _CapabilityCard(
                icon: Icons.map_rounded,
                gradient: const LinearGradient(colors: [Color(0xFF4F8EF7), Color(0xFF00D4AA)]),
                title: 'Live Demand Heatmap',
                body: 'See aggregated issue hotspots across your constituency. Filter by category — roads, water, health, education, sanitation — to understand where demand is highest.',
              ),

              const SizedBox(height: 28),

              // ── How it works ──────────────────────────────────────────
              _SectionTitle(title: 'How It Works', icon: Icons.account_tree_rounded),
              const SizedBox(height: 12),
              _HowItWorksCard(),

              const SizedBox(height: 28),

              // ── Backed by ─────────────────────────────────────────────
              _SectionTitle(title: 'Powered By', icon: Icons.cloud_rounded),
              const SizedBox(height: 12),
              _TechStack(),

              const SizedBox(height: 28),

              // ── App Update ────────────────────────────────────────────
              _SectionTitle(title: 'App Update', icon: Icons.system_update_alt_rounded),
              const SizedBox(height: 12),
              const _UpdateCheckerCard(),

              const SizedBox(height: 28),

              // ── Terms & Conditions ────────────────────────────────────
              _SectionTitle(title: 'Legal', icon: Icons.gavel_rounded),
              const SizedBox(height: 12),
              _ExpandableSection(
                title: 'Terms & Conditions',
                icon: Icons.description_rounded,
                content: _kTerms,
              ),
              const SizedBox(height: 10),
              _ExpandableSection(
                title: 'Privacy Policy',
                icon: Icons.privacy_tip_rounded,
                content: _kPrivacy,
              ),

              const SizedBox(height: 32),

              // ── Footer ────────────────────────────────────────────────
              Center(
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: JanMatTheme.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: JanMatTheme.border),
                    ),
                    child: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (_, snap) => Text(
                        'Version ${snap.data?.version ?? '1.0.0'}',
                        style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('© 2025 JanMat. All rights reserved.', style: TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
                  const SizedBox(height: 4),
                  const Text('Built for Google AI Hackathon — Track 1', style: TextStyle(color: JanMatTheme.textMuted, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 32),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Hero Banner ────────────────────────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: JanMatTheme.heroGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.account_balance, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            const Text('JanMat', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 1)),
            const SizedBox(height: 6),
            const Text('Voice of the People', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Text(
                'AI-powered citizen-to-MP grievance pipeline',
                style: TextStyle(color: Colors.white, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Section title ──────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: JanMatTheme.primary, size: 18),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
    ]);
  }
}

// ── Capability card ────────────────────────────────────────────────────
class _CapabilityCard extends StatelessWidget {
  final IconData icon;
  final LinearGradient gradient;
  final String title, body;
  const _CapabilityCard({required this.icon, required this.gradient, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: JanMatTheme.cardBox(),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 12, height: 1.55)),
        ])),
      ]),
    );
  }
}

// ── How it works ───────────────────────────────────────────────────────
class _HowItWorksCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: JanMatTheme.cardBox(),
      child: Column(children: [
        _Step(num: '1', color: JanMatTheme.primary,   icon: Icons.campaign_rounded,   title: 'Citizen Submits',  body: 'Voice, text, or photo — in any language, with GPS location.'),
        _Connector(),
        _Step(num: '2', color: const Color(0xFF7B2FF7), icon: Icons.psychology_rounded, title: 'AI Processes',    body: 'Gemini extracts category, urgency, and structured data. Translated to English.'),
        _Connector(),
        _Step(num: '3', color: JanMatTheme.accent,    icon: Icons.bar_chart_rounded,  title: 'MP Dashboard',     body: 'Aggregated hotspots, ranked projects, and evidence logs reach the MP for action.'),
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  final String num, title, body;
  final Color color;
  final IconData icon;
  const _Step({required this.num, required this.color, required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: color.withValues(alpha: 0.4))),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(body, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 12, height: 1.5)),
      ])),
    ]);
  }
}

class _Connector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 17, top: 4, bottom: 4),
      child: Container(width: 2, height: 20, color: JanMatTheme.border),
    );
  }
}

// ── Tech stack ────────────────────────────────────────────────────────
class _TechStack extends StatelessWidget {
  static const _items = [
    ('Google Gemini', Icons.auto_awesome_rounded, Color(0xFF4F8EF7)),
    ('Cloud Run', Icons.cloud_rounded, Color(0xFF00D4AA)),
    ('AlloyDB', Icons.storage_rounded, Color(0xFF7B2FF7)),
    ('Firebase Auth', Icons.security_rounded, Color(0xFFFF6B35)),
    ('Google Maps', Icons.map_rounded, Color(0xFF4F8EF7)),
    ('Cloud Speech', Icons.record_voice_over_rounded, Color(0xFF00D4AA)),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10, runSpacing: 10,
      children: _items.map((t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: t.$3.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.$3.withValues(alpha: 0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(t.$2, color: t.$3, size: 15),
          const SizedBox(width: 6),
          Text(t.$1, style: TextStyle(color: t.$3, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      )).toList(),
    );
  }
}

// ── Expandable section ────────────────────────────────────────────────
class _ExpandableSection extends StatefulWidget {
  final String title, content;
  final IconData icon;
  const _ExpandableSection({required this.title, required this.content, required this.icon});

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: JanMatTheme.cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(widget.icon, color: JanMatTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(widget.title, style: const TextStyle(color: JanMatTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700))),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down_rounded, color: JanMatTheme.textMuted),
              ),
            ]),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(widget.content,
              style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 12, height: 1.7)),
          ),
      ]),
    );
  }
}

// ── Legal content ─────────────────────────────────────────────────────
const _kTerms = '''
1. Acceptance
By using JanMat, you agree to these Terms. If you disagree, do not use the app.

2. Purpose
JanMat is a civic engagement platform for Indian citizens to submit grievances to their elected Member of Parliament (MP). Submissions are processed by AI and forwarded to the relevant constituency dashboard.

3. User Responsibilities
You must provide accurate information. False, misleading, or abusive submissions are prohibited. You must be a resident of the constituency you are submitting from.

4. Location Data
GPS location is mandatory for each submission. This is used solely to map your concern to the correct constituency and to identify geographic demand clusters. Location data is never shared with third parties.

5. Content
You retain ownership of your submissions. By submitting, you grant JanMat a non-exclusive licence to process, aggregate, and display your submission (in anonymised form) to MPs and public dashboards.

6. Prohibited Use
You may not use JanMat to submit spam, political propaganda, defamatory content, or content that violates Indian law.

7. Disclaimer
JanMat does not guarantee that your MP will act on any submission. The platform facilitates communication; actual project delivery is the MP\'s responsibility.

8. Changes
We may update these Terms at any time. Continued use constitutes acceptance.''';

const _kPrivacy = '''
1. Data We Collect
• Phone number (Firebase OTP authentication only)
• Name, city, state, PIN code (profile setup)
• Submission content: voice, text, or photo
• GPS coordinates at time of submission
• Submission timestamps and device metadata

2. How We Use Your Data
• To authenticate your identity via phone OTP
• To map submissions to your constituency
• To power the AI grievance pipeline (Gemini processing)
• To generate anonymised heatmaps for MP dashboards
• To show your submission history in-app

3. Data Storage
All data is stored on Google Cloud Platform (AlloyDB, Cloud Storage) within India regions. Audio and image files are retained in Google Cloud Storage with strict access controls.

4. Third-Party Services
We use Google services: Firebase Authentication, Cloud Run, AlloyDB, Gemini AI, Cloud Speech-to-Text, Cloud Translation, and Google Maps. Each is governed by Google\'s Privacy Policy.

5. Data Sharing
We do not sell your personal data. Submissions are shared (in aggregated, anonymised form) with your constituency\'s MP dashboard. Personal identifiers (name, phone) are never exposed to MPs.

6. Your Rights
You may request deletion of your account and all associated data by contacting us. You may view your submission history at any time within the app.

7. Security
All data in transit is encrypted via HTTPS/TLS. Data at rest is encrypted using Google-managed keys. Firebase Phone Auth ensures only verified users can submit.

8. Contact
For privacy concerns, contact: privacy@janmat.in''';

// ── Update Checker ─────────────────────────────────────────────────────
enum _UpdateState { checking, upToDate, available, downloading, error }

class _UpdateCheckerCard extends StatefulWidget {
  const _UpdateCheckerCard();

  @override
  State<_UpdateCheckerCard> createState() => _UpdateCheckerCardState();
}

class _UpdateCheckerCardState extends State<_UpdateCheckerCard> {
  static const _kApiUrl =
      'https://api.github.com/repos/debarun1234/jan-mat-googlehack/releases/latest';

  _UpdateState _state = _UpdateState.checking;
  String _latestVersion = '';
  String _downloadUrl = '';
  double? _progress;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  String _strip(String tag) => tag.startsWith('v') ? tag.substring(1) : tag;

  bool _isNewer(String latest, String current) {
    try {
      List<int> p(String v) => v.split('.').map(int.parse).toList();
      final l = p(latest);
      final c = p(current);
      for (var i = 0; i < 3; i++) {
        final lv = i < l.length ? l[i] : 0;
        final cv = i < c.length ? c[i] : 0;
        if (lv > cv) return true;
        if (lv < cv) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() { _state = _UpdateState.checking; _error = ''; });
    try {
      final info = await PackageInfo.fromPlatform();
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
      final resp = await dio.get(
        _kApiUrl,
        options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}),
      );

      final tag = (resp.data['tag_name'] as String?) ?? '';
      _latestVersion = _strip(tag);

      final assets = (resp.data['assets'] as List?) ?? [];
      final apk = assets.cast<Map>().firstWhere(
        (a) => (a['name'] as String? ?? '').endsWith('.apk'),
        orElse: () => <String, dynamic>{},
      );
      _downloadUrl = (apk['browser_download_url'] as String?) ?? '';

      if (_latestVersion.isEmpty) {
        setState(() { _state = _UpdateState.error; _error = 'No release found on GitHub.'; });
        return;
      }
      setState(() {
        _state = _isNewer(_latestVersion, info.version)
            ? _UpdateState.available
            : _UpdateState.upToDate;
      });
    } catch (_) {
      setState(() { _state = _UpdateState.error; _error = 'Could not reach GitHub. Check connection.'; });
    }
  }

  Future<void> _download() async {
    if (_downloadUrl.isEmpty) {
      setState(() { _state = _UpdateState.error; _error = 'No APK asset found in this release.'; });
      return;
    }

    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        setState(() {
          _state = _UpdateState.error;
          _error = 'Permission denied. Enable "Install unknown apps" in Settings.';
        });
        return;
      }
    }

    setState(() { _state = _UpdateState.downloading; _progress = 0; });

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/janmat_v$_latestVersion.apk';

      await Dio().download(
        _downloadUrl,
        path,
        onReceiveProgress: (recv, total) {
          if (mounted && total > 0) setState(() => _progress = recv / total);
        },
      );

      final result = await OpenFile.open(path);
      if (result.type != ResultType.done) {
        setState(() { _state = _UpdateState.error; _error = result.message; });
      } else {
        // Installer is open — keep showing "available" in case user dismisses
        setState(() => _state = _UpdateState.available);
      }
    } catch (e) {
      setState(() {
        _state = _UpdateState.error;
        _error = 'Download failed: ${e.toString().split('\n').first}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: JanMatTheme.cardBox(),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _UpdateState.checking:
        return _UpdateRow(
          leading: const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(JanMatTheme.primary),
            ),
          ),
          label: 'Checking for updates…',
          sub: 'Connecting to GitHub releases',
          labelColor: JanMatTheme.textPrimary,
        );

      case _UpdateState.upToDate:
        return _UpdateRow(
          leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF00D4AA), size: 20),
          label: 'You\'re up to date',
          sub: 'v$_latestVersion is the latest release',
          labelColor: const Color(0xFF00D4AA),
          trailing: TextButton(
            onPressed: _check,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Re-check', style: TextStyle(fontSize: 12, color: JanMatTheme.primary)),
          ),
        );

      case _UpdateState.available:
        return _UpdateRow(
          leading: const Icon(Icons.system_update_alt_rounded, color: Color(0xFFFF6B35), size: 20),
          label: 'Update available — v$_latestVersion',
          sub: 'Tap to download and install',
          labelColor: const Color(0xFFFF6B35),
          trailing: ElevatedButton.icon(
            onPressed: _download,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Update'),
            style: ElevatedButton.styleFrom(
              backgroundColor: JanMatTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        );

      case _UpdateState.downloading:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.downloading_rounded, color: JanMatTheme.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Downloading update…',
                  style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                _progress != null
                    ? '${(_progress! * 100).toStringAsFixed(0)}%  —  v$_latestVersion'
                    : 'Starting…',
                style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 11),
              ),
            ])),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: JanMatTheme.border,
              valueColor: const AlwaysStoppedAnimation<Color>(JanMatTheme.primary),
            ),
          ),
        ]);

      case _UpdateState.error:
        return _UpdateRow(
          leading: const Icon(Icons.error_outline_rounded, color: Color(0xFFFF4D6D), size: 20),
          label: 'Update check failed',
          sub: _error,
          labelColor: const Color(0xFFFF4D6D),
          trailing: TextButton(
            onPressed: _check,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Retry', style: TextStyle(fontSize: 12, color: JanMatTheme.primary)),
          ),
        );
    }
  }
}

class _UpdateRow extends StatelessWidget {
  final Widget leading;
  final String label, sub;
  final Color labelColor;
  final Widget? trailing;

  const _UpdateRow({
    required this.leading,
    required this.label,
    required this.sub,
    required this.labelColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      leading,
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: JanMatTheme.textSecondary, fontSize: 11, height: 1.4)),
        if (trailing != null) ...[const SizedBox(height: 8), trailing!],
      ])),
    ]);
  }
}
