import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/user_service.dart';
import 'screens/home_screen.dart';
import 'screens/text_screen.dart';
import 'screens/audio_screen.dart';
import 'screens/image_screen.dart';
import 'screens/status_screen.dart';
import 'screens/heatmap_screen.dart';
import 'screens/auth/phone_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final prefs = await SharedPreferences.getInstance();
  runApp(JanMatApp(prefs: prefs));
}

class JanMatApp extends StatelessWidget {
  final SharedPreferences prefs;
  const JanMatApp({super.key, required this.prefs});

  String get _baseUrl =>
    prefs.getString('api_url') ?? 'https://janmat-backend-poc.a.run.app';

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService(baseUrl: _baseUrl)),
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<UserService>(create: (_) => UserService(baseUrl: _baseUrl)),
        ChangeNotifierProvider(create: (_) => SubmissionState()),
      ],
      child: MaterialApp(
        title: 'JanMat',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1A237E),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0F1B2D),
          fontFamily: 'Roboto',
        ),
        home: const _AuthGate(),
        routes: {
          '/phone':   (ctx) => const PhoneScreen(),
          '/otp':     (ctx) => const OtpScreen(),
          '/profile': (ctx) => const ProfileScreen(),
          '/home':    (ctx) => const HomeScreen(),
          '/text':    (ctx) => const TextSubmissionScreen(),
          '/audio':   (ctx) => const AudioSubmissionScreen(),
          '/image':   (ctx) => const ImageSubmissionScreen(),
          '/status':  (ctx) => const StatusScreen(),
          '/heatmap': (ctx) => const HeatmapScreen(),
        },
      ),
    );
  }
}

/// On cold start: check if session exists → home, else → phone auth
class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final auth = context.read<AuthService>();
    final userSvc = context.read<UserService>();
    if (auth.isLoggedIn && await userSvc.hasStoredSession()) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      Navigator.pushReplacementNamed(context, '/phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F1B2D),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF2196F3))),
    );
  }
}

// ── Global submission state ───────────────────────────────────────────
class SubmissionState extends ChangeNotifier {
  final List<SubmissionRecord> _history = [];
  List<SubmissionRecord> get history => List.unmodifiable(_history);

  void addSubmission(SubmissionRecord record) {
    _history.insert(0, record);
    notifyListeners();
  }
}

class SubmissionRecord {
  final String submissionId;
  final String type; // text | audio | image
  final String category;
  final int urgency;
  final String summary;
  final DateTime submittedAt;

  SubmissionRecord({
    required this.submissionId,
    required this.type,
    required this.category,
    required this.urgency,
    required this.summary,
    required this.submittedAt,
  });
}
