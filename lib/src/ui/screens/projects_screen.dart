import 'package:flutter/material.dart';
import '../../app.dart';
import '../../models.dart';
import '../../core/app_identity.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/app_modal.dart';
import '../widgets/status_indicator.dart';
import 'create_project_dialog.dart';
import 'settings_screen.dart';

/// Clean, compact Projects screen matching the quiet developer aesthetic.
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _filterQuery = _searchController.text.trim().toLowerCase(),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final summaries = widget.controller.projects.where((summary) {
      if (_filterQuery.isEmpty) return true;
      return summary.project.name.toLowerCase().contains(_filterQuery) ||
          summary.project.folderPath.toLowerCase().contains(_filterQuery);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          AppButton(
            label: 'Create Project',
            icon: Icons.add,
            onPressed: () => showCreateProjectModal(context, widget.controller),
            compact: true,
          ),
          const SizedBox(width: 8),
          AppIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SettingsScreen(controller: widget.controller),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search filter if there are multiple projects
          if (widget.controller.projects.length > 3) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                style: AppTypography.bodySmall,
                decoration: InputDecoration(
                  hintText: 'Filter projects...',
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  suffixIcon: _filterQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: _searchController.clear,
                        )
                      : null,
                ),
              ),
            ),
          ],

          Expanded(
            child: summaries.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: summaries.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final summary = summaries[index];
                      return _buildProjectRow(summary);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 24,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No projects yet',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a project pointing to a local directory to begin coding with the agent.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Create Project',
              icon: Icons.add,
              onPressed: () =>
                  showCreateProjectModal(context, widget.controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectRow(ProjectSummary summary) {
    final hasRunning = summary.runningCount > 0;
    final hasError = summary.errorCount > 0;

    final status = hasRunning
        ? ChatStatus.running
        : (hasError ? ChatStatus.error : ChatStatus.idle);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => widget.controller.openProject(summary.project),
      onLongPress: () => _showProjectOptions(summary.project),
      child: Row(
        children: [
          // Status indicator dot
          if (hasRunning || hasError) ...[
            StatusIndicator(status: status, size: 8),
            const SizedBox(width: 10),
          ] else ...[
            const Icon(
              Icons.folder_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
          ],

          // Project Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        summary.project.name,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${summary.chatCount} ${summary.chatCount == 1 ? 'chat' : 'chats'}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.project.folderPath,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.monoSmall.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatRelativeTime(summary.project.updatedAt),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // Options Menu Button
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.more_vert,
              size: 16,
              color: AppColors.textMuted,
            ),
            padding: EdgeInsets.zero,
            onSelected: (value) async {
              if (value == 'remove') {
                _confirmRemoveProject(summary.project);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'remove',
                child: Row(
                  children: [
                    Icon(Icons.link_off, size: 14, color: AppColors.errorText),
                    SizedBox(width: 8),
                    Text(
                      'Remove from app',
                      style: TextStyle(color: AppColors.errorText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showProjectOptions(Project project) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(project.name, style: AppTypography.titleMedium),
                subtitle: Text(
                  project.folderPath,
                  style: AppTypography.monoSmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.link_off, color: AppColors.errorText),
                title: const Text(
                  'Remove from app',
                  style: TextStyle(color: AppColors.errorText),
                ),
                subtitle: const Text(
                  'Source files on disk will NOT be deleted.',
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _confirmRemoveProject(project);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveProject(Project project) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove Project',
      message:
          'Remove "${project.name}" from ${AppIdentity.instance.appDisplayName}?\n\nYour actual source files and directories on disk will remain untouched.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );

    if (confirmed) {
      await widget.controller.repository.removeProjectFromApp(project.id);
      if (widget.controller.selectedProject?.id == project.id) {
        widget.controller.selectedProject = null;
        widget.controller.chats = <Chat>[];
      }
      await widget.controller.refreshAll();
    }
  }
}
