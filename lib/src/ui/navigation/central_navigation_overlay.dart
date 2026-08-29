import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';

enum CentralNavDestination {
  projects,
  chats,
  providers,
  runtime,
  settings,
  newChat,
}

/// Floating central navigation hub triggered by hamburger taps.
/// Blurs background, scales content, and displays adaptive glass navigation controls.
class CentralNavigationOverlay extends StatefulWidget {
  const CentralNavigationOverlay({
    super.key,
    required this.onSelect,
    this.showNewChat = false,
  });

  final ValueChanged<CentralNavDestination> onSelect;
  final bool showNewChat;

  static Future<CentralNavDestination?> show(
    BuildContext context, {
    bool showNewChat = false,
  }) {
    return showGeneralDialog<CentralNavDestination>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss Navigation',
      barrierColor: Colors.black.withAlpha(160),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, anim1, anim2) => CentralNavigationOverlay(
        showNewChat: showNewChat,
        onSelect: (dest) => Navigator.of(context).pop(dest),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CentralNavigationOverlay> createState() =>
      _CentralNavigationOverlayState();
}

class _CentralNavigationOverlayState extends State<CentralNavigationOverlay> {
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isLandscape ? 560 : 360),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.glassStrong,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.borderActive, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(30),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Hub Title Bar
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          AppIcons.prompt,
                          size: 16,
                          color: AppColors.primaryBright,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Navigation Hub', style: AppTypography.titleSmall),
                      const Spacer(),
                      AppIconButton(
                        icon: AppIcons.close,
                        tooltip: 'Close',
                        size: 32,
                        iconSize: 16,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Navigation Grid Items
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      if (widget.showNewChat)
                        _buildNavTile(
                          icon: AppIcons.add,
                          label: 'New Chat',
                          destination: CentralNavDestination.newChat,
                          highlight: true,
                          width: isLandscape ? 160 : 140,
                        ),
                      _buildNavTile(
                        icon: AppIcons.folder,
                        label: 'Projects',
                        destination: CentralNavDestination.projects,
                        width: isLandscape ? 160 : 140,
                      ),
                      _buildNavTile(
                        icon: AppIcons.chat,
                        label: 'Chats',
                        destination: CentralNavDestination.chats,
                        width: isLandscape ? 160 : 140,
                      ),
                      _buildNavTile(
                        icon: AppIcons.model,
                        label: 'Providers',
                        destination: CentralNavDestination.providers,
                        width: isLandscape ? 160 : 140,
                      ),
                      _buildNavTile(
                        icon: AppIcons.runtime,
                        label: 'Runtime',
                        destination: CentralNavDestination.runtime,
                        width: isLandscape ? 160 : 140,
                      ),
                      _buildNavTile(
                        icon: AppIcons.settings,
                        label: 'Settings',
                        destination: CentralNavDestination.settings,
                        width: isLandscape ? 160 : 140,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String label,
    required CentralNavDestination destination,
    required double width,
    bool highlight = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelect(destination),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: highlight
                ? AppColors.primary.withAlpha(40)
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlight ? AppColors.primary : AppColors.border,
              width: 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: highlight
                    ? AppColors.primaryBright
                    : AppColors.textPrimary,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: AppTypography.button.copyWith(
                  color: highlight
                      ? AppColors.primaryBright
                      : AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
