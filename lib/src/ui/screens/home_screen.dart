import 'dart:async';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/app_identity.dart';
import '../../models.dart';
import '../components/animated_hamburger.dart';
import '../navigation/central_navigation_overlay.dart';
import '../onboarding/onboarding_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/badge_chip.dart';
import '../widgets/empty_state.dart';
import 'chats_screen.dart';
import 'create_project_dialog.dart';
import 'main_chat_screen.dart';
import 'providers_screen.dart';
import 'runtime_screen.dart';
import 'settings_screen.dart';

/// Redesigned Home Screen with visual paged project grid, search bar,
/// and central floating navigation overlay.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checkedOnboarding = false;
  bool _isOnboarding = false;

  final TextEditingController _searchController = TextEditingController();
  String _filter = '';
  final int _pageSize = 20;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _maybeCheckOnboardingState();
    _searchController.addListener(() {
      setState(() {
        _filter = _searchController.text.trim().toLowerCase();
        _currentPage = 1;
      });
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    _checkedOnboarding = false;
    _isOnboarding = false;
    widget.controller.addListener(_handleControllerChanged);
    _maybeCheckOnboardingState();
  }

  void _handleControllerChanged() {
    _maybeCheckOnboardingState();
  }

  void _maybeCheckOnboardingState() {
    if (_checkedOnboarding ||
        widget.controller.loading ||
        widget.controller.lastError != null) {
      return;
    }
    unawaited(_checkOnboardingState());
  }

  Future<void> _checkOnboardingState() async {
    try {
      final state = await widget.controller.repository.readOnboardingState();
      if (!state.completed && mounted) {
        setState(() {
          _isOnboarding = true;
          _checkedOnboarding = true;
        });
        return;
      }
      if (mounted) {
        setState(() {
          _isOnboarding = false;
          _checkedOnboarding = true;
        });
      }
    } catch (error, stackTrace) {
      widget.controller.reportStartupError(
        error,
        stackTrace,
        context: 'Onboarding state check failed',
        message: 'App could not read onboarding state. Try again.',
      );
      if (mounted) {
        setState(() {
          _isOnboarding = false;
          _checkedOnboarding = true;
        });
      }
    }
  }

  void _openProject(Project project) async {
    await widget.controller.openProject(project);
    if (!mounted) return;
    Navigator.of(context).push(
      AppMotion.pageRoute(
        builder: (context) => MainChatScreen(controller: widget.controller),
      ),
    );
  }

  void _showNewProjectDialog() {
    showCreateProjectDialog(context, widget.controller);
  }

  void _openCentralNavHub() async {
    final destination = await CentralNavigationOverlay.show(context);
    if (destination == null || !mounted) return;

    switch (destination) {
      case CentralNavDestination.projects:
        break; // already on projects
      case CentralNavDestination.chats:
        Navigator.of(context).push(
          AppMotion.pageRoute(
            builder: (_) => ChatsScreen(controller: widget.controller),
          ),
        );
        break;
      case CentralNavDestination.providers:
        Navigator.of(context).push(
          AppMotion.pageRoute(
            builder: (_) => ProvidersScreen(controller: widget.controller),
          ),
        );
        break;
      case CentralNavDestination.runtime:
        Navigator.of(context).push(
          AppMotion.pageRoute(
            builder: (_) => RuntimeScreen(controller: widget.controller),
          ),
        );
        break;
      case CentralNavDestination.settings:
        Navigator.of(context).push(
          AppMotion.pageRoute(
            builder: (_) => SettingsScreen(controller: widget.controller),
          ),
        );
        break;
      case CentralNavDestination.newChat:
        if (widget.controller.projects.isNotEmpty) {
          await widget.controller.openProject(
            widget.controller.projects.first.project,
          );
          await widget.controller.newChat();
          if (mounted) {
            Navigator.of(context).push(
              AppMotion.pageRoute(
                builder: (_) => MainChatScreen(controller: widget.controller),
              ),
            );
          }
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.controller.lastError != null) {
      return _StartupErrorView(
        message: widget.controller.lastError!,
        onRetry: () {
          setState(() {
            _checkedOnboarding = false;
            _isOnboarding = false;
          });
          unawaited(widget.controller.retryInitialize());
        },
      );
    }

    if (widget.controller.loading || !_checkedOnboarding) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (_isOnboarding) {
      return OnboardingScreen(
        controller: widget.controller,
        onComplete: () {
          setState(() {
            _isOnboarding = false;
          });
          if (widget.controller.selectedProject != null) {
            Navigator.of(context).push(
              AppMotion.pageRoute(
                builder: (context) =>
                    MainChatScreen(controller: widget.controller),
              ),
            );
          }
        },
      );
    }

    final app = AppIdentity.instance;
    final update = widget.controller.availableUpdate;
    final allSummaries = widget.controller.projects;
    final filtered = allSummaries.where((s) {
      if (_filter.isEmpty) return true;
      return s.project.name.toLowerCase().contains(_filter) ||
          s.project.folderPath.toLowerCase().contains(_filter);
    }).toList();

    final pagedSummaries = filtered.take(_currentPage * _pageSize).toList();
    final hasMore = pagedSummaries.length < filtered.length;

    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final gridColumns = isLandscape ? (media.size.width > 900 ? 4 : 3) : 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: AnimatedHamburger(
              onTap: _openCentralNavHub,
              size: 38,
              iconSize: 18,
              showGlow: false,
            ),
          ),
        ),
        title: Text(app.appName, style: AppTypography.titleMedium),
        actions: [
          AppIconButton(
            icon: AppIcons.add,
            tooltip: 'New Project',
            size: 34,
            iconSize: 18,
            backgroundColor: AppColors.surfaceElevated,
            borderColor: AppColors.border,
            onPressed: _showNewProjectDialog,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // Search Field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              style: AppTypography.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search projects...',
                prefixIcon: const Icon(
                  AppIcons.search,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          if (update != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: UpdateAvailableBanner(
                version: update.version,
                channel: update.channel.name,
                mandatory: update.requiresUpgradeFrom(app.versionCode),
                notes: update.notes.take(2).join(' · '),
                onView: widget.controller.openAvailableUpdate,
              ),
            ),

          // Project Grid or Empty State
          Expanded(
            child: pagedSummaries.isEmpty
                ? EmptyState(
                    icon: AppIcons.folder,
                    title: _filter.isNotEmpty
                        ? 'No projects match "$_filter"'
                        : 'No projects yet',
                    description:
                        'Create a workspace folder to start coding with the agent.',
                    actionLabel: 'Create Project',
                    actionIcon: AppIcons.add,
                    onAction: _showNewProjectDialog,
                  )
                : RefreshIndicator(
                    onRefresh: () => widget.controller.refreshAll(),
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceElevated,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridColumns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: isLandscape ? 1.4 : 1.15,
                      ),
                      itemCount: pagedSummaries.length + (hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == pagedSummaries.length) {
                          return Center(
                            child: AppButton(
                              label: 'Load More',
                              variant: AppButtonVariant.ghost,
                              compact: true,
                              onPressed: () {
                                setState(() => _currentPage++);
                              },
                            ),
                          );
                        }
                        return _buildProjectTile(pagedSummaries[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectTile(ProjectSummary summary) {
    final project = summary.project;

    return AppCard(
      onTap: () => _openProject(project),
      padding: const EdgeInsets.all(14),
      backgroundColor: AppColors.surfaceElevated,
      borderColor: AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceFloating,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  AppIcons.folder,
                  size: 20,
                  color: AppColors.primaryBright,
                ),
              ),
              const Spacer(),
              if (summary.runningCount > 0)
                const BadgeChip(
                  label: 'Running',
                  variant: BadgeVariant.warning,
                ),
            ],
          ),
          const Spacer(),
          Text(
            project.name,
            style: AppTypography.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${summary.chatCount} chats',
                style: AppTypography.label.copyWith(color: AppColors.textMuted),
              ),
              const Spacer(),
              Text(
                _timeAgo(project.updatedAt),
                style: AppTypography.label.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ],
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

class UpdateAvailableBanner extends StatelessWidget {
  const UpdateAvailableBanner({
    super.key,
    required this.version,
    required this.channel,
    required this.mandatory,
    required this.notes,
    required this.onView,
  });

  final String version;
  final String channel;
  final bool mandatory;
  final String notes;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: AppColors.surfaceFloating,
      borderColor: mandatory ? AppColors.error : AppColors.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            mandatory ? AppIcons.warning : AppIcons.info,
            color: mandatory ? AppColors.error : AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mandatory ? 'Update required' : 'Update available',
                  style: AppTypography.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  'Syntac $version is available on $channel.',
                  style: AppTypography.bodySmall,
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notes,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'View Update',
            icon: AppIcons.externalLink,
            compact: true,
            onPressed: onView,
          ),
        ],
      ),
    );
  }
}

class _StartupErrorView extends StatelessWidget {
  const _StartupErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Startup failed', style: AppTypography.titleLarge),
                const SizedBox(height: 8),
                Text(message, style: AppTypography.bodyMedium),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Retry',
                  icon: AppIcons.refresh,
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
