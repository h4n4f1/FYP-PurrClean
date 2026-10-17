import 'package:flutter/material.dart';
import '../theme/app_styles.dart';
import 'analytics_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const int _analyticsTab = 0;
  static const int _homeTab = 1;
  static const int _profileTab = 2;

  int _index = _homeTab;
  int _homeRefreshTick = 0;

  void _onTap(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      if (index == _homeTab) _homeRefreshTick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const AnalyticsScreen(),
          HomeScreen(refreshTick: _homeRefreshTick),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: _BottomNavBar(
        currentIndex: _index,
        onTap: _onTap,
        analyticsIndex: _analyticsTab,
        homeIndex: _homeTab,
        profileIndex: _profileTab,
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.analyticsIndex,
    required this.homeIndex,
    required this.profileIndex,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int analyticsIndex;
  final int homeIndex;
  final int profileIndex;

  @override
  Widget build(BuildContext context) {
    final homeSelected = currentIndex == homeIndex;

    return Material(
      color: Colors.white,
      elevation: 16,
      shadowColor: Colors.black54,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.show_chart_rounded,
                  label: 'Analytics',
                  selected: currentIndex == analyticsIndex,
                  onTap: () => onTap(analyticsIndex),
                ),
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () => onTap(homeIndex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary
                                .withValues(alpha: homeSelected ? 0.5 : 0.25),
                            blurRadius: homeSelected ? 16 : 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.home_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  selected: currentIndex == profileIndex,
                  onTap: () => onTap(profileIndex),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textGrey;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}