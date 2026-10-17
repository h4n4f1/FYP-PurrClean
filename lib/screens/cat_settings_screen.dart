import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/local_profile_store.dart';
import '../theme/app_styles.dart';
import '../widgets/profile_widgets.dart';

class CatSettingsScreen extends StatefulWidget {
  const CatSettingsScreen({super.key});

  @override
  State<CatSettingsScreen> createState() => _CatSettingsScreenState();
}

class _CatSettingsScreenState extends State<CatSettingsScreen> {
  final _authService = FirebaseAuthService();

  String _catName = '';
  Uint8List? _photo;

  String get _uid => _authService.currentUser?.uid ?? 'guest';
  String get _displayName => _catName.isEmpty ? 'My Cat' : _catName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _load() async {
    final name = await LocalProfileStore.loadCatName(_uid);
    final photo = await LocalProfileStore.loadCatPhoto(_uid);
    if (!mounted) return;
    setState(() {
      _catName = name;
      _photo = photo;
    });
  }

  Future<void> _changeName() async {
    final newName = await showNameDialog(
      context,
      title: 'Change cat name',
      label: 'Cat name',
      initial: _catName,
    );
    if (newName == null) return;
    await LocalProfileStore.saveCatName(_uid, newName);
    if (!mounted) return;
    setState(() => _catName = newName);
    _snack('Cat name updated!');
  }

  Future<void> _changePhoto() async {
    final action = await showPhotoOptions(context, hasPhoto: _photo != null);
    if (action == null) return;

    if (action == PhotoAction.remove) {
      await LocalProfileStore.saveCatPhoto(_uid, null);
      if (mounted) setState(() => _photo = null);
      return;
    }

    final bytes = await LocalProfileStore.pickImage();
    if (bytes == null) return;
    await LocalProfileStore.saveCatPhoto(_uid, bytes);
    if (mounted) setState(() => _photo = bytes);
  }

  Future<void> _removeCatProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove cat profile?'),
        content: const Text('This clears your cat\'s name and photo.'),
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
    await LocalProfileStore.clearCat(_uid);
    if (!mounted) return;
    setState(() {
      _catName = '';
      _photo = null;
    });
    _snack('Cat profile removed.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cat Settings'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Tap the picture to change it.
          Center(
            child: EditableAvatar(
              photo: _photo,
              radius: 50,
              onTap: _changePhoto,
              fallback: const Icon(
                Icons.pets,
                size: 44,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Tap the name to change it.
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _changeName,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'ComicRelief',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.edit_rounded,
                      size: 16,
                      color: AppColors.textGrey,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _removeCatProfile,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove cat profile'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: AppDecorations.buttonRadius,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}