import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme/app_styles.dart';
import 'widgets/dashboard_card.dart';
import 'widgets/profile_widgets.dart';

class AddCatPage extends StatefulWidget {
  final String userId; // Pass the current logged-in user's ID

  const AddCatPage({super.key, required this.userId});

  /// Opens [AddCatPage]. If the user already has 1 or more cats registered,
  /// displays an alert popup first explaining that adding multiple cats may
  /// reduce individual tracking accuracy and functionality.
  static Future<void> open(
    BuildContext context, {
    required String userId,
    int? existingCatCount,
  }) async {
    final navigator = Navigator.of(context);
    int count = existingCatCount ?? 0;

    if (existingCatCount == null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('cats')
            .where('user_id', isEqualTo: userId)
            .get();
        count = snap.docs
            .where((d) => d.data()['user_id']?.toString().trim() == userId)
            .length;
      } catch (_) {}
    }

    if (count >= 1) {
      if (!context.mounted) return;
      final proceed = await showMultiCatWarningDialog(context);
      if (proceed != true) return;
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => AddCatPage(userId: userId)),
    );
  }

  /// Shows the alert popup warning the user about multi-cat limitations.
  static Future<bool?> showMultiCatWarningDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Multiple Cats Notice',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Adding more than one cat may result in reduced functionality and lower tracking accuracy.\n\n'
          'PurrClean\'s load-cell and gas sensors are optimised for single-cat tracking, so visit logs and health analytics may be combined when multiple cats share the same litter box.\n\n'
          'Would you still like to add another cat?',
          style: TextStyle(
            fontSize: 13.5,
            color: Colors.black87,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Add Anyway',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  State<AddCatPage> createState() => _AddCatPageState();
}

class _AddCatPageState extends State<AddCatPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();

  Uint8List? _photoBytes;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 50,
      maxWidth: 500,
      maxHeight: 500,
    );
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      if (mounted) {
        setState(() {
          _photoBytes = bytes;
        });
      }
    }
  }

  void _showPhotoPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              ListTile(
                leading: const RoundIcon(
                  icon: Icons.camera_alt_rounded,
                  background: AppColors.iconBgOrange,
                  iconColor: AppColors.primary,
                  size: 38,
                ),
                title: const Text(
                  'Take a Photo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const RoundIcon(
                  icon: Icons.photo_library_rounded,
                  background: AppColors.iconBgBlue,
                  iconColor: AppColors.infoBlue,
                  size: 38,
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              if (_photoBytes != null)
                ListTile(
                  leading: RoundIcon(
                    icon: Icons.delete_outline_rounded,
                    background: Colors.red.shade50,
                    iconColor: Colors.redAccent,
                    size: 38,
                  ),
                  title: const Text(
                    'Remove Photo',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.redAccent,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    setState(() => _photoBytes = null);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveCatProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final String base64Image =
          _photoBytes != null ? base64Encode(_photoBytes!) : '';

      await FirebaseFirestore.instance.collection('cats').add({
        'user_id': widget.userId,
        'cat_name': _nameController.text.trim(),
        'breed': _breedController.text.trim(),
        'weight': double.tryParse(_weightController.text.trim()) ?? 0.0,
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'image_base64': base64Image,
        'created_at': FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        const SnackBar(content: Text('Cat profile added successfully!')),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error saving cat profile: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Add Cat Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        child: DashboardCard(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CardHeader(
                  icon: Icons.pets_rounded,
                  iconBg: AppColors.iconBgOrange,
                  iconColor: AppColors.primary,
                  title: 'Personalise Your Cat',
                ),
                const SizedBox(height: 22),
                Center(
                  child: EditableAvatar(
                    photo: _photoBytes,
                    radius: 54,
                    onTap: _showPhotoPickerSheet,
                    fallback: const Icon(
                      Icons.pets_rounded,
                      size: 46,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Tap avatar to add a photo',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Cat Name
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: AppDecorations.inputDecoration(
                    hint: "Cat's Name (e.g. Mochi)",
                    icon: Icons.pets_rounded,
                  ).copyWith(labelText: "Cat's Name"),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Please enter a name'
                          : null,
                ),
                const SizedBox(height: 14),

                // Breed
                TextFormField(
                  controller: _breedController,
                  textCapitalization: TextCapitalization.words,
                  decoration: AppDecorations.inputDecoration(
                    hint: 'Breed (e.g. British Shorthair)',
                    icon: Icons.category_outlined,
                  ).copyWith(labelText: 'Breed'),
                ),
                const SizedBox(height: 14),

                // Weight & Age side-by-side
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: AppDecorations.inputDecoration(
                          hint: 'Weight (kg)',
                          icon: Icons.monitor_weight_outlined,
                        ).copyWith(labelText: 'Weight (kg)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ageController,
                        keyboardType: TextInputType.number,
                        decoration: AppDecorations.inputDecoration(
                          hint: 'Age (yrs)',
                          icon: Icons.cake_outlined,
                        ).copyWith(labelText: 'Age (Years)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),

                // Submit Button
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveCatProfile,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 20),
                    label: Text(
                      _isLoading ? 'Saving...' : 'Save Cat Profile',
                      style: AppTextStyles.buttonLabel,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppDecorations.buttonRadius,
                      ),
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
}
