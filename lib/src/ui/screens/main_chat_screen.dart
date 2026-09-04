import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app.dart';
import '../../core/app_identity.dart';
import '../../models.dart';
import '../chat/agent_running_indicator.dart';
import '../chat/chat_message_list.dart';
import '../chat/composer_view.dart';
import '../chat/empty_chat_view.dart';
import '../chat/model_selector_sheet.dart';
import '../components/animated_hamburger.dart';
import '../navigation/central_navigation_overlay.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';
import 'chat_sidebar.dart';
import 'chats_screen.dart';
import 'providers_screen.dart';
import 'runtime_screen.dart';
import 'settings_screen.dart';

/// Comprehensive Project Workspace & Chat Screen supporting both center hamburger
/// empty-state transitions and active chat coding workflows.
class MainChatScreen extends StatefulWidget {
  const MainChatScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends State<MainChatScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<ComposerViewState> _composerKey =
      GlobalKey<ComposerViewState>();
  final List<Attachment> _pendingAttachments = <Attachment>[];

  @override
  Widget build(BuildContext context) {
    final project = widget.controller.selectedProject;
    final chat = widget.controller.selectedChat;
    final hasMessages = widget.controller.messages.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 780;

        if (chat == null && !hasMessages) {
          return _buildEmptyProjectCanvas(context, project);
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          drawer: isWide
              ? null
              : Drawer(
                  backgroundColor: AppColors.surface,
                  child: ChatSidebar(
                    controller: widget.controller,
                    onClose: () => Navigator.of(context).pop(),
                  ),
                ),
          body: Row(
            children: [
              if (isWide)
                SizedBox(
                  width: 280,
                  child: ChatSidebar(controller: widget.controller),
                ),
              Expanded(
                child: _buildChatCanvas(
                  context,
                  project: project,
                  chat: chat,
                  isWide: isWide,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyProjectCanvas(BuildContext context, Project? project) {
    final app = AppIdentity.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: AppIconButton(
          icon: AppIcons.back,
          tooltip: 'Back to Projects',
          size: 32,
          iconSize: 18,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          project?.name ?? app.appName,
          style: AppTypography.titleSmall,
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              project?.name ?? 'Workspace',
              style: AppTypography.display.copyWith(
                fontSize: 22,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap menu to begin coding in this project',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 36),

            // CENTER Floating Glass Hamburger
            AnimatedHamburger(
              onTap: () => _openCenterNavMenu(context),
              isCenter: true,
              showGlow: true,
            ),
          ],
        ),
      ),
    );
  }

  void _openCenterNavMenu(BuildContext context) async {
    final navigator = Navigator.of(context);
    final destination = await CentralNavigationOverlay.show(
      context,
      showNewChat: true,
    );
    if (destination == null || !mounted) return;

    switch (destination) {
      case CentralNavDestination.newChat:
        await widget.controller.newChat();
        break;
      case CentralNavDestination.chats:
        navigator.push(
          AppMotion.pageRoute(
            builder: (_) => ChatsScreen(controller: widget.controller),
          ),
        );
        break;
      case CentralNavDestination.providers:
        navigator.push(
          AppMotion.pageRoute(
            builder: (_) => ProvidersScreen(controller: widget.controller),
          ),
        );
        break;
      case CentralNavDestination.runtime:
        navigator.push(
          AppMotion.pageRoute(
            builder: (_) => RuntimeScreen(controller: widget.controller),
          ),
        );
        break;
      case CentralNavDestination.settings:
        navigator.push(
          AppMotion.pageRoute(
            builder: (_) => SettingsScreen(controller: widget.controller),
          ),
        );
        break;
      case CentralNavDestination.projects:
        navigator.pop();
        break;
    }
  }

  Widget _buildChatCanvas(
    BuildContext context, {
    required Project? project,
    required Chat? chat,
    required bool isWide,
  }) {
    final isRunning =
        chat != null && widget.controller.agentLoop.isChatRunning(chat.id);
    final hasMessages = widget.controller.messages.isNotEmpty;

    return Column(
      children: [
        // Compact Chat Header
        _buildAppBar(context, project: project, chat: chat, isWide: isWide),

        // Running indicator banner
        if (isRunning)
          AgentRunningIndicator(
            action: 'Working on code...',
            onStop: () => widget.controller.stopCurrentChat(),
          ),

        // Error banner if any
        if (widget.controller.lastError != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: AppColors.errorSubtle,
            child: Row(
              children: [
                const Icon(AppIcons.error, size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.controller.lastError!,
                    style: AppTypography.codeSmall.copyWith(
                      color: AppColors.errorText,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Message Transcript or Empty View
        Expanded(
          child: hasMessages
              ? ChatMessageList(
                  messages: widget.controller.messages,
                  toolExecutions: widget.controller.toolExecutions,
                )
              : EmptyChatView(
                  project: project,
                  onSuggestionTap: (prompt) => _handleSendMessage(prompt),
                ),
        ),

        // Floating Glass Composer
        ComposerView(
          key: _composerKey,
          isRunning: isRunning,
          selectedModelName: _resolveSelectedModelName(chat),
          attachments: _pendingAttachments,
          onSend: _handleSendMessage,
          onStop: () => widget.controller.stopCurrentChat(),
          onPickAttachment: _pickAttachment,
          onSelectModel: () => _showModelSelector(context, chat),
          onRemoveAttachment: (att) {
            setState(() => _pendingAttachments.remove(att));
          },
        ),
      ],
    );
  }

  Widget _buildAppBar(
    BuildContext context, {
    required Project? project,
    required Chat? chat,
    required bool isWide,
  }) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 6,
        bottom: 8,
        left: 10,
        right: 12,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.borderSoft, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (!isWide)
            AppIconButton(
              icon: AppIcons.menu,
              tooltip: 'Menu',
              size: 36,
              iconSize: 18,
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
          const SizedBox(width: 8),

          // Project & Chat Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  project?.name ?? AppIdentity.instance.agentLabel,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall,
                ),
                if (chat != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    chat.title,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Model Selector Pill
          GestureDetector(
            onTap: () => _showModelSelector(context, chat),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    AppIcons.model,
                    size: 14,
                    color: AppColors.primaryBright,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 100),
                    child: Text(
                      _resolveSelectedModelName(chat) ?? 'Model',
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.codeSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // New Chat Button
          AppIconButton(
            icon: AppIcons.add,
            tooltip: 'New Chat',
            size: 32,
            iconSize: 18,
            backgroundColor: AppColors.surfaceElevated,
            borderColor: AppColors.border,
            onPressed: () => widget.controller.newChat(),
          ),
        ],
      ),
    );
  }

  String? _resolveSelectedModelName(Chat? chat) {
    if (chat?.modelId != null) {
      for (final provider in widget.controller.providers) {
        final models =
            widget.controller.providerModels[provider.id] ?? <ProviderModel>[];
        for (final m in models) {
          if (m.id == chat!.modelId || m.model == chat.modelId) {
            return m.model;
          }
        }
      }
    }
    if (widget.controller.providers.isNotEmpty) {
      final firstProvider = widget.controller.providers.first;
      final models =
          widget.controller.providerModels[firstProvider.id] ??
          <ProviderModel>[];
      if (models.isNotEmpty) {
        return models.first.model;
      }
    }
    return null;
  }

  void _showModelSelector(BuildContext context, Chat? chat) {
    ModelSelectorSheet.show(
      context: context,
      providers: widget.controller.providers,
      providerModels: widget.controller.providerModels,
      modelsDevCatalog: widget.controller.modelsDevCatalog,
      selectedModelId: chat?.modelId,
      onRefreshModels: (providerId) =>
          widget.controller.refreshProviderModels(providerId),
      onModelSelected: (model) async {
        if (chat != null) {
          await widget.controller.repository.updateChat(
            chat.copyWith(modelId: model.id, providerId: model.providerId),
          );
          await widget.controller.refreshAll();
        } else if (widget.controller.selectedProject != null) {
          final newChat = await widget.controller.repository.createChat(
            projectId: widget.controller.selectedProject!.id,
            title: 'New chat',
            providerId: model.providerId,
            modelId: model.id,
          );
          await widget.controller.openChat(newChat);
          await widget.controller.refreshAll();
        }
      },
      onConfigureProviders: () {
        Navigator.of(context).push(
          AppMotion.pageRoute(
            builder: (_) => SettingsScreen(controller: widget.controller),
          ),
        );
      },
    );
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final file in result.files) {
        final path = file.path;
        if (path == null) continue;
        final ext = p.extension(path).toLowerCase();
        final kind = ['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)
            ? AttachmentKind.image
            : AttachmentKind.text;

        _pendingAttachments.add(
          Attachment.create(
            messageId: 'pending',
            path: path,
            kind: kind,
            name: file.name,
          ),
        );
      }
    });
  }

  void _handleSendMessage(String text) {
    final attachmentsToSend = List<Attachment>.of(_pendingAttachments);
    setState(() => _pendingAttachments.clear());
    unawaited(widget.controller.sendMessage(text, attachmentsToSend));
  }
}
