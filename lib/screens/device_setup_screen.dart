import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_provisioning_service.dart';
import '../services/device_status_service.dart';
import '../theme/app_styles.dart';

enum _Step { intro, busy, pickDevice, pickNetwork, success, error }

/// Connects the ESP32 to the user's home Wi-Fi over Bluetooth.
///
/// Used in three places:
///  - right after login/register (with [onSkip] so the user can skip it)
///  - from Settings (also used to SWITCH to a different Wi-Fi)
///  - from the main-menu banner
class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({
    super.key,
    required this.onComplete,
    this.onSkip,
    this.showBackButton = false,
  });

  /// Called when the ESP32 is online and the user taps "Continue".
  final VoidCallback onComplete;

  /// If set, a "Skip for now" button is shown.
  final VoidCallback? onSkip;

  /// Show a back arrow (when the screen was opened from Settings / banner).
  final bool showBackButton;

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen> {
  final _service = DeviceProvisioningService.instance;
  final _manualSsidController = TextEditingController();
  final _passwordController = TextEditingController();

  _Step _step = _Step.intro;
  String _busyMessage = '';
  String _errorMessage = '';
  VoidCallback? _retry;

  List<String> _devices = [];
  List<String> _networks = [];
  String? _device;
  String? _selectedSsid;
  bool _enterManually = false;
  bool _hidePassword = true;

  /// BLE name of a device that was already set up from this phone (or null).
  String? _savedDevice;

  @override
  void initState() {
    super.initState();
    _loadSavedDevice();
  }

  Future<void> _loadSavedDevice() async {
    final saved = await _service.savedDeviceName();
    if (!mounted) return;
    setState(() => _savedDevice = saved);
  }

  @override
  void dispose() {
    _manualSsidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ---- flow ----------------------------------------------------------

  void _showBusy(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.busy;
      _busyMessage = message;
    });
  }

  void _showError(String message, VoidCallback retry) {
    if (!mounted) return;
    setState(() {
      _step = _Step.error;
      _errorMessage = message;
      _retry = retry;
    });
  }

  Future<void> _startSearch() async {
    _showBusy('Looking for your PurrClean…');

    final problem = await _service.checkAccess();
    if (!mounted) return;
    if (problem != null) {
      _showError(problem, _startSearch);
      return;
    }

    try {
      final devices = await _service.scanDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        _showError(
          'We couldn\'t find your PurrClean. Make sure it is plugged in, '
          'Bluetooth is on, and your phone is next to it.',
          _startSearch,
        );
        return;
      }
      _devices = devices;
      if (devices.length == 1) {
        await _selectDevice(devices.first);
      } else {
        setState(() => _step = _Step.pickDevice);
      }
    } catch (_) {
      _showError(
        'Something went wrong while searching. Check that Bluetooth AND '
        'Location are turned on in your phone, then try again.',
        _startSearch,
      );
    }
  }

  /// Switch to a different Wi-Fi: ask the (online) PurrClean to forget its
  /// current Wi-Fi, wait for it to restart in setup mode, then run the normal
  /// search + Wi-Fi pick flow.
  Future<void> _switchWifi() async {
    final saved = _savedDevice;
    if (saved == null) {
      _startSearch();
      return;
    }
    final status = DeviceStatusService.instance;

    _showBusy('Telling your PurrClean to forget its old Wi-Fi…\n'
        'This can take up to 40 seconds.');

    final sent = await status.requestWifiReset(saved);
    if (!mounted) return;
    if (!sent) {
      _showError(
        'Couldn\'t reach PurrClean\'s cloud. Check your phone\'s internet '
        'connection and try again.\n\n'
        'If your old Wi-Fi is no longer available, just wait about 3 '
        'minutes: your PurrClean opens setup mode by itself. Then tap '
        '"Try again" below.',
        _startSearch,
      );
      return;
    }

    final acked = await status.waitForWifiResetAck(saved);
    if (!mounted) return;
    if (!acked) {
      await status.cancelWifiReset(saved);
      if (!mounted) return;
      _showError(
        'Your PurrClean didn\'t answer. It is probably offline (for example '
        'because the old Wi-Fi was turned off).\n\n'
        'If its Wi-Fi changed, wait about 3 minutes: it opens setup mode by '
        'itself when it can\'t find its Wi-Fi. Then tap "Try again". ',
        _startSearch,
      );
      return;
    }

    _showBusy('Your PurrClean is restarting in setup mode…');
    await Future<void>.delayed(const Duration(seconds: 6));
    if (!mounted) return;
    _startSearch();
  }

  Future<void> _selectDevice(String device) async {
    _device = device;
    _showBusy('Checking which Wi-Fi networks your PurrClean can see…');
    try {
      final networks = await _service.scanNetworks(device);
      if (!mounted) return;
      _networks = networks;
      setState(() {
        _selectedSsid = null;
        _enterManually = networks.isEmpty;
        _step = _Step.pickNetwork;
      });
    } catch (_) {
      _showError(
        'Couldn\'t talk to your PurrClean. Move closer and try again.',
        () => _selectDevice(device),
      );
    }
  }

  Future<void> _submitWifi() async {
    final ssid =
        (_enterManually ? _manualSsidController.text.trim() : _selectedSsid) ??
            '';
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose or enter your Wi-Fi name.')),
      );
      return;
    }
    final device = _device;
    if (device == null) return;

    FocusScope.of(context).unfocus();
    _showBusy('Connecting your PurrClean to "$ssid"…\nThis can take up to a minute.');

    bool ok;
    try {
      ok = await _provisionAndConfirm(
        device: device,
        ssid: ssid,
        password: _passwordController.text,
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;

    if (ok) {
      await _service.markProvisioned(device);
      // Don't wait for this one: it only updates the cloud status.
      DeviceStatusService.instance.setProvisioned(device, true);
      if (!mounted) return;
      setState(() => _step = _Step.success);
    } else {
      _showError(
        'Your PurrClean couldn\'t join "$ssid". Check the password, and '
        'make sure it is a 2.4 GHz network (5 GHz is not supported).',
        () => setState(() => _step = _Step.pickNetwork),
      );
    }
  }

  /// Sends the Wi-Fi details over Bluetooth, then confirms the result in two
  /// ways, because the Bluetooth answer can get lost when the ESP32 drops the
  /// Bluetooth link right after it joins the Wi-Fi:
  ///  1. the Bluetooth result from the plugin, and
  ///  2. the ESP32 setting devices/<id>/provisioned = true in Firebase as
  ///     soon as it is online.
  /// Whichever reports success first wins. Never waits more than 75 seconds.
  Future<bool> _provisionAndConfirm({
    required String device,
    required String ssid,
    required String password,
  }) async {
    final status = DeviceStatusService.instance;
    final done = Completer<bool>();
    void finish(bool ok) {
      if (!done.isCompleted) done.complete(ok);
    }

    // Reset the flag so we can tell when the ESP32 sets it back to true.
    await status.setProvisioned(device, false);

    const limit = Duration(seconds: 75);

    status.waitForProvisioned(device, timeout: limit).then((ok) {
      if (ok) finish(true);
    });

    _service
        .provision(deviceName: device, ssid: ssid, password: password)
        .then((ok) {
      if (ok) {
        finish(true);
      } else {
        // Give the cloud check a moment to prove it actually worked.
        Future<void>.delayed(const Duration(seconds: 10), () => finish(false));
      }
    }).catchError((Object _) {
      Future<void>.delayed(const Duration(seconds: 10), () => finish(false));
    });

    Future<void>.delayed(limit, () => finish(false));
    return done.future;
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Can\'t find your PurrClean?'),
        content: const Text(
          '• Make sure the device is plugged in and powered on.\n'
          '• Turn Bluetooth on and stay within 1–2 metres of the device.\n'
          '• If the device was set up before, press and hold its BOOT button '
          'for 5 seconds. It will forget the old Wi-Fi and restart in setup '
          'mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  // ---- layout --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showBackButton
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              foregroundColor: AppColors.textDark,
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppDecorations.cardRadius,
              boxShadow: AppDecorations.cardShadow,
            ),
            child: Column(
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: KeyedSubtree(
                      key: ValueKey(_step),
                      child: _buildStep(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: Column(
          children: [
            Image.asset('assets/images/logo.png', width: 88, height: 88),
            const SizedBox(height: 6),
            const Text('PurrClean', style: AppTextStyles.appTitle),
            const SizedBox(height: 4),
            const Text(
              'Device setup',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.intro:
        return _buildIntro();
      case _Step.busy:
        return _buildBusy();
      case _Step.pickDevice:
        return _buildPickDevice();
      case _Step.pickNetwork:
        return _buildPickNetwork();
      case _Step.success:
        return _buildSuccess();
      case _Step.error:
        return _buildError();
    }
  }

  /// "Skip for now" button, only when the screen was given an onSkip.
  Widget _skipButton() {
    final onSkip = widget.onSkip;
    if (onSkip == null) return const SizedBox.shrink();
    return TextButton(
      onPressed: onSkip,
      child: const Text('Skip for now'),
    );
  }

  Widget _buildIntro() {
    if (_savedDevice != null) return _buildSwitchIntro();
    return Column(
      children: [
        const Icon(Icons.wifi_rounded, size: 56, color: AppColors.primary),
        const SizedBox(height: 16),
        const Text(
          'Connect your PurrClean to Wi-Fi',
          textAlign: TextAlign.center,
          style: AppTextStyles.cardTitle,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your PurrClean litter box needs to be connected to your home Wi-Fi '
          'so it can send its data to the app.\n\n'
          '1. Plug in your PurrClean.\n'
          '2. Turn on Bluetooth and Location on your phone.\n'
          '3. Keep your phone close to the device.',
          style: TextStyle(fontSize: 15, color: AppColors.textDark, height: 1.4),
        ),
        const SizedBox(height: 24),
        _primaryButton('Find my PurrClean', _startSearch),
        TextButton(onPressed: _showHelp, child: const Text('Need help?')),
        _skipButton(),
      ],
    );
  }

  /// Intro shown when this phone has already set up a PurrClean: lets the
  /// user move it to a different Wi-Fi network.
  Widget _buildSwitchIntro() {
    return Column(
      children: [
        const Icon(Icons.swap_horiz_rounded,
            size: 56, color: AppColors.primary),
        const SizedBox(height: 16),
        const Text(
          'Switch to a different Wi-Fi',
          textAlign: TextAlign.center,
          style: AppTextStyles.cardTitle,
        ),
        const SizedBox(height: 12),
        const Text(
          'Your PurrClean is already set up. To move it to another Wi-Fi '
          'network (for example a new router):\n\n'
          '1. Keep your phone close to the device.\n'
          '2. Turn on Bluetooth and Location on your phone.\n'
          '3. Tap "Switch Wi-Fi" and follow the steps.\n\n'
          'If the old Wi-Fi is already gone, wait about 3 minutes: your '
          'PurrClean opens setup mode by itself. Then tap "My PurrClean is '
          'already reset".',
          style: TextStyle(fontSize: 15, color: AppColors.textDark, height: 1.4),
        ),
        const SizedBox(height: 24),
        _primaryButton('Switch Wi-Fi', _switchWifi),
        TextButton(
          onPressed: _startSearch,
          child: const Text('My PurrClean is already reset'),
        ),
        TextButton(onPressed: _showHelp, child: const Text('Need help?')),
        _skipButton(),
      ],
    );
  }

  Widget _buildBusy() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 24),
          Text(
            _busyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

  Widget _buildPickDevice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose your PurrClean', style: AppTextStyles.cardTitle),
        const SizedBox(height: 4),
        const Text(
          'More than one device was found nearby.',
          style: AppTextStyles.helperText,
        ),
        const SizedBox(height: 16),
        for (final device in _devices)
          Card(
            elevation: 0,
            color: AppColors.inputFill,
            shape: RoundedRectangleBorder(borderRadius: AppDecorations.inputRadius),
            child: ListTile(
              leading: const Icon(Icons.bluetooth, color: AppColors.primary),
              title: Text(device),
              onTap: () => _selectDevice(device),
            ),
          ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _startSearch,
            child: const Text('Search again'),
          ),
        ),
      ],
    );
  }

  Widget _buildPickNetwork() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Choose your home Wi-Fi', style: AppTextStyles.cardTitle),
        const SizedBox(height: 4),
        const Text(
          'Only 2.4 GHz networks work with the PurrClean.',
          style: AppTextStyles.helperText,
        ),
        const SizedBox(height: 16),
        if (!_enterManually) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: RadioGroup<String>(
              groupValue: _selectedSsid,
              onChanged: (value) => setState(() => _selectedSsid = value),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final ssid in _networks)
                    RadioListTile<String>(
                      value: ssid,
                      activeColor: AppColors.primary,
                      title: Text(ssid),
                      secondary:
                          const Icon(Icons.wifi, color: AppColors.primary),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _enterManually = true),
            child: const Text('My network isn\'t listed'),
          ),
        ] else ...[
          TextField(
            controller: _manualSsidController,
            decoration: AppDecorations.inputDecoration(
              hint: 'Wi-Fi name',
              icon: Icons.wifi,
            ),
          ),
          if (_networks.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _enterManually = false),
              child: const Text('Pick from the list instead'),
            ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: _hidePassword,
          decoration: AppDecorations.inputDecoration(
            hint: 'Wi-Fi password',
            icon: Icons.lock_outline,
          ).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _hidePassword ? Icons.visibility_off : Icons.visibility,
                color: AppColors.textGrey,
              ),
              onPressed: () => setState(() => _hidePassword = !_hidePassword),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _primaryButton('Connect', _submitWifi),
        Center(
          child: TextButton(
            onPressed: () => _selectDevice(_device!),
            child: const Text('Rescan networks'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        const SizedBox(height: 8),
        const Icon(Icons.check_circle_rounded,
            size: 64, color: AppColors.successGreen),
        const SizedBox(height: 16),
        const Text(
          'Your PurrClean is online!',
          textAlign: TextAlign.center,
          style: AppTextStyles.cardTitle,
        ),
        const SizedBox(height: 8),
        const Text(
          'It is now connected to your home Wi-Fi.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: AppColors.textDark),
        ),
        const SizedBox(height: 24),
        _primaryButton('Continue', widget.onComplete),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 56, color: AppColors.alertBell),
        const SizedBox(height: 16),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: AppColors.textDark),
        ),
        const SizedBox(height: 24),
        _primaryButton('Try again', () => _retry?.call()),
        TextButton(onPressed: _showHelp, child: const Text('Need help?')),
        _skipButton(),
      ],
    );
  }

  Widget _primaryButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.buttonRadius),
          elevation: 0,
        ),
        child: Text(label, style: AppTextStyles.buttonLabel),
      ),
    );
  }
}