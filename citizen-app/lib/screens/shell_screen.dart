import 'package:flutter/material.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'submit_screen.dart';
import 'history_screen.dart';
import 'heatmap_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _tab = 0;

  static const _labels = ['Home', 'Submit', 'My Reports', 'Heatmap'];
  static const _icons  = [Icons.home_rounded, Icons.add_circle_outline_rounded,
                           Icons.receipt_long_rounded, Icons.map_rounded];
  static const _activeIcons = [Icons.home_rounded, Icons.add_circle_rounded,
                                Icons.receipt_long_rounded, Icons.map_rounded];

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      SubmitScreen(onTabChange: (i) => setState(() => _tab = i)),
      const HistoryScreen(),
      const HeatmapScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: _BottomNav(
        selected: _tab,
        labels: _labels,
        icons: _icons,
        activeIcons: _activeIcons,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

// ── Custom bottom nav bar ──────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int selected;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> activeIcons;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.selected,
    required this.labels,
    required this.icons,
    required this.activeIcons,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JanMatTheme.surface,
        border: const Border(top: BorderSide(color: JanMatTheme.border, width: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: List.generate(labels.length, (i) {
              final active = i == selected;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (active)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: JanMatTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(activeIcons[i], color: Colors.white, size: 22),
                          )
                        else
                          Icon(icons[i], color: JanMatTheme.textMuted, size: 22),
                        const SizedBox(height: 4),
                        Text(
                          labels[i],
                          style: TextStyle(
                            color: active ? JanMatTheme.primary : JanMatTheme.textMuted,
                            fontSize: 10,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
