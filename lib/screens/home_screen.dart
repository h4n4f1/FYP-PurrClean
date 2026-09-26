import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme/app_styles.dart';
import '../services/auth_service.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/stat_card.dart';
import 'analytics_screen.dart';
import '../add_cat_page.dart';       // Import your AddCatPage file
import '../cat_list_widget.dart';

/// Placeholder alert model.
/// TODO: Replace with your real model / API response once the backend is ready.
class HealthAlert {
  final String message;
  final String timeAgo;
  const HealthAlert({required this.message, required this.timeAgo});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // Whether the odor-control fan is in Auto or Manual mode.
  // TODO: Wire this up to your backend / device service.
  bool isAutoMode = true;

  // Whether the fan is actively running (only relevant in Manual mode).
  // TODO: Wire this up to your backend / device service.
  bool isFanRunning = false;
  bool isSigningOut = false;
  bool _isEmailVerified = false;

  final _authService = FirebaseAuthService();

  @override
  void initState() {
    super.initState();
    _isEmailVerified = _authService.isEmailVerified;
    WidgetsBinding.instance.addObserver(this);
    _refreshEmailVerification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshEmailVerification();
    }
  }

  Future<void> _refreshEmailVerification() async {
    try {
      await _authService.reloadUser();
    } catch (_) {
      return;
    }
    if (mounted) {
      setState(() => _isEmailVerified = _authService.isEmailVerified);
    }
  }

  // ---------------------------------------------------------------------
  // MOCK DATA — replace all of this once the backend is connected.
  // ---------------------------------------------------------------------
  final String lastVisit = '0 hours ago';
  final String todaysVisits = '0';
  final String wasteLevel = '0%';
  final String airQualityStatus = 'Moderate';

  final int ammoniaPpm = 0;
  final int ammoniaMaxPpm = 0;
  final int co2Ppm = 0;
  final int co2MaxPpm = 0;
  final int autoActivationThresholdPpm = 0;

  final String fanName = 'DC Brushless Fan';

  /// TODO: Replace with live device status from the backend.
  String get fanStatusText => isFanRunning ? 'Running' : 'Stopped';

  final List<HealthAlert> alerts = const [
    HealthAlert(
      message: '',
      timeAgo: '0h ago',
    ),
    HealthAlert(
      message: '', 
      timeAgo: '0h ago',),
  ];
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Get the current user's unique ID from Firebase Auth.
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              if (!_isEmailVerified) _buildEmailVerificationNotice(),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Text(
                  'My Cats',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              // Show the current user's cats from Firestore.
              CatListWidget(userId: currentUserId),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildWelcomeCard(),
                    const SizedBox(height: 18),
                    _buildHealthAlertsCard(),
                    const SizedBox(height: 18),
                    _buildStatsGrid(),
                    const SizedBox(height: 18),
                    _buildAirQualityMonitoringCard(),
                    const SizedBox(height: 18),
                    _buildOdorControlCard(),
                    const SizedBox(height: 18),
                    _buildBottomNavRow(),
                    const SizedBox(height: 16),
                    _buildLogoutButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddCatPage(userId: currentUserId),
            ),
          );
        },
        backgroundColor: const Color(0xFFFF8A00),
        tooltip: 'Add Cat Profile',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmailVerificationNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.mark_email_unread_outlined,
            color: Colors.red,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Please verify your email. Check your inbox or spam folder for the verification email.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.red.shade800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Header ---------------------------------------------------------

  Widget _buildHeader() {
    return ClipRRect(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Decorative background circles.
            Positioned(
              top: -30,
              right: -40,
              child: _decorCircle(150, Colors.white.withValues(alpha: 0.08)),
            ),
            Positioned(
              top: 40,
              right: 30,
              child: _decorCircle(90, Colors.white.withValues(alpha: 0.10)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PurrClean',
                        style: TextStyle(
                          fontFamily: 'ComicRelief',
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your personal litter box assistant',
                        style: TextStyle(
                          fontFamily: 'ComicRelief',
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(1),
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _decorCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  // -- Welcome card -----------------------------------------------------

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppDecorations.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    fontFamily: 'ComicRelief',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  // TODO: Replace with a real health summary from the backend.
                  "Your cat's health is looking great today!",
                  style: TextStyle(
                    fontFamily: 'ComicRelief',
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(1),
            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
          ),
        ],
      ),
    );
  }

  // -- Health alerts ----------------------------------------------------

  Widget _buildHealthAlertsCard() {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            icon: Icons.error_outline,
            iconBg: AppColors.iconBgOrange,
            iconColor: AppColors.primary,
            title: 'Health Alerts',
          ),
          const SizedBox(height: 18),
          if (alerts.isEmpty)
            Text(
              'No alerts right now — everything looks good!',
              style: TextStyle(color: Colors.grey.shade600),
            )
          else
            Column(
              children: [
                for (int i = 0; i < alerts.length; i++) ...[
                  _buildAlertRow(alerts[i]),
                  if (i != alerts.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAlertRow(HealthAlert alert) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.notifications_none_rounded,
          color: AppColors.alertBell,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                alert.message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(alert.timeAgo, style: AppTextStyles.timestamp),
            ],
          ),
        ),
      ],
    );
  }

  // -- Stats grid ---------------------------------------------------------

  Widget _buildStatsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.access_time_rounded,
                iconBg: AppColors.iconBgOrange,
                iconColor: AppColors.primary,
                label: 'Last Visit',
                value: lastVisit,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                icon: Icons.people_alt_outlined,
                iconBg: AppColors.iconBgYellow,
                iconColor: AppColors.moderatePillText,
                label: "Today's Visits",
                value: todaysVisits,
                trailing: const Icon(
                  Icons.trending_down_rounded,
                  color: AppColors.successGreen,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.inventory_2_outlined,
                iconBg: AppColors.iconBgYellow,
                iconColor: AppColors.moderatePillText,
                label: 'Waste Level',
                value: wasteLevel,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: StatCard(
                icon: Icons.air_rounded,
                iconBg: AppColors.iconBgYellow,
                iconColor: AppColors.moderatePillText,
                label: 'Air Quality',
                valueWidget: StatusPill(
                  label: airQualityStatus,
                  background: AppColors.moderatePillBg,
                  textColor: AppColors.moderatePillText,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // -- Air quality monitoring --------------------------------------------

  Widget _buildAirQualityMonitoringCard() {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            icon: Icons.bar_chart_rounded,
            iconBg: AppColors.iconBgBlue,
            iconColor: AppColors.infoBlue,
            title: 'Air Quality Monitoring',
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overall Status',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      label: airQualityStatus,
                      background: AppColors.moderatePillBg,
                      textColor: AppColors.moderatePillText,
                    ),
                  ],
                ),
              ),
              const RoundIcon(
                icon: Icons.thumb_up_alt_outlined,
                background: AppColors.moderatePillBg,
                iconColor: AppColors.moderatePillText,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _buildMetricBar(
            label: 'Ammonia',
            valuePpm: ammoniaPpm,
            maxPpm: ammoniaMaxPpm,
            color: AppColors.infoBlue,
          ),
          const SizedBox(height: 18),
          _buildMetricBar(
            label: 'Carbon Dioxide',
            valuePpm: co2Ppm,
            maxPpm: co2MaxPpm,
            color: AppColors.successGreen,
          ),
          const SizedBox(height: 18),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Auto-activation threshold',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              Text(
                '$autoActivationThresholdPpm PPM',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBar({
    required String label,
    required int valuePpm,
    required int maxPpm,
    required Color color,
  }) {
    final progress = (valuePpm / maxPpm).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$valuePpm PPM',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppColors.barTrack,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  // -- Automated odor control ---------------------------------------------

  Widget _buildOdorControlCard() {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            icon: Icons.air_rounded,
            iconBg: AppColors.iconBgOrange,
            iconColor: AppColors.primary,
            title: 'Automated Odor Control',
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const RoundIcon(
                icon: Icons.air_rounded,
                background: AppColors.iconBgOrange,
                iconColor: AppColors.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fanName, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 2),
                    Text(
                      fanStatusText,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: isAutoMode ? 'Auto Mode' : 'Manual',
                background: isAutoMode
                    ? AppColors.iconBgBlue
                    : AppColors.manualPillBg,
                textColor: isAutoMode
                    ? AppColors.infoBlue
                    : AppColors.manualPillText,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildModeToggle(),
          if (!isAutoMode) ...[
            const SizedBox(height: 12),
            _buildFanControlButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.toggleTrack,
        borderRadius: AppDecorations.toggleRadius,
      ),
      child: Row(
        children: [
          Expanded(child: _modeButton('Auto', isAutoMode)),
          Expanded(child: _modeButton('Manual', !isAutoMode)),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool selected) {
    final gradient = label == 'Auto'
        ? AppColors.fanGradient
        : AppColors.manualGradient;
    return GestureDetector(
      onTap: () {
        // TODO: Send the selected mode to the fan / device service.
        setState(() => isAutoMode = label == 'Auto');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: selected ? gradient : null,
          borderRadius: AppDecorations.toggleButtonRadius,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: selected
              ? AppTextStyles.toggleLabelActive
              : AppTextStyles.toggleLabelInactive,
        ),
      ),
    );
  }

  Widget _buildFanControlButton() {
    return GestureDetector(
      onTap: () {
        // TODO: Send a start/stop command to the fan / device service.
        setState(() => isFanRunning = !isFanRunning);
      },
      child: Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: isFanRunning
              ? AppColors.stopGradient
              : AppColors.startGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          isFanRunning ? 'Stop Fan' : 'Start Fan',
          style: AppTextStyles.buttonLabel,
        ),
      ),
    );
  }

  // -- Bottom navigation row -----------------------------------------------

  Widget _buildBottomNavRow() {
    return Row(
      children: [
        Expanded(
          child: _buildNavCard(
            icon: Icons.show_chart_rounded,
            iconBg: AppColors.iconBgOrange,
            iconColor: AppColors.primary,
            label: 'Analytics',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildNavCard(
            icon: Icons.person_outline_rounded,
            iconBg: AppColors.iconBgYellow,
            iconColor: AppColors.moderatePillText,
            label: 'Profile',
            onTap: () => _showProfileModal(context),
          ),
        ),
      ],
    );
  }

  Future<void> _showProfileModal(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ProfileBottomSheet(),
    );
    await _refreshEmailVerification();
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: isSigningOut ? null : _handleLogout,
        icon: isSigningOut
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout_rounded),
        label: Text(isSigningOut ? 'Signing out...' : 'Log out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: AppDecorations.buttonRadius,
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    setState(() => isSigningOut = true);
    try {
      await _authService.signOut();
    } catch (_) {
      if (!mounted) return;
      setState(() => isSigningOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please try again.')),
      );
    }
  }

  Widget _buildNavCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: DashboardCard(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            RoundIcon(icon: icon, background: iconBg, iconColor: iconColor),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBottomSheet extends StatefulWidget {
  const _ProfileBottomSheet();

  @override
  State<_ProfileBottomSheet> createState() => _ProfileBottomSheetState();
}

class _ProfileBottomSheetState extends State<_ProfileBottomSheet> {
  final _authService = FirebaseAuthService();
  bool _isSendingVerification = false;
  bool _isLinkingGoogle = false;
  bool _isCheckingVerification = false;

  @override
  void initState() {
    super.initState();
    _refreshUser();
  }

  Future<void> _refreshUser() async {
    setState(() => _isCheckingVerification = true);
    await _authService.reloadUser();
    if (mounted) {
      setState(() => _isCheckingVerification = false);
    }
  }

  Future<void> _handleSendVerification() async {
    setState(() => _isSendingVerification = true);
    final result = await _authService.sendEmailVerification();
    if (!mounted) return;
    setState(() => _isSendingVerification = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Verification email sent! Check your inbox or spam folder.'
              : (result.errorMessage ?? 'Failed to send verification email.'),
        ),
      ),
    );
  }

  Future<void> _handleLinkGoogle() async {
    setState(() => _isLinkingGoogle = true);
    final result = await _authService.linkWithGoogle();
    if (!mounted) return;
    setState(() => _isLinkingGoogle = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'Google account successfully linked!'
              : (result.errorMessage ?? 'Google account linking failed.'),
        ),
      ),
    );
    if (result.success) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final isVerified = _authService.isEmailVerified;
    final isGoogleLinked = _authService.isGoogleLinked;
    final email = user?.email ?? 'No email available';
    final displayName = user?.displayName ?? 'PurrClean User';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Profile Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.iconBgOrange,
                    child: Image.asset('assets/images/logo.png', width: 36, height: 36),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isNotEmpty ? displayName : 'PurrClean User',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),

              // Section: Email Verification
              const Text(
                'Email Verification',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isVerified
                      ? const Color(0xFFE8F8EE)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isVerified
                        ? const Color(0xFF3EBD6A).withValues(alpha: 0.3)
                        : AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isVerified
                              ? Icons.verified_rounded
                              : Icons.warning_amber_rounded,
                          color: isVerified
                              ? const Color(0xFF3EBD6A)
                              : AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isVerified ? 'Email Verified' : 'Email Not Verified',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isVerified
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC2410C),
                          ),
                        ),
                        const Spacer(),
                        if (!isVerified)
                          InkWell(
                            onTap: _isCheckingVerification ? null : _refreshUser,
                            child: _isCheckingVerification
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh, size: 18, color: Colors.grey),
                          ),
                      ],
                    ),
                    if (!isVerified) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Verify your email to keep your account secure and prevent losing access.',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _isSendingVerification ? null : _handleSendVerification,
                          icon: _isSendingVerification
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 16),
                          label: const Text('Resend Verification Email'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Section: Account Linking
              const Text(
                'Linked Accounts',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),

              // Email / Password Provider Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined, color: AppColors.textDark, size: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Email & Password',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Active',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Google Provider Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Image.asset('assets/images/google_logo.png', width: 22, height: 22),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Google Sign-In',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    if (isGoogleLinked)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Linked',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ElevatedButton(
                        onPressed: _isLinkingGoogle ? null : _handleLinkGoogle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLinkingGoogle
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Link Google',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}