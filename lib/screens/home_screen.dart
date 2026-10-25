import 'package:flutter/material.dart';
import '../theme/app_styles.dart';
import '../services/auth_service.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/stat_card.dart';

/// Placeholder alert model.
/// TODO: Replace with your real model / API response once the backend is ready.
class HealthAlert {
  final String message;
  final String timeAgo;
  const HealthAlert({required this.message, required this.timeAgo});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.refreshTick = 0});

  /// Changes whenever the user switches back to the Home tab.
  final int refreshTick;

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
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _refreshEmailVerification();
    }
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
      timeAgo: '0h ago',
    ),
  ];
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
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
                  ],
                ),
              ),
            ],
          ),
        ),
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
    final progress = maxPpm > 0 ? (valuePpm / maxPpm).clamp(0.0, 1.0) : 0.0;
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
}