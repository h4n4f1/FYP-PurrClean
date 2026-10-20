import 'package:flutter/material.dart';

import '../services/device_provisioning_service.dart';
import '../theme/app_styles.dart';

enum _Step { intro, busy, pickDevice, pickNetwork, success, error }

/// Shown before login / register until the ESP32 has been connected to the
/// user's home Wi-Fi through the app.
class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key, required this.onComplete});

  /// Called when the ESP32 is online and the user taps "Continue".
  final VoidCallback onComplete;

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

    final allowed = await _service.ensurePermissions();
    if (!allowed) {
      _showError(
        'PurrClean needs Bluetooth permission to find your device. '
        'Please allow it in your phone settings and try again.',
        _startSearch,
      );
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
        'Something went wrong while searching. Check that Bluetooth is turned '
        'on and try again.',
        _startSearch,
      );
    }
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
    _showBusy('Connecting your PurrClean to "$ssid"…\nThis can take up to 30 seconds.');

    try {
      final ok = await _service.provision(
        deviceName: device,
        ssid: ssid,
        password: _passwordController.text,
      );
      if (!mounted) return;
      if (ok) {
        await _service.markProvisioned(device);
        if (!mounted) return;
        setState(() => _step = _Step.success);
      } else {
        _showError(
          'Your PurrClean couldn\'t join "$ssid". Check the password, and '
          'make sure it is a 2.4 GHz network (5 GHz is not supported).',
          () => setState(() => _step = _Step.pickNetwork),
        );
      }
    } catch (_) {
      _showError(
        'Your PurrClean couldn\'t join "$ssid". Check the password, and '
        'make sure it is a 2.4 GHz network (5 GHz is not supported).',
        () => setState(() => _step = _Step.pickNetwork),
      );
    }
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

  Widget _buildIntro() {
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
          'Before you sign in, your PurrClean litter box needs to be connected '
          'to your home Wi-Fi.\n\n'
          '1. Plug in your PurrClean.\n'
          '2. Turn on Bluetooth on your phone.\n'
          '3. Keep your phone close to the device.',
          style: TextStyle(fontSize: 15, color: AppColors.textDark, height: 1.4),
        ),
        const SizedBox(height: 24),
        _primaryButton('Find my PurrClean', _startSearch),
        TextButton(onPressed: _showHelp, child: const Text('Need help?')),
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
          'It is now connected to your home Wi-Fi. Next, sign in or create '
          'your account.',
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