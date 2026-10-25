import 'dart:async';

import 'package:flutter/material.dart';
import '../services/device_status_service.dart';
import '../theme/app_styles.dart';
import '../widgets/device_status_banner.dart';
import 'analytics_screen.dart';
import 'device_setup_screen.dart';
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

  StreamSubscription<DeviceLinkStatus>? _statusSub;
  DeviceLinkStatus _status = DeviceLinkStatus.unknown;

  /// Last status that needed a banner (kept so the card can fade out nicely).
  DeviceLinkStatus _lastBannerStatus = DeviceLinkStatus.notSetUp;

  /// Status the user dismissed the banner for (re-shows if status changes).
  DeviceLinkStatus? _dismissedStatus;

  @override
  void initState() {
    super.initState();
    _watchStatus();
  }

  /// (Re)starts listening to the ESP32 status. Called again after the user
  /// finishes Wi-Fi setup, because the saved device may have changed.
  void _watchStatus() {
    _statusSub?.cancel();
    _statusSub = DeviceStatusService.instance.watchStatus().listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  Future<void> _openDeviceSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => DeviceSetupScreen(
          showBackButton: true,
          onComplete: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
    if (mounted) _watchStatus();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  void _onTap(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      if (index == _homeTab) _homeRefreshTick++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bannerVisible =
        DeviceStatusBanner.isVisibleFor(_status) && _dismissedStatus != _status;
    if (DeviceStatusBanner.isVisibleFor(_status)) _lastBannerStatus = _status;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _index,
              children: [
                const RepaintBoundary(child: AnalyticsScreen()),
                RepaintBoundary(
                  child: HomeScreen(refreshTick: _homeRefreshTick),
                ),
                const RepaintBoundary(child: ProfileScreen()),
              ],
            ),
          ),
          // Compact floating device status card (doesn't touch the headers)
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: IgnorePointer(
              ignoring: !bannerVisible,
              child: AnimatedSlide(
                offset: bannerVisible ? Offset.zero : const Offset(0, 0.4),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: bannerVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: DeviceStatusBanner(
                    status: _lastBannerStatus,
                    onPressed: _openDeviceSetup,
                    onDismiss: () =>
                        setState(() => _dismissedStatus = _status),
                  ),
                ),
              ),
            ),
          ),
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
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(homeIndex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(
                              alpha: homeSelected ? 0.5 : 0.25,
                            ),
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(height: 3),
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
