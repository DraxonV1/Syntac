import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app.dart';
import '../../../core/app_identity.dart';
import '../../../models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_card.dart';

/// Step 6 — Progressive Create First Project
/// Features animated cycling idea phrases, inline hero editing, and progressive disclosure
/// of directory picker and action button.
class ProjectStep extends StatefulWidget {
  const ProjectStep({
    super.key,
    required this.controller,
    required this.onFinish,
    this.identity,
  });

  final AppController controller;
  final VoidCallback onFinish;
  final AppIdentity? identity;

  @override
  State<ProjectStep> createState() => _ProjectStepState();
}

class _ProjectStepState extends State<ProjectStep> {
  final List<String> _sampleIdeas = [
    'First Project',
    'My Fire Idea',
    'API Playground',
    'Demo Workspace',
    'Build Something',
  ];

  int _currentSampleIndex = 0;
  Timer? _sampleTimer;
  bool _isUserEditing = false;
  late final TextEditingController _nameController;
  late final FocusNode _nameFocusNode;
  String? _selectedFolder;

  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _sampleIdeas.first);
    _nameFocusNode = FocusNode();

    _nameFocusNode.addListener(() {
      if (_nameFocusNode.hasFocus && !_isUserEditing) {
        _stopCycling();
      }
    });

    _startCycling();
  }

  void _startCycling() {
    _sampleTimer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!_isUserEditing && mounted) {
        setState(() {
          _currentSampleIndex = (_currentSampleIndex + 1) % _sampleIdeas.length;
          _nameController.text = _sampleIdeas[_currentSampleIndex];
        });
      }
    });
  }

  void _stopCycling() {
    _sampleTimer?.cancel();
    setState(() {
      _isUserEditing = true;
    });
    _nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _nameController.text.length,
    );
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    try {
      final result = await FilePicker.getDirectoryPath();
      if (result != null && mounted) {
        setState(() {
          _selectedFolder = result;
          _errorMessage = null;
        });
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Could not open directory picker: $error';
      });
    }
  }

  Future<void> _handleCreateProject() async {
    final name = _nameController.text.trim();
    final path = _selectedFolder;

    if (name.isEmpty) {
      setState(() => _errorMessage = 'Project name is required');
      return;
    }

    if (path == null || path.isEmpty) {
      setState(() => _errorMessage = 'Choose a project folder first');
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      await widget.controller.createProject(name, path);
      if (widget.controller.lastError != null) {
        throw Exception(widget.controller.lastError);
      }

      await widget.controller.repository.saveOnboardingState(
        const OnboardingState(completed: true, step: 6),
      );

      await widget.controller.newChat();
      widget.onFinish();
    } catch (error) {
      setState(() {
        _errorMessage = error.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasName = _nameController.text.trim().isNotEmpty;
    final hasPath = _selectedFolder != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Heading
              Text(
                'Create Your',
                style: AppTypography.display.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),

              // Interactive Hero Project Name
              GestureDetector(
                onTap: () {
                  if (!_isUserEditing) _stopCycling();
                  _nameFocusNode.requestFocus();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceStrong,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isUserEditing
                          ? AppColors.borderActive
                          : AppColors.border,
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    onTap: () {
                      if (!_isUserEditing) _stopCycling();
                    },
                    onChanged: (_) {
                      setState(() {});
                    },
                    style: AppTypography.display.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryBright,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Project Name',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Progressive Step 2: Directory Selection (Reveals once interacting/named)
              AnimatedOpacity(
                opacity: hasName ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  backgroundColor: AppColors.surfaceElevated,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            AppIcons.folder,
                            size: 16,
                            color: AppColors.primaryBright,
                          ),
                          const SizedBox(width: 8),
                          Text('PROJECT DIRECTORY', style: AppTypography.label),
                          const Spacer(),
                          AppButton(
                            label: 'Choose Folder',
                            icon: AppIcons.folderOpen,
                            compact: true,
                            variant: AppButtonVariant.ghost,
                            onPressed: _pickDirectory,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedFolder ?? 'No folder selected',
                        style: AppTypography.codeSmall.copyWith(
                          color: _selectedFolder == null
                              ? AppColors.textMuted
                              : AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Error Banner
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorSubtle,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        AppIcons.error,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.errorText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Progressive Step 3: Create Button (Reveals when name & path ready)
              AnimatedOpacity(
                opacity: (hasName && hasPath) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'Create Project & Start Coding',
                    icon: AppIcons.forward,
                    loading: _isCreating,
                    onPressed: (hasName && hasPath)
                        ? _handleCreateProject
                        : null,
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
