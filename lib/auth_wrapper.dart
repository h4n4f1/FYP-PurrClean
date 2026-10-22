import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'add_cat_page.dart';
import 'screens/auth_screen.dart';
import 'screens/device_setup_screen.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';
import 'services/device_provisioning_service.dart';
import 'services/device_status_service.dart';
import 'theme/app_styles.dart';

/// Decides which screen to show:
///   not logged in   -> AuthScreen (login / register)
///   logged in       -> 1. device Wi-Fi setup   (skipped if this account
///                         already owns a device)
///                   -> 2. cat setup            (skippable)
///                   -> main menu
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

String _catStepKey(String uid) => 'cat_step_done_$uid';

/// True if this user already has a cat saved in Firestore.
Future<bool> _userHasCat(String uid) async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('cats')
        .where('user_id', isEqualTo: uid)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  } catch (_) {
    return false;
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
  bool? _catStepDone;

  @override
  void initState() {
    super.initState();
    _loadSteps();
  }

  Future<void> _loadSteps() async {
    final service = DeviceProvisioningService.instance;
    final prefs = await SharedPreferences.getInstance();

    // Device: known on this phone, or owned by this account in the cloud
    // (e.g. new phone / reinstalled app).
    var deviceDone = await service.isProvisioned();
    if (!deviceDone) {
      final owned =
          await DeviceStatusService.instance.findDeviceForUser(widget.userId);
      if (owned != null) {
        await service.markProvisioned(owned);
        deviceDone = true;
      }
    }
    if (!deviceDone) deviceDone = await service.isSetupStepDone(widget.userId);

    var catDone = prefs.getBool(_catStepKey(widget.userId)) ?? false;
    if (!catDone && await _userHasCat(widget.userId)) {
      catDone = true;
      await prefs.setBool(_catStepKey(widget.userId), true);
    }

    if (!mounted) return;
    setState(() {
      _deviceStepDone = deviceDone;
      _catStepDone = catDone;
    });
  }

  /// Called when the device was connected OR the user tapped "Skip for now".
  Future<void> _finishDeviceStep() async {
    await DeviceProvisioningService.instance.markSetupStepDone(widget.userId);
    if (!mounted) return;
    setState(() => _deviceStepDone = true);
  }

  /// Called when the cat was saved OR the user tapped "Skip for now".
  Future<void> _finishCatStep() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_catStepKey(widget.userId), true);
    if (!mounted) return;
    setState(() => _catStepDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final deviceStepDone = _deviceStepDone;
    final catStepDone = _catStepDone;
    if (deviceStepDone == null || catStepDone == null) {
      return const _LoadingScreen();
    }

    // Step 1: connect the ESP32 to Wi-Fi (can be skipped).
    if (!deviceStepDone) {
      return DeviceSetupScreen(
        onComplete: _finishDeviceStep,
        onSkip: _finishDeviceStep,
      );
    }

    // Step 2: add the cat (can be skipped).
    if (!catStepDone) {
      return _CatSetupScreen(
        userId: widget.userId,
        onDone: _finishCatStep,
        onSkip: _finishCatStep,
      );
    }

    // Step 3: main menu.
    return const MainShell();
  }
}

/// Shown right after the Wi-Fi step: asks the user to add their cat.
class _CatSetupScreen extends StatelessWidget {
  const _CatSetupScreen({
    required this.userId,
    required this.onDone,
    required this.onSkip,
  });

  final String userId;
  final VoidCallback onDone;
  final VoidCallback onSkip;

  Future<void> _addCat(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddCatPage(userId: userId)),
    );
    // AddCatPage closes itself after saving (or the user pressed back).
    if (await _userHasCat(userId)) onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppDecorations.cardRadius,
                boxShadow: AppDecorations.cardShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pets, size: 56, color: AppColors.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Add your cat',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.cardTitle,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Tell us about your cat (name, breed, weight and a '
                    'photo) so PurrClean can track their litter habits.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textDark,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () => _addCat(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDecorations.buttonRadius,
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Add my cat',
                        style: AppTextStyles.buttonLabel,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onSkip,
                    child: const Text('Skip for now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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