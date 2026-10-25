import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../add_cat_page.dart';
import '../services/auth_service.dart';
import '../services/local_profile_store.dart';
import '../theme/app_styles.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/profile_widgets.dart';

class CatSettingsScreen extends StatefulWidget {
  final String? initialCatDocId;

  const CatSettingsScreen({super.key, this.initialCatDocId});

  @override
  State<CatSettingsScreen> createState() => _CatSettingsScreenState();
}

class _CatSettingsScreenState extends State<CatSettingsScreen> {
  final _authService = FirebaseAuthService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();

  String? _selectedDocId;
  String? _loadedDocId;
  bool _isSaving = false;
  bool _isUpdatingPhoto = false;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _catStream;
  String? _streamUid;
  final Map<String, Uint8List> _photoCache = {};

  String? get _uid => _authService.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _selectedDocId = widget.initialCatDocId;
    _ensureStream();
  }

  void _ensureStream() {
    final uid = _uid;
    if (uid != null && uid.isNotEmpty) {
      if (_catStream == null || _streamUid != uid) {
        _streamUid = uid;
        _catStream = FirebaseFirestore.instance
            .collection('cats')
            .where('user_id', isEqualTo: uid)
            .snapshots();
      }
    } else {
      _streamUid = null;
      _catStream = null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _populateControllersFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    _loadedDocId = doc.id;
    _nameController.text = (data['cat_name'] as String?)?.trim() ?? '';
    _breedController.text = (data['breed'] as String?)?.trim() ?? '';

    final weight = data['weight'];
    _weightController.text =
        (weight is num && weight > 0) ? weight.toString() : '';

    final age = data['age'];
    _ageController.text = (age is num && age > 0) ? age.toInt().toString() : '';
  }

  void _selectCat(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedDocId = doc.id;
      _populateControllersFromDoc(doc);
    });
  }

  void _openAddCat() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      _snack('Please sign in to add a cat profile.');
      return;
    }
    AddCatPage.open(context, userId: uid);
  }

  Future<void> _changePhoto(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool hasPhoto,
  ) async {
    final action = await showPhotoOptions(context, hasPhoto: hasPhoto);
    if (action == null) return;

    setState(() => _isUpdatingPhoto = true);
    try {
      if (action == PhotoAction.remove) {
        await doc.reference.update({'image_base64': ''});
        _snack('Cat photo removed.');
        return;
      }

      final bytes = await LocalProfileStore.pickImage();
      if (bytes == null) return;
      final encoded = base64Encode(bytes);
      await doc.reference.update({'image_base64': encoded});
      _snack('Cat photo updated!');
    } catch (e) {
      _snack('Failed to update cat photo.');
    } finally {
      if (mounted) setState(() => _isUpdatingPhoto = false);
    }
  }

  Future<void> _saveCatDetails(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSaving = true);
    try {
      final updatedName = _nameController.text.trim();
      final updatedBreed = _breedController.text.trim();
      final updatedWeight =
          double.tryParse(_weightController.text.trim()) ?? 0.0;
      final updatedAge = int.tryParse(_ageController.text.trim()) ?? 0;

      await doc.reference.update({
        'cat_name': updatedName,
        'breed': updatedBreed,
        'weight': updatedWeight,
        'age': updatedAge,
      });

      _snack('Saved changes for $updatedName!');
    } catch (e) {
      _snack('Could not save cat changes. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeCatProfile(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final catName =
        (doc.data()['cat_name'] as String?)?.trim().isNotEmpty == true
            ? (doc.data()['cat_name'] as String).trim()
            : 'this cat';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $catName?'),
        content: Text(
          'This permanently deletes $catName\'s profile from your account.',
        ),
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
      await doc.reference.delete();
      if (mounted) {
        setState(() {
          _selectedDocId = null;
          _loadedDocId = null;
        });
      }
      _snack('$catName removed.');
    } catch (_) {
      _snack('Could not remove cat profile.');
    }
  }

  Uint8List? _decodePhoto(String? base64String) {
    if (base64String == null || base64String.isEmpty) return null;
    final cached = _photoCache[base64String];
    if (cached != null) return cached;
    try {
      final decoded = base64Decode(base64String);
      _photoCache[base64String] = decoded;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureStream();
    final uid = _uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Cat Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        ),
        actions: [
          if (uid != null && uid.isNotEmpty)
            IconButton(
              tooltip: 'Add Another Cat',
              icon: const Icon(Icons.add_rounded),
              onPressed: _openAddCat,
            ),
        ],
      ),
      body: (uid == null || uid.isEmpty)
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Please sign in to view and manage your cats.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.textDark),
                ),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _catStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load your cats right now.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  );
                }

                // Strictly verify that user_id matches the current logged-in uid
                final docs = (snapshot.data?.docs ?? []).where((doc) {
                  final docUid = doc.data()['user_id']?.toString().trim();
                  return docUid != null && docUid == uid;
                }).toList();

                if (docs.isEmpty) {
                  return _buildEmptyState();
                }

                // Resolve active cat document
                QueryDocumentSnapshot<Map<String, dynamic>> activeDoc =
                    docs.first;
                if (_selectedDocId != null) {
                  final found =
                      docs.where((d) => d.id == _selectedDocId).toList();
                  if (found.isNotEmpty) {
                    activeDoc = found.first;
                  } else {
                    _selectedDocId = activeDoc.id;
                  }
                } else {
                  _selectedDocId = activeDoc.id;
                }

                if (_loadedDocId != activeDoc.id) {
                  _populateControllersFromDoc(activeDoc);
                }

                final activeData = activeDoc.data();
                final photoBytes =
                    _decodePhoto(activeData['image_base64'] as String?);
                final activeName =
                    (activeData['cat_name'] as String?)?.trim().isNotEmpty ==
                            true
                        ? (activeData['cat_name'] as String).trim()
                        : 'My Cat';

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  children: [
                    // Multi-cat selector bar (always visible so user can switch or add cats easily)
                    _buildCatSelectorSection(docs, activeDoc.id),
                    const SizedBox(height: 18),

                    // Main Cat Profile Editor Card
                    DashboardCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  docs.length > 1
                                      ? 'Editing: $activeName'
                                      : 'Cat Profile Details',
                                  style: AppTextStyles.cardTitle,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.iconBgOrange,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${docs.indexOf(activeDoc) + 1} of ${docs.length}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Editable Photo Avatar with smooth transition when switching cats
                            Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: Stack(
                                  key: ValueKey(activeDoc.id),
                                  alignment: Alignment.center,
                                  children: [
                                    EditableAvatar(
                                      photo: photoBytes,
                                      radius: 52,
                                      onTap: _isUpdatingPhoto
                                          ? null
                                          : () => _changePhoto(
                                                activeDoc,
                                                photoBytes != null,
                                              ),
                                      fallback: const Icon(
                                        Icons.pets_rounded,
                                        size: 46,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    if (_isUpdatingPhoto)
                                      const SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                'Tap photo to update',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Cat Name
                            TextFormField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: AppDecorations.inputDecoration(
                                hint: "Cat's Name",
                                icon: Icons.pets_rounded,
                              ).copyWith(labelText: "Cat's Name"),
                              validator: (val) =>
                                  (val == null || val.trim().isEmpty)
                                      ? 'Please enter your cat\'s name'
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
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
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
                            const SizedBox(height: 22),

                            // Save Button
                            SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving
                                    ? null
                                    : () => _saveCatDetails(activeDoc),
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check_rounded, size: 20),
                                label: Text(
                                  _isSaving ? 'Saving...' : 'Save Changes',
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                  ),
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
                    const SizedBox(height: 18),

                    // Remove Selected Cat Button
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: () => _removeCatProfile(activeDoc),
                        icon: const Icon(Icons.delete_outline),
                        label: Text('Remove $activeName'),
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
                );
              },
            ),
    );
  }

  Widget _buildCatSelectorSection(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String activeId,
  ) {
    return DashboardCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                docs.length > 1
                    ? 'Your Cats (${docs.length}) — Tap to Switch'
                    : 'Your Registered Cat',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openAddCat,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_circle_outline_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Add Cat',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final doc in docs) ...[
                  _buildCatChip(doc, isSelected: doc.id == activeId),
                  const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatChip(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool isSelected,
  }) {
    final data = doc.data();
    final name =
        (data['cat_name'] as String?)?.trim().isNotEmpty == true
            ? (data['cat_name'] as String).trim()
            : 'My Cat';
    final photoBytes = _decodePhoto(data['image_base64'] as String?);

    return GestureDetector(
      onTap: () => _selectCat(doc),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected ? null : AppColors.inputFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : Colors.grey.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor:
                  isSelected ? Colors.white : AppColors.iconBgOrange,
              backgroundImage:
                  photoBytes != null ? MemoryImage(photoBytes) : null,
              child: photoBytes == null
                  ? Icon(
                      Icons.pets_rounded,
                      size: 16,
                      color: isSelected ? AppColors.primary : AppColors.textDark,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DashboardCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.iconBgOrange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.pets_rounded,
                  size: 38,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Cats Registered Yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your first cat profile to personalise PurrClean and track their health.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _openAddCat,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Add Cat Profile',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
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
    );
  }
}