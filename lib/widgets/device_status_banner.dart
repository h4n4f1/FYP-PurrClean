import 'package:flutter/material.dart';

import '../services/device_status_service.dart';
import '../theme/app_styles.dart';

/// Compact floating card shown above the bottom navigation bar when the
/// ESP32 needs attention. Designed to not interfere with page headers.
class DeviceStatusBanner extends StatelessWidget {
  const DeviceStatusBanner({
    super.key,
    required this.status,
    required this.onPressed,
    this.onDismiss,
  });

  final DeviceLinkStatus status;
  final VoidCallback onPressed;
  final VoidCallback? onDismiss;

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
      title = 'PurrClean not connected';
      message = 'Connect it to Wi-Fi to see live data.';
      button = 'Connect';
      icon = Icons.wifi_find_rounded;
    } else if (status == DeviceLinkStatus.wasReset) {
      title = 'PurrClean was reset';
      message = 'Its Wi-Fi settings were cleared.';
      button = 'Reconnect';
      icon = Icons.restart_alt_rounded;
    } else if (status == DeviceLinkStatus.offline) {
      title = 'PurrClean is offline';
      message = 'Check its power and Wi-Fi connection.';
      button = 'Reconnect';
      icon = Icons.wifi_off_rounded;
    } else {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.iconBgOrange,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onPressed,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Text(
                      button,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.grey.shade500,
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
