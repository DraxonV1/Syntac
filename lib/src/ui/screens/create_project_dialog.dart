import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../app.dart';
import '../../core/app_identity.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';

Future<void> showCreateProjectDialog(
  BuildContext context,
  AppController controller,
) => showCreateProjectModal(context, controller);

/// Clean dialog to create a new local coding project.
Future<void> showCreateProjectModal(
  BuildContext context,
  AppController controller,
) async {
  final nameController = TextEditingController();
  final app = AppIdentity.instance;
  final defaultPath = Platform.isAndroid
      ? app.defaultSharedStoragePath
      : p.join(Directory.systemTemp.path, app.appSlug);
  final folderController = TextEditingController(text: defaultPath);
  var isSubmitting = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border, width: 1),
          ),
          title: Text('Create Project', style: AppTypography.titleLarge),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Project Name',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: AppTypography.bodyMedium,
                  decoration: const InputDecoration(
                    hintText: 'e.g. auth-service, mobile-app',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Project Folder',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final browseButton = AppIconButton(
                      icon: Icons.folder_open_outlined,
                      tooltip: 'Browse folder',
                      backgroundColor: AppColors.surfaceElevated,
                      borderColor: AppColors.border,
                      onPressed: () async {
                        final picked = await FilePicker.getDirectoryPath();
                        if (picked != null) {
                          setState(() {
                            folderController.text = picked;
                          });
                        }
                      },
                    );
                    final field = TextField(
                      controller: folderController,
                      style: AppTypography.monoSmall,
                      decoration: const InputDecoration(
                        hintText: '/path/to/folder',
                      ),
                    );
                    if (constraints.maxWidth < 360) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          field,
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: browseButton,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 8),
                        browseButton,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderSubtle, width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          Platform.isAndroid
                              ? 'Android V1 works best with shared-storage paths accessible to both this app and Termux.'
                              : 'Local-first project directory where agent tools execute.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textMuted,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.ghost,
              onPressed: () => Navigator.of(dialogContext).pop(),
              compact: true,
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'Create Project',
              variant: AppButtonVariant.primary,
              loading: isSubmitting,
              onPressed: () async {
                final name = nameController.text.trim();
                final folder = folderController.text.trim();
                if (name.isEmpty || folder.isEmpty) return;

                setState(() => isSubmitting = true);
                await controller.createProject(name, folder);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              compact: true,
            ),
          ],
        );
      },
    ),
  );
}
