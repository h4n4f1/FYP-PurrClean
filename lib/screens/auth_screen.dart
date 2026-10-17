import 'package:cloud_firestore/cloud_firestore.dart'; // <-- Add this import
import 'package:firebase_auth/firebase_auth.dart';       // <-- Add this import
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_styles.dart';
import '../widgets/custom_text_field.dart';
import '../add_cat_page.dart';                         // <-- Import your AddCatPage file

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _authService = FirebaseAuthService();
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  bool isGoogleLoading = false;

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _fullNameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    super.dispose();
  }

  Future _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    final result = await _authService.login(
      email: _loginEmailController.text.trim(),
      password: _loginPasswordController.text,
    );
    if (!mounted) return;
    setState(() => isLoading = false);
    if (!result.success) {
      _showMessage(result.errorMessage ?? 'Login failed.');
    }
  }

  Future _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    final email = _registerEmailController.text.trim();
    final result = await _authService.register(
      fullName: _fullNameController.text.trim(),
      email: email,
      password: _registerPasswordController.text,
    );
    if (!mounted) return;
    setState(() => isLoading = false);
    
    if (!result.success) {
      _showMessage(result.errorMessage ?? 'Registration failed.');
    } else {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Use push (instead of pushReplacement if your auth wrapper interferes) 
        // or ensure it pops/replaces the entire stack to AddCatPage:
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => AddCatPage(userId: currentUser.uid),
          ),
          (route) => false, // Clears the auth screen out of the navigation stack
        );
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

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
                  child: Column(
                    children: [
                      _buildToggle(),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: isLogin ? _buildLoginForm() : _buildRegisterForm(),
                      ),
                    ],
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
          ],
        ),
      ),
    );
  }

  Widget _buildToggle() {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.toggleTrack,
        borderRadius: AppDecorations.toggleRadius,
      ),
      child: Row(
        children: [
          Expanded(child: _toggleButton('Login', isLogin)),
          Expanded(child: _toggleButton('Register', !isLogin)),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, bool selected) {
    return GestureDetector(
      onTap: () => setState(() => isLogin = label == 'Login'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: selected ? AppColors.primaryGradient : null,
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

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        key: const ValueKey('login'),
        children: [
          CustomTextField(
            label: 'Email',
            hint: '',
            icon: Icons.alternate_email,
            controller: _loginEmailController,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          CustomTextField(
            label: 'Password',
            hint: '',
            icon: Icons.lock_outline,
            controller: _loginPasswordController,
            obscureText: true,
            validator: _passwordValidator,
          ),
          const SizedBox(height: 8),
          _buildSubmitButton('Sign In', _handleLogin),
          const SizedBox(height: 16),
          _buildOrDivider(),
          const SizedBox(height: 16),
          _buildGoogleButton(),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Form(
      key: _registerFormKey,
      child: Column(
        key: const ValueKey('register'),
        children: [
          CustomTextField(
            label: 'Full Name',
            hint: '',
            icon: Icons.person_outline,
            controller: _fullNameController,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter your name'
                : null,
          ),
          CustomTextField(
            label: 'Email',
            hint: '',
            icon: Icons.alternate_email,
            controller: _registerEmailController,
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          CustomTextField(
            label: 'Password',
            hint: '',
            icon: Icons.lock_outline,
            controller: _registerPasswordController,
            obscureText: true,
            validator: _passwordValidator,
          ),
          const SizedBox(height: 8),
          _buildSubmitButton('Create Account', _handleRegister),
          const SizedBox(height: 16),
          _buildOrDivider(),
          const SizedBox(height: 16),
          _buildGoogleButton(),
        ],
      ),
    );
  }

  String? _emailValidator(String? value) =>
      value == null || !value.contains('@') ? 'Enter a valid email' : null;

  String? _passwordValidator(String? value) =>
      value == null || value.length < 6 ? 'Min 6 characters' : null;

  Widget _buildSubmitButton(String label, VoidCallback onTap) {
    final isBusy = isLoading || isGoogleLoading;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isBusy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.buttonRadius),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Text(label, style: AppTextStyles.buttonLabel),
      ),
    );
  }

  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    final isBusy = isLoading || isGoogleLoading;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: isBusy ? null : _handleGoogleSignIn,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: Colors.grey.shade300, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: AppDecorations.buttonRadius,
          ),
          elevation: 0,
        ),
        child: isGoogleLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/google_logo.png',
                    width: 22,
                    height: 22,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future _handleGoogleSignIn() async {
    setState(() => isGoogleLoading = true);
    final result = await _authService.signInWithGoogle();
    if (!mounted) return;
    setState(() => isGoogleLoading = false);

    if (!result.success) {
      _showMessage(result.errorMessage ?? 'Google sign-in failed.');
    } else {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Check if this user already has a cat registered in Firestore
        final catQuery = await FirebaseFirestore.instance
            .collection('cats')
            .where('user_id', isEqualTo: currentUser.uid)
            .get();

        if (!mounted) return;

        // If they don't have any cats yet, route them to AddCatPage
        if (catQuery.docs.isEmpty) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => AddCatPage(userId: currentUser.uid),
            ),
            (route) => false,
          );
        }
        // If they already have a cat, your main app wrapper (like StreamBuilder on auth state) 
        // will automatically land them on the HomeScreen.
      }
    }
  }
}