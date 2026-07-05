import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

class IosPrimaryButton extends StatelessWidget {
  const IosPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(16),
      onPressed: isLoading
          ? null
          : () {
              HapticFeedback.lightImpact();
              onPressed?.call();
            },
      child: isLoading
          ? const CupertinoActivityIndicator(color: Colors.white)
          : Row(
              mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppTheme.text(
                    context,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
    );

    return expanded ? SizedBox(width: double.infinity, child: child) : child;
  }
}

class IosSecondaryButton extends StatelessWidget {
  const IosSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
      borderRadius: BorderRadius.circular(16),
      onPressed: () {
        HapticFeedback.selectionClick();
        onPressed?.call();
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppColors.accent, size: 20),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: AppTheme.text(
              context,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class IosSectionHeader extends StatelessWidget {
  const IosSectionHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AppTheme.labelSecondary(context),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.labelSecondary(context),
            ),
          ),
        ],
      ],
    );
  }
}

class IosListTile extends StatelessWidget {
  const IosListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.labelPrimary(context),
                        letterSpacing: -0.4,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.labelSecondary(context),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
