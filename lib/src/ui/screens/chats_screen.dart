import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/app_modal.dart';
import '../widgets/empty_state.dart';
import '../widgets/status_indicator.dart';
import 'main_chat_screen.dart';

/// Standalone top-level screen for browsing, filtering, and searching chats
/// across all projects with pagination and debounced search.
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  String? _selectedProjectId;
  final int _pageSize = 20;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _filter = _searchController.text.trim().toLowerCase();
        _currentPage = 1;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openChat(Chat chat) async {
    final project = widget.controller.projects
        .where((p) => p.project.id == chat.projectId)
        .firstOrNull
        ?.project;

    if (project != null) {
      await widget.controller.openProject(project);
    }
    await widget.controller.openChat(chat);

    if (!mounted) return;
    Navigator.of(context).push(
      AppMotion.pageRoute(
        builder: (context) => MainChatScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allChats = widget.controller.chats;
    final filtered = allChats.where((chat) {
      if (_selectedProjectId != null && chat.projectId != _selectedProjectId) {
        return false;
      }
      if (_filter.isNotEmpty && !chat.title.toLowerCase().contains(_filter)) {
        return false;
      }
      return true;
    }).toList();

    final totalCount = filtered.length;
    final pagedChats = filtered.take(_currentPage * _pageSize).toList();
    final hasMore = pagedChats.length < totalCount;
    final projects = widget.controller.projects;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          AppIconButton(
            icon: AppIcons.add,
            tooltip: 'New Chat',
            size: 32,
            iconSize: 18,
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (widget.controller.selectedProject != null) {
                await widget.controller.newChat();
                if (!mounted) return;
                navigator.push(
                  AppMotion.pageRoute(
                    builder: (context) =>
                        MainChatScreen(controller: widget.controller),
                  ),
                );
              } else if (projects.isNotEmpty) {
                await widget.controller.openProject(projects.first.project);
                await widget.controller.newChat();
                if (!mounted) return;
                navigator.push(
                  AppMotion.pageRoute(
                    builder: (context) =>
                        MainChatScreen(controller: widget.controller),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Filter & Search Controls Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                // Project Filter Dropdown
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedProjectId,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    dropdownColor: AppColors.surfaceFloating,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Projects'),
                      ),
                      for (final summary in projects)
                        DropdownMenuItem<String?>(
                          value: summary.project.id,
                          child: Text(
                            summary.project.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedProjectId = val;
                        _currentPage = 1;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),

                // Search Bar
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    style: AppTypography.bodySmall,
                    decoration: InputDecoration(
                      hintText: 'Search chats...',
                      prefixIcon: const Icon(
                        AppIcons.search,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Paged Chat List
          Expanded(
            child: pagedChats.isEmpty
                ? EmptyState(
                    icon: AppIcons.chat,
                    title: _filter.isNotEmpty
                        ? 'No chats match "$_filter"'
                        : 'No conversations yet',
                    description: 'Start a conversation to see it listed here.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    itemCount: pagedChats.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == pagedChats.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: AppButton(
                              label: 'Load More Chats',
                              variant: AppButtonVariant.ghost,
                              compact: true,
                              onPressed: () {
                                setState(() {
                                  _currentPage++;
                                });
                              },
                            ),
                          ),
                        );
                      }
                      return _buildChatTile(pagedChats[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTile(Chat chat) {
    final projectName = widget.controller.projects
        .where((p) => p.project.id == chat.projectId)
        .firstOrNull
        ?.project
        .name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () => _openChat(chat),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        backgroundColor: AppColors.surfaceElevated,
        child: Row(
          children: [
            StatusIndicator.fromChat(chat.status, size: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.title,
                    style: AppTypography.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (projectName != null) ...[
                        Text(
                          projectName,
                          style: AppTypography.label.copyWith(
                            color: AppColors.primaryBright,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _timeAgo(chat.updatedAt),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 16),
              color: AppColors.surfaceFloating,
              onSelected: (action) async {
                if (action == 'rename') {
                  final textCtrl = TextEditingController(text: chat.title);
                  final newTitle = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Rename Chat'),
                      content: TextField(
                        controller: textCtrl,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Chat title',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(textCtrl.text.trim()),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                  if (newTitle != null && newTitle.isNotEmpty) {
                    await widget.controller.renameChat(chat.id, newTitle);
                  }
                } else if (action == 'delete') {
                  final confirmed = await showConfirmDialog(
                    context,
                    title: 'Delete Chat',
                    message:
                        'Delete "${chat.title}" from project "$projectName"?',
                    confirmLabel: 'Delete',
                    isDestructive: true,
                  );
                  if (confirmed) {
                    await widget.controller.deleteChat(chat.id);
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Delete',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
