// JanMat Design System — shared colors, gradients, text styles
import 'package:flutter/material.dart';

class JanMatTheme {
  // ── Brand colors ─────────────────────────────────────────────────
  static const Color background   = Color(0xFF080D1A);
  static const Color surface      = Color(0xFF111827);
  static const Color card         = Color(0xFF1C2539);
  static const Color cardHover    = Color(0xFF222D44);
  static const Color border       = Color(0xFF2A3555);

  static const Color primary      = Color(0xFF4F8EF7);
  static const Color primaryDark  = Color(0xFF1A237E);
  static const Color accent       = Color(0xFF00D4AA);
  static const Color amber        = Color(0xFFFFC107);
  static const Color errorColor   = Color(0xFFFF4D6D);

  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8899BB);
  static const Color textMuted     = Color(0xFF4A5878);

  // Category colors
  static const Map<String, Color> catColors = {
    'Roads':      Color(0xFFFF6B35),
    'Water':      Color(0xFF00B4D8),
    'Health':     Color(0xFFFF4D6D),
    'Education':  Color(0xFF4F8EF7),
    'Sanitation': Color(0xFF9B59B6),
    'Other':      Color(0xFF78909C),
  };

  // ── Gradients ─────────────────────────────────────────────────────
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A237E), Color(0xFF1565C0), Color(0xFF0288D1)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4F8EF7), Color(0xFF1565C0)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFF00D4AA), Color(0xFF0288D1)],
  );

  // ── Theme ─────────────────────────────────────────────────────────
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: errorColor,
      ),
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  // ── Shared decorations ────────────────────────────────────────────
  static BoxDecoration cardBox({Color? color, double radius = 16}) => BoxDecoration(
    color: color ?? card,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border),
  );

  static BoxDecoration glassBox({double radius = 16}) => BoxDecoration(
    color: card.withValues(alpha: 0.6),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border.withValues(alpha: 0.5)),
  );
}

// ── Shared widgets ─────────────────────────────────────────────────
class JMBadge extends StatelessWidget {
  final String label;
  final Color color;
  const JMBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class JMButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final LinearGradient? gradient;
  final bool outlined;

  const JMButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.gradient,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(
        width: double.infinity, height: 52,
        child: OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: JanMatTheme.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label, style: const TextStyle(color: JanMatTheme.primary, fontWeight: FontWeight.w700)),
        ),
      );
    }
    return SizedBox(
      width: double.infinity, height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient ?? JanMatTheme.primaryGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: loading
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
        ),
      ),
    );
  }
}
