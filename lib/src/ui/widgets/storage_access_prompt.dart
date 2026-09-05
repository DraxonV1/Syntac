import 'dart:io';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import 'app_buttons.dart';

Future<bool> ensureAndroidStorageAccess(
  BuildContext context,
  AppController controller,
) async {
  if (!Platform.isAndroid || await controller.hasAndroidStorageAccess()) {
    return true;
  }
  if (!context.mounted) return false;

  final openSettings = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Allow file access'),
      content: Text(
        'Syntac needs All files access to open and edit project folders you choose, including shared storage folders.',
        style: AppTypography.bodySmall,
      ),
      actions: [
        AppButton(
          label: 'Not now',
          compact: true,
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        AppButton(
          label: 'Open Settings',
          icon: AppIcons.settings,
          compact: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  if (openSettings != true) return false;
  await controller.openAndroidStorageSettings();
  return controller.hasAndroidStorageAccess();
}
