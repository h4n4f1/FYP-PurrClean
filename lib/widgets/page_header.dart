import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_styles.dart';

/// Shared gradient header used by the three main tabs (Analytics, Home,
/// Profile) so they all share the same visual language.
///
/// Layout: [leading badge] [title / subtitle] [actions...]
/// with an optional [bottom] widget rendered inside the gradient.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon,
    this.leading,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String subtitle;

  /// Icon shown in the white leading badge (ignored if [leading] is set).
  final IconData? icon;

  /// Custom widget shown in the white leading badge (e.g. the app logo).
  final Widget? leading;

  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Soft decorative circles (same on every page)
            Positioned(
              top: -40,
              right: -30,
              child: _circle(130, 0.10),
            ),
            Positioned(
              bottom: -50,
              left: -40,
              child: _circle(120, 0.07),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, topInset + 14, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _buildLeadingBadge(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'ComicRelief',
                                fontSize: 23,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final action in actions) ...[
                        const SizedBox(width: 8),
                        action,
                      ],
                    ],
                  ),
                  if (bottom != null) ...[
                    const SizedBox(height: 16),
                    bottom!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadingBadge() {
    // Frosted badge with white content, so the white PurrClean logo and the
    // icons look identical across Analytics, Home and Profile.
    return Container(
      width: 46,
      height: 46,
      padding: EdgeInsets.all(leading != null ? 7 : 0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      child: leading ??
          Icon(icon ?? Icons.pets_rounded, color: Colors.white, size: 24),
    );
  }

  static Widget _circle(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: alpha),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Round frosted icon button used in the [PageHeader] actions slot.
class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.icon,
    this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.20),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: child ?? Icon(icon, color: Colors.white, size: 21),
            ),
          ),
        ),
      ),
    );
  }
}

