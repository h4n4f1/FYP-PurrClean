import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../add_cat_page.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/local_profile_store.dart';
import '../theme/app_styles.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/profile_widgets.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  final _authService = FirebaseAuthService();
  final _account = AccountService();

  Uint8List? _photo;
  bool _isSendingVerification = false;
  bool _isLinkingGoogle = false;
  bool _isCheckingVerification = false;
  bool _isSigningOut = false;
  bool _isDeleting = false;

  User? get _user => _authService.currentUser;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _catStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = _user?.uid;
    if (uid != null) {
      _catStream = FirebaseFirestore.instance
          .collection('cats')
          .where('user_id', isEqualTo: uid)
          .snapshots();
    }
    _loadPhoto();
    _refreshUser();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUser();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadPhoto() async {
    final uid = _user?.uid;
    if (uid == null) return;
    final bytes = await LocalProfileStore.loadUserPhoto(uid);
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _refreshUser() async {
    if (mounted) setState(() => _isCheckingVerification = true);
    try {
      await _authService.reloadUser();
    } catch (_) {}
    if (mounted) setState(() => _isCheckingVerification = false);
  }

  // ---- actions ---------------------------------------------------------

  Future<void> _changeName() async {
    final newName = await showNameDialog(
      context,
      title: 'Change name',
      label: 'Your name',
      initial: _user?.displayName ?? '',
    );
    if (newName == null) return;
    final result = await _account.updateDisplayName(newName);
    if (!mounted) return;
    setState(() {});
    _snack(result.success
        ? 'Name updated!'
        : (result.errorMessage ?? 'Could not update your name.'));
  }

  Future<void> _changePhoto() async {
    final uid = _user?.uid;
    if (uid == null) return;
    final action = await showPhotoOptions(context, hasPhoto: _photo != null);
    if (action == null) return;

    if (action == PhotoAction.remove) {
      await LocalProfileStore.saveUserPhoto(uid, null);
      if (mounted) setState(() => _photo = null);
      return;
    }

    final bytes = await LocalProfileStore.pickImage();
    if (bytes == null) return;
    await LocalProfileStore.saveUserPhoto(uid, bytes);
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _handleSendVerification() async {
    setState(() => _isSendingVerification = true);
    final result = await _authService.sendEmailVerification();
    if (!mounted) return;
    setState(() => _isSendingVerification = false);
    _snack(result.success
        ? 'Verification email sent! Check your inbox or spam folder.'
        : (result.errorMessage ?? 'Failed to send verification email.'));
  }

  Future<void> _handleLinkGoogle() async {
    setState(() => _isLinkingGoogle = true);
    final result = await _authService.linkWithGoogle();
    if (!mounted) return;
    setState(() => _isLinkingGoogle = false);
    _snack(result.success
        ? 'Google account successfully linked!'
        : (result.errorMessage ?? 'Google account linking failed.'));
  }

  // ---- cat profile -----------------------------------------------------

  void _openAddCat() {
    final uid = _user?.uid;
    if (uid == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddCatPage(userId: uid)),
    );
  }

  Future<void> _deleteCat(DocumentReference<Map<String, dynamic>> ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this cat?'),
        content: const Text('This deletes your cat\'s profile.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.delete();
      _snack('Cat profile removed.');
    } catch (_) {
      _snack('Could not remove the cat profile.');
    }
  }

  Future<void> _handleLogout() async {
    setState(() => _isSigningOut = true);
    try {
      await _authService.signOut();
      // AuthWrapper switches to the login screen automatically.
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSigningOut = false);
      _snack('Could not log out. Please try again.');
    }
  }

  Future<bool> _reauthenticate() async {
    if (!mounted) return false;
    AccountResult result;
    if (_account.hasPasswordProvider) {
      final password = await showPasswordDialog(context);
      if (password == null) return false;
      result = await _account.reauthenticateWithPassword(password);
    } else {
      result = await _account.reauthenticateWithGoogle();
    }
    if (!result.success) {
      _snack(result.errorMessage ?? 'Re-authentication failed.');
    }
    return result.success;
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your PurrClean account and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final uid = _user?.uid;
    setState(() => _isDeleting = true);

    var result = await _account.deleteAccount();
    if (!result.success && result.requiresRecentLogin) {
      final reauthed = await _reauthenticate();
      if (!reauthed) {
        if (mounted) setState(() => _isDeleting = false);
        return;
      }
      result = await _account.deleteAccount();
    }

    if (result.success) {
      // AuthWrapper switches to the login screen automatically.
      if (uid != null) await LocalProfileStore.clearUser(uid);
      return;
    }

    if (!mounted) return;
    setState(() => _isDeleting = false);
    _snack(result.errorMessage ?? 'Could not delete your account.');
  }

  // ---- UI ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildVerificationCard(),
                    const SizedBox(height: 18),
                    _buildCatCard(),
                    const SizedBox(height: 18),
                    _buildLinkedAccountsCard(),
                    const SizedBox(height: 18),
                    DashboardCard(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SettingsTile(
                        icon: Icons.settings_outlined,
                        iconBg: AppColors.iconBgBlue,
                        iconColor: AppColors.infoBlue,
                        title: 'Settings',
                        subtitle: 'Notifications, cat settings and more',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildLogoutButton(),
                    const SizedBox(height: 12),
                    _buildDeleteButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = (_user?.displayName?.isNotEmpty ?? false)
        ? _user!.displayName!
        : 'PurrClean User';
    final email = _user?.email ?? 'No email available';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Column(
        children: [
          // Tap the picture to change it.
          EditableAvatar(
            photo: _photo,
            radius: 46,
            onTap: _changePhoto,
            fallback: Image.asset(
              'assets/images/logo.png',
              width: 56,
              height: 56,
            ),
          ),
          const SizedBox(height: 14),
          // Tap the name to change it.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _changeName,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'ComicRelief',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            email,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatCard() {
    final stream = _catStream;
    if (stream == null) return const SizedBox.shrink();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            icon: Icons.pets,
            iconBg: AppColors.iconBgOrange,
            iconColor: AppColors.primary,
            title: 'My Cats',
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  'Could not load your cats.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final docs = snapshot.data!.docs;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (docs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'You haven\'t added your cat yet. Add a name and photo '
                        'to personalise PurrClean.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  for (final doc in docs) ...[
                    _catRow(doc),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: _openAddCat,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(docs.isEmpty ? 'Set up cat profile' : 'Add another cat'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppDecorations.buttonRadius,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _catRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final name = (data['cat_name'] as String?)?.trim();
    final breed = (data['breed'] as String?)?.trim() ?? '';
    final age = data['age'];
    final base64Image = (data['image_base64'] as String?) ?? '';

    ImageProvider? image;
    if (base64Image.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(base64Image));
      } catch (_) {}
    }

    final details = [
      if (breed.isNotEmpty) breed,
      if (age is num && age > 0) '${age.toInt()} yrs',
    ].join(' • ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            backgroundImage: image,
            child: image == null
                ? const Icon(Icons.pets, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (name == null || name.isEmpty) ? 'My Cat' : name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textDark,
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _deleteCat(doc.reference),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard() {
    final isVerified = _authService.isEmailVerified;
    const green = Color(0xFF3EBD6A);

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(
            icon: isVerified
                ? Icons.verified_rounded
                : Icons.warning_amber_rounded,
            iconBg: isVerified ? const Color(0xFFE8F8EE) : AppColors.iconBgOrange,
            iconColor: isVerified ? green : AppColors.primary,
            title: isVerified ? 'Email Verified' : 'Email Not Verified',
            trailing: isVerified
                ? null
                : InkWell(
                    onTap: _isCheckingVerification ? null : _refreshUser,
                    child: _isCheckingVerification
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 20, color: Colors.grey),
                  ),
          ),
          if (!isVerified) ...[
            const SizedBox(height: 12),
            Text(
              'Verify your email to keep your account secure and prevent losing access.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed:
                    _isSendingVerification ? null : _handleSendVerification,
                icon: _isSendingVerification
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: const Text('Resend Verification Email'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerRow({
    required Widget leading,
    required String title,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.textDark,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildLinkedAccountsCard() {
    final isGoogleLinked = _authService.isGoogleLinked;

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardHeader(
            icon: Icons.link_rounded,
            iconBg: AppColors.iconBgBlue,
            iconColor: AppColors.infoBlue,
            title: 'Linked Accounts',
          ),
          const SizedBox(height: 16),
          _providerRow(
            leading: const Icon(
              Icons.email_outlined,
              color: AppColors.textDark,
              size: 22,
            ),
            title: 'Email & Password',
            trailing: _statusBadge('Active'),
          ),
          const SizedBox(height: 10),
          _providerRow(
            leading: Image.asset(
              'assets/images/google_logo.png',
              width: 22,
              height: 22,
            ),
            title: 'Google Sign-In',
            trailing: isGoogleLinked
                ? _statusBadge('Linked')
                : ElevatedButton(
                    onPressed: _isLinkingGoogle ? null : _handleLinkGoogle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLinkingGoogle
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Link Google',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: (_isSigningOut || _isDeleting) ? null : _handleLogout,
        icon: _isSigningOut
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.logout_rounded),
        label: Text(_isSigningOut ? 'Signing out...' : 'Log out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: AppDecorations.buttonRadius,
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: (_isSigningOut || _isDeleting) ? null : _deleteAccount,
        icon: _isDeleting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_forever_outlined),
        label: Text(_isDeleting ? 'Deleting...' : 'Delete account'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: AppDecorations.buttonRadius,
          ),
        ),
      ),
    );
  }
}