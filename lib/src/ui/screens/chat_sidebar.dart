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
import '../widgets/status_indicator.dart';
import 'settings_screen.dart';

/// Smooth animated sidebar/drawer for navigating conversations, switching workspaces,
/// and accessing settings.
class ChatSidebar extends StatefulWidget {
  const ChatSidebar({super.key, required this.controller, this.onClose});

  final AppController controller;
  final VoidCallback? onClose;

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  bool _chatsExpanded = true;
  bool _providersExpanded = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _filter = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleNavigateHome() {
    widget.onClose?.call();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openSettings() {
    widget.onClose?.call();
    Navigator.of(context).push(
      AppMotion.pageRoute(
        builder: (context) => SettingsScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.selectedProject;
    final chats = widget.controller.chats.where((chat) {
      if (_filter.isEmpty) return true;
      return chat.title.toLowerCase().contains(_filter);
    }).toList();

    final activeChat = widget.controller.selectedChat;
    final providers = widget.controller.providers;
    final activeProvider = providers.firstOrNull;

    return Container(
      width: 290,
      color: AppColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar with Home navigation and Project Identity
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  AppButton(
                    label: 'Home',
                    icon: AppIcons.home,
                    variant: AppButtonVariant.ghost,
                    compact: true,
                    onPressed: _handleNavigateHome,
                  ),
                  const Spacer(),
                  if (widget.onClose != null)
                    AppIconButton(
                      icon: AppIcons.close,
                      tooltip: 'Close Sidebar',
                      size: 32,
                      iconSize: 18,
                      onPressed: widget.onClose,
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderSoft),

            // Project Info Banner
            if (project != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          AppIcons.folder,
                          size: 14,
                          color: AppColors.primaryBright,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            project.name,
                            style: AppTypography.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.folderPath,
                      style: AppTypography.codeSmall.copyWith(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Scrollable Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  // Dropdown Group: Chats ▼
                  _buildDropdownHeader(
                    title: 'Chats',
                    expanded: _chatsExpanded,
                    onToggle: () =>
                        setState(() => _chatsExpanded = !_chatsExpanded),
                    trailingAction: AppIconButton(
                      icon: AppIcons.add,
                      tooltip: 'New Chat',
                      size: 26,
                      iconSize: 14,
                      onPressed: () async {
                        await widget.controller.newChat();
                        widget.onClose?.call();
                      },
                    ),
                  ),
                  if (_chatsExpanded) ...[
                    if (chats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          _filter.isNotEmpty
                              ? 'No matching chats'
                              : 'No chats yet',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    else
                      for (final chat in chats)
                        _buildChatTile(
                          chat,
                          isSelected: chat.id == activeChat?.id,
                        ),
                  ],
                  const SizedBox(height: 12),

                  // Dropdown Group: Providers ▼
                  _buildDropdownHeader(
                    title: 'Providers',
                    expanded: _providersExpanded,
                    onToggle: () => setState(
                      () => _providersExpanded = !_providersExpanded,
                    ),
                  ),
                  if (_providersExpanded) ...[
                    if (activeProvider != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: AppCard(
                          padding: const EdgeInsets.all(10),
                          backgroundColor: AppColors.surfaceElevated,
                          child: Row(
                            children: [
                              AppIcons.providerLogo(
                                activeProvider.providerKey,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  activeProvider.name,
                                  style: AppTypography.bodySmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const StatusIndicator(
                                status: ChatStatus.completed,
                                size: 6,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'No providers configured',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Bottom Navigation: Settings
            const Divider(height: 1, color: AppColors.borderSoft),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                leading: const Icon(
                  AppIcons.settings,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                title: Text('Settings', style: AppTypography.bodyMedium),
                onTap: _openSettings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownHeader({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    Widget? trailingAction,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Text(
                title.toUpperCase(),
                style: AppTypography.label.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(width: 4),
              Icon(
                expanded ? AppIcons.chevronDown : AppIcons.chevronRight,
                size: 14,
                color: AppColors.textMuted,
              ),
              const Spacer(),
              ?trailingAction,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatTile(Chat chat, {required bool isSelected}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? AppColors.surfaceFloating : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            await widget.controller.openChat(chat);
            widget.onClose?.call();
          },
          onLongPress: () => _showChatOptions(chat),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                StatusIndicator.fromChat(chat.status, size: 7),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    chat.title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (chat.status == ChatStatus.running) ...[
                  const SizedBox(width: 4),
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primaryBright,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChatOptions(Chat chat) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AppIcons.edit, size: 18),
              title: const Text('Rename Chat'),
              onTap: () {
                Navigator.of(context).pop();
                _showRenameDialog(chat);
              },
            ),
            ListTile(
              leading: const Icon(
                AppIcons.delete,
                size: 18,
                color: AppColors.error,
              ),
              title: const Text(
                'Delete Chat',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _confirmDeleteChat(chat);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(Chat chat) async {
    final controller = TextEditingController(text: chat.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Chat title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await widget.controller.renameChat(chat.id, result);
    }
  }

  Future<void> _confirmDeleteChat(Chat chat) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Chat',
      message: 'Are you sure you want to delete "${chat.title}"?',
      confirmLabel: 'Delete',
      isDestructive: true,
    );

    if (confirmed) {
      await widget.controller.deleteChat(chat.id);
    }
  }
}
