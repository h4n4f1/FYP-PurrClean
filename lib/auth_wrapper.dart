import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'add_cat_page.dart';
import 'screens/auth_screen.dart';
import 'screens/device_setup_screen.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';
import 'services/device_provisioning_service.dart';
import 'theme/app_styles.dart';

/// Decides which screen to show:
///   not logged in            -> AuthScreen (login / register)
///   logged in                -> device Wi-Fi setup (skippable)
///                            -> cat setup (only if the user has no cat yet)
///                            -> main menu
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = FirebaseAuthService();
  late final Stream<User?> _authStream = _authService.authStateChanges;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        final user = snapshot.data;
        if (user == null) return const AuthScreen();
        return _PostLoginGate(key: ValueKey(user.uid), userId: user.uid);
      },
    );
  }
}

class _PostLoginGate extends StatefulWidget {
  const _PostLoginGate({super.key, required this.userId});

  final String userId;

  @override
  State<_PostLoginGate> createState() => _PostLoginGateState();
}

class _PostLoginGateState extends State<_PostLoginGate> {
  /// null = still loading
  bool? _deviceStepDone;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _catStream =
      FirebaseFirestore.instance
          .collection('cats')
          .where('user_id', isEqualTo: widget.userId)
          .limit(1)
          .snapshots();

  @override
  void initState() {
    super.initState();
    _loadDeviceStep();
  }

  Future<void> _loadDeviceStep() async {
    final service = DeviceProvisioningService.instance;
    final done = await service.isProvisioned() ||
        await service.isSetupStepDone(widget.userId);
    if (!mounted) return;
    setState(() => _deviceStepDone = done);
  }

  /// Called when the device was connected OR the user tapped "Skip for now".
  Future<void> _finishDeviceStep() async {
    await DeviceProvisioningService.instance.markSetupStepDone(widget.userId);
    if (!mounted) return;
    setState(() => _deviceStepDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final deviceStepDone = _deviceStepDone;
    if (deviceStepDone == null) return const _LoadingScreen();

    // Step 1: connect the ESP32 to Wi-Fi (can be skipped).
    if (!deviceStepDone) {
      return DeviceSetupScreen(
        onComplete: _finishDeviceStep,
        onSkip: _finishDeviceStep,
      );
    }

    // Step 2: cat setup if the user has no cat yet. Step 3: main menu.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _catStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const MainShell(); // never trap the user
        if (!snapshot.hasData) return const _LoadingScreen();
        if (snapshot.data!.docs.isEmpty) {
          return AddCatPage(userId: widget.userId);
        }
        return const MainShell();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}