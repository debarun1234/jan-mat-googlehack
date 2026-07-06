import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';
import 'services/user_service.dart';
import 'screens/shell_screen.dart';
import 'screens/auth/phone_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: JanMatTheme.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const JanMatApp());
}

class JanMatApp extends StatelessWidget {
  const JanMatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
      ],
      child: MaterialApp(
        title: 'JanMat',
        debugShowCheckedModeBanner: false,
        theme: JanMatTheme.dark,
        home: const _AuthGate(),
        routes: {
          '/phone':   (_) => const PhoneScreen(),
          '/otp':     (_) => const OtpScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/home':    (_) => const ShellScreen(),
        },
      ),
    );
  }
}

// ── App state ──────────────────────────────────────────────────────────
class AppState extends ChangeNotifier {
  String? _token;
  UserProfile? _profile;
  bool _loading = false;

  String? get token    => _token;
  UserProfile? get profile => _profile;
  bool get loading     => _loading;
  bool get isAuth      => _token != null;

  void setToken(String t) { _token = t; notifyListeners(); }
  void setProfile(UserProfile p) { _profile = p; notifyListeners(); }

  void logout() {
    _token   = null;
    _profile = null;
    notifyListeners();
  }

  Future<void> restoreSession() async {
    _loading = true; notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final tok = prefs.getString('janmat_token');
      if (tok != null) {
        _token = tok;
        final us = UserService();
        _profile = await us.getProfile(tok);
      }
    } catch (_) {}
    _loading = false; notifyListeners();
  }
}

// ── Auth gate ──────────────────────────────────────────────────────────
class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final app = context.read<AppState>();
    await app.restoreSession();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Logo(),
              SizedBox(height: 32),
              CircularProgressIndicator(color: JanMatTheme.primary),
            ],
          ),
        ),
      );
    }
    return Consumer<AppState>(
      builder: (_, app, __) => app.isAuth ? const ShellScreen() : const PhoneScreen(),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          gradient: JanMatTheme.heroGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: JanMatTheme.primary.withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 2)],
        ),
        child: const Icon(Icons.account_balance, color: Colors.white, size: 40),
      ),
      const SizedBox(height: 16),
      const Text('JanMat', style: TextStyle(color: JanMatTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      const SizedBox(height: 4),
      const Text('Voice of the People', style: TextStyle(color: JanMatTheme.textSecondary, fontSize: 13)),
    ]);
  }
}
