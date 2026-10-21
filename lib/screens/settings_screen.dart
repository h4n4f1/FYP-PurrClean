import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/local_profile_store.dart';
import '../theme/app_styles.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/profile_widgets.dart';
import 'cat_settings_screen.dart';
import 'device_setup_screen.dart';

class _NotificationOption {
  const _NotificationOption(this.key, this.title, this.subtitle);

  final String key;
  final String title;
  final String subtitle;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _options = [
    _NotificationOption(
      'health_anomaly',
      'Health Anomaly Alerts',
      'Get notified of unusual patterns',
    ),
    _NotificationOption(
      'litter_cleaning',
      'Litter Cleaning Reminder',
      'Alert when waste reaches 80%',
    ),
    _NotificationOption(
      'litter_refill',
      'Litter Refill Reminder',
      'Remind to refill litter',
    ),
    _NotificationOption(
      'daily_summary',
      'Daily Summary',
      'Daily activity report',
    ),
  ];

  static const _switchOn = Color(0xFF111122);
  static const _switchOff = Color(0xFFD1D5DB);

  final _authService = FirebaseAuthService();
  final Map<String, bool> _prefs = Map.of(LocalProfileStore.notificationDefaults);

  String get _uid => _authService.currentUser?.uid ?? 'guest';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final loaded = <String, bool>{};
    for (final option in _options) {
      loaded[option.key] =
          await LocalProfileStore.loadNotificationPref(_uid, option.key);
    }
    if (!mounted) return;
    setState(() => _prefs.addAll(loaded));
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _prefs[key] = value);
    await LocalProfileStore.saveNotificationPref(_uid, key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DashboardCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SettingsTile(
              icon: Icons.pets,
              title: 'Cat Settings',
              subtitle: 'Your cat\'s name and photo',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CatSettingsScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          DashboardCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SettingsTile(
              icon: Icons.wifi_rounded,
              title: 'Device Wi-Fi Setup',
              subtitle: 'Connect or reconnect your PurrClean to Wi-Fi',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => DeviceSetupScreen(
                    showBackButton: true,
                    onComplete: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildNotificationCard(),
        ],
      ),
    );
  }

  Widget _buildNotificationCard() {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            icon: Icons.notifications_none_rounded,
            iconBg: AppColors.iconBgYellow,
            iconColor: AppColors.primary,
            title: 'Notification Preferences',
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _options.length; i++) ...[
            _buildOptionRow(_options[i]),
            if (i != _options.length - 1)
              Divider(height: 1, color: Colors.grey.shade200),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionRow(_NotificationOption option) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Switch(
            value: _prefs[option.key] ?? false,
            onChanged: (value) => _toggle(option.key, value),
            thumbColor: WidgetStateProperty.all(Colors.white),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? _switchOn
                  : _switchOff,
            ),
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ],
      ),
    );
  }
}