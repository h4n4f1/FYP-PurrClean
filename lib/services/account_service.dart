import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AccountResult {
  const AccountResult({
    required this.success,
    this.errorMessage,
    this.requiresRecentLogin = false,
  });

  final bool success;
  final String? errorMessage;
  final bool requiresRecentLogin;
}

/// Name change, re-authentication and account deletion.
class AccountService {
  AccountService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  static bool _googleInitialized = false;

  User? get user => _auth.currentUser;

  bool get hasPasswordProvider =>
      user?.providerData.any((p) => p.providerId == 'password') ?? false;

  static const _noUser =
      AccountResult(success: false, errorMessage: 'No signed in user.');

  Future<AccountResult> updateDisplayName(String name) async {
    final current = user;
    if (current == null) return _noUser;
    try {
      await current.updateDisplayName(name);
      await current.reload();
      return const AccountResult(success: true);
    } on FirebaseAuthException catch (error) {
      return AccountResult(
        success: false,
        errorMessage: error.message ?? 'Could not update your name.',
      );
    } catch (_) {
      return const AccountResult(
        success: false,
        errorMessage: 'Could not update your name.',
      );
    }
  }

  Future<AccountResult> reauthenticateWithPassword(String password) async {
    final current = user;
    final email = current?.email;
    if (current == null || email == null) return _noUser;
    try {
      await current.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
      return const AccountResult(success: true);
    } on FirebaseAuthException catch (error) {
      final wrongPassword =
          error.code == 'wrong-password' || error.code == 'invalid-credential';
      return AccountResult(
        success: false,
        errorMessage: wrongPassword
            ? 'Incorrect password.'
            : (error.message ?? 'Re-authentication failed.'),
      );
    } catch (_) {
      return const AccountResult(
        success: false,
        errorMessage: 'Re-authentication failed.',
      );
    }
  }

  Future<AccountResult> reauthenticateWithGoogle() async {
    final current = user;
    if (current == null) return _noUser;
    try {
      if (!_googleInitialized) {
        await GoogleSignIn.instance.initialize();
        _googleInitialized = true;
      }
      final googleUser = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: googleUser.authentication.idToken,
      );
      await current.reauthenticateWithCredential(credential);
      return const AccountResult(success: true);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return const AccountResult(
          success: false,
          errorMessage: 'Google sign-in was canceled.',
        );
      }
      return AccountResult(
        success: false,
        errorMessage: error.description ?? 'Re-authentication failed.',
      );
    } on FirebaseAuthException catch (error) {
      return AccountResult(
        success: false,
        errorMessage: error.message ?? 'Re-authentication failed.',
      );
    } catch (_) {
      return const AccountResult(
        success: false,
        errorMessage: 'Re-authentication failed.',
      );
    }
  }

  Future<AccountResult> deleteAccount() async {
    final current = user;
    if (current == null) return _noUser;
    try {
      await current.delete();
      return const AccountResult(success: true);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'requires-recent-login') {
        return const AccountResult(
          success: false,
          requiresRecentLogin: true,
          errorMessage: 'Please confirm your identity to continue.',
        );
      }
      return AccountResult(
        success: false,
        errorMessage: error.message ?? 'Could not delete your account.',
      );
    } catch (_) {
      return const AccountResult(
        success: false,
        errorMessage: 'Could not delete your account.',
      );
    }
  }
}