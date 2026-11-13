import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/care_reminder_service.dart';

/// Wrap the main screen with this. While it is on screen it starts the
/// CareReminderService (push registration + Home card data) and stops it on
/// sign-out. It no longer shows any in-app popup.
class CareReminderListener extends StatefulWidget {
  const CareReminderListener({super.key, required this.child});

  final Widget child;

  @override
  State<CareReminderListener> createState() => _CareReminderListenerState();
}

class _CareReminderListenerState extends State<CareReminderListener>
    with WidgetsBindingObserver {
  final CareReminderService _service = CareReminderService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_service.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_service.checkNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_service.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}