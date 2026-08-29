import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../agent/system_prompt.dart';
import '../../../app.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/maximizable_surface.dart';

/// Step 3 — System Prompt Configuration
/// Direct editing, file picker, paste, reset to default, and maximizable editor.
class PromptStep extends StatefulWidget {
  const PromptStep({super.key, required this.controller, required this.onNext});

  final AppController controller;
  final VoidCallback onNext;

  @override
  State<PromptStep> createState() => _PromptStepState();
}

class _PromptStepState extends State<PromptStep> {
  late final TextEditingController _promptController;
  String? _loadedFileName;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: codingAgentSystemPrompt);
    _loadSavedPrompt();
  }

  Future<void> _loadSavedPrompt() async {
    final saved = await widget.controller.repository.readGlobalSystemPrompt();
    if (saved != null && saved.trim().isNotEmpty && mounted) {
      setState(() {
        _promptController.text = saved;
      });
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _pickPromptFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'txt', 'prompt'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final text = await file.readAsString();
        setState(() {
          _promptController.text = text;
          _loadedFileName = result.files.single.name;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load file: $error')));
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && mounted) {
      setState(() {
        _promptController.text = data.text!;
        _loadedFileName = null;
      });
    }
  }

  void _resetToDefault() {
    setState(() {
      _promptController.text = codingAgentSystemPrompt;
      _loadedFileName = null;
    });
  }

  Future<void> _handleSaveAndNext() async {
    setState(() {
      _isSaving = true;
    });
    try {
      final prompt = _promptController.text.trim();
      await widget.controller.repository.saveGlobalSystemPrompt(
        prompt.isEmpty ? codingAgentSystemPrompt : prompt,
      );
      widget.onNext();
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final charCount = _promptController.text.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text('Prompt Configuration', style: AppTypography.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Customize the instructions given to the coding agent for all projects.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 16),

          // Action Toolbar
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'Pick File',
                icon: AppIcons.file,
                compact: true,
                variant: AppButtonVariant.secondary,
                onPressed: _pickPromptFile,
              ),
              AppButton(
                label: 'Paste',
                icon: AppIcons.copy,
                compact: true,
                variant: AppButtonVariant.secondary,
                onPressed: _pasteFromClipboard,
              ),
              AppButton(
                label: 'Reset Default',
                icon: AppIcons.refresh,
                compact: true,
                variant: AppButtonVariant.ghost,
                onPressed: _resetToDefault,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // File source badge if loaded
          if (_loadedFileName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    AppIcons.file,
                    size: 14,
                    color: AppColors.primaryBright,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Loaded from: $_loadedFileName',
                    style: AppTypography.labelMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Maximizable System Prompt Surface
          MaximizableSurface(
            title: 'System Prompt Instructions',
            subtitle: '$charCount characters',
            icon: AppIcons.prompt,
            initialExpanded: true,
            child: TextField(
              controller: _promptController,
              maxLines: 14,
              minLines: 8,
              style: AppTypography.codeSmall,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Enter custom system instructions...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Next Button
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Save & Review Configuration',
              icon: AppIcons.forward,
              loading: _isSaving,
              onPressed: _handleSaveAndNext,
            ),
          ),
        ],
      ),
    );
  }
}
