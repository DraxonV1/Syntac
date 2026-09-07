// Borderless glass navigation hub arranged around one central close control.

import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';

enum CentralNavDestination {
  projects,
  chats,
  providers,
  runtime,
  settings,
  newChat,
}

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
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, anim1, anim2) => CentralNavigationOverlay(
        showNewChat: showNewChat,
        onSelect: (destination) => Navigator.of(context).pop(destination),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1.0).animate(curved),
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
    final size = media.orientation == Orientation.landscape ? 380.0 : 336.0;
    final maxSize = media.size.shortestSide - 32;
    final hubSize = size < maxSize ? size : maxSize;

    return Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Center(
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: SizedBox(
                width: hubSize,
                height: hubSize,
                child: Stack(
                  children: [
                    Positioned(
                      top: hubSize * 0.12,
                      left: 0,
                      right: 0,
                      child: _buildNavTile(
                        icon: AppIcons.folder,
                        label: 'Projects',
                        destination: CentralNavDestination.projects,
                      ),
                    ),
                    Positioned(
                      top: hubSize * 0.40,
                      left: 12,
                      right: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildNavTile(
                            icon: AppIcons.chat,
                            label: 'Chats',
                            destination: CentralNavDestination.chats,
                          ),
                          _buildCloseButton(context),
                          _buildNavTile(
                            iconWidget: AppIcons.providerLogo('grok', size: 23),
                            label: 'Providers',
                            destination: CentralNavDestination.providers,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      bottom: hubSize * 0.13,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildNavTile(
                            iconWidget: AppIcons.runtimeLogo('arch', size: 23),
                            label: 'Runtime',
                            destination: CentralNavDestination.runtime,
                          ),
                          _buildNavTile(
                            icon: AppIcons.settings,
                            label: 'Settings',
                            destination: CentralNavDestination.settings,
                          ),
                        ],
                      ),
                    ),
                    if (widget.showNewChat)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: TextButton.icon(
                            onPressed: () =>
                                widget.onSelect(CentralNavDestination.newChat),
                            icon: const Icon(AppIcons.add, size: 14),
                            label: const Text('New Chat'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textMuted,
                              textStyle: AppTypography.caption,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Close navigation',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(),
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(AppIcons.close, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTile({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required CentralNavDestination destination,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onSelect(destination),
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 92,
            height: 68,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconWidget ??
                    Icon(
                      icon ?? AppIcons.info,
                      size: 23,
                      color: AppColors.textPrimary,
                    ),
                const SizedBox(height: 5),
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
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
