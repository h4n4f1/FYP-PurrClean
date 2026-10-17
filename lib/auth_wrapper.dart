import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  static const _sessionTimeout = Duration(days: 90);
  User? _user;
  bool _isCheckingSession = true;
  late final StreamSubscription<User?> _authSubscription;

  final _authService = FirebaseAuthService();

  @override
  void initState() {
    super.initState();
    _authSubscription = _authService.authStateChanges.listen(_handleAuthStateChanged);
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _isCheckingSession = false;
      });
      return;
    }

    setState(() => _isCheckingSession = true);
    final sessionIsValid = await _checkSession(user);
    if (!mounted) return;
    setState(() {
      _user = sessionIsValid ? user : null;
      _isCheckingSession = false;
    });
  }

  Future<bool> _checkSession(User user) async {
    final preferences = await SharedPreferences.getInstance();
    final key = 'last_opened_${user.uid}';
    final lastOpenedValue = preferences.getString(key);
    final now = DateTime.now();

    if (lastOpenedValue != null) {
      final lastOpened = DateTime.tryParse(lastOpenedValue);
      if (lastOpened != null && now.difference(lastOpened) >= _sessionTimeout) {
        await _authService.signOut();
        return false;
      }
    }

    await preferences.setString(key, now.toIso8601String());
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _user == null ? const AuthScreen() : const MainShell();
  }
}