import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../theme/app_styles.dart';
import 'dashboard_card.dart';

enum PhotoAction { choose, remove }

/// Circular avatar with an optional camera badge. Shows [fallback] when
/// there is no [photo].
class EditableAvatar extends StatelessWidget {
  const EditableAvatar({
    super.key,
    required this.fallback,
    this.photo,
    this.radius = 44,
    this.onTap,
  });

  final Uint8List? photo;
  final Widget fallback;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: radius,
              backgroundColor: AppColors.iconBgOrange,
              backgroundImage: photo != null ? MemoryImage(photo!) : null,
              child: photo == null ? fallback : null,
            ),
          ),
          if (onTap != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet asking whether to pick a new photo or remove the current one.
Future<PhotoAction?> showPhotoOptions(
  BuildContext context, {
  required bool hasPhoto,
}) {
  return showModalBottomSheet<PhotoAction>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(
              Icons.photo_library_outlined,
              color: AppColors.primary,
            ),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, PhotoAction.choose),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove photo'),
              onTap: () => Navigator.pop(ctx, PhotoAction.remove),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Dialog with a single text field. Returns the trimmed text, or null.
Future<String?> showNameDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, label: label, initial: initial),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initial,
  });

  final String title;
  final String label;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Name cannot be empty.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: widget.label, errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Dialog asking for the account password. Returns the password, or null.
Future<String?> showPasswordDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _PasswordDialog(),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm your password'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: 'Password',
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

/// A tappable row (icon, title, optional subtitle, chevron). Put inside a
/// [DashboardCard].
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconBg = AppColors.iconBgOrange,
    this.iconColor = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color iconBg;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              RoundIcon(
                icon: icon,
                background: iconBg,
                iconColor: iconColor,
                size: 40,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}