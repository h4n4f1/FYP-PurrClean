import 'package:flutter/material.dart';

import '../services/device_status_service.dart';
import '../theme/app_styles.dart';

/// Banner shown at the top of the main menu when the ESP32 needs attention.
class DeviceStatusBanner extends StatelessWidget {
  const DeviceStatusBanner({
    super.key,
    required this.status,
    required this.onPressed,
  });

  final DeviceLinkStatus status;
  final VoidCallback onPressed;

  /// Whether a banner should be shown for this status.
  static bool isVisibleFor(DeviceLinkStatus status) =>
      status == DeviceLinkStatus.notSetUp ||
      status == DeviceLinkStatus.wasReset ||
      status == DeviceLinkStatus.offline;

  @override
  Widget build(BuildContext context) {
    String title;
    String message;
    String button;
    IconData icon;

    if (status == DeviceLinkStatus.notSetUp) {
      title = 'Connect your PurrClean to Wi-Fi';
      message = 'Set up your device to see live data in the app.';
      button = 'Set up Wi-Fi';
      icon = Icons.wifi_find_rounded;
    } else if (status == DeviceLinkStatus.wasReset) {
      title = 'Your PurrClean was reset';
      message = 'Its Wi-Fi settings were cleared. Set it up again to reconnect.';
      button = 'Set up Wi-Fi again';
      icon = Icons.restart_alt_rounded;
    } else if (status == DeviceLinkStatus.offline) {
      title = 'Your PurrClean is offline';
      message = 'It hasn\'t been seen for a few minutes. Check its power and '
          'Wi-Fi, or set up the Wi-Fi again.';
      button = 'Set up Wi-Fi again';
      icon = Icons.wifi_off_rounded;
    } else {
      return const SizedBox.shrink();
    }

    return Material(
      color: const Color(0xFFFFE6CC),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: AppColors.alertBell, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}