// Lists and controls live Arch Linux runtime jobs.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_typography.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_card.dart';
import '../widgets/status_indicator.dart';

class RuntimeJobsScreen extends StatefulWidget {
  const RuntimeJobsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<RuntimeJobsScreen> createState() => _RuntimeJobsScreenState();
}

class _RuntimeJobsScreenState extends State<RuntimeJobsScreen> {
  Timer? _poller;
  List<Map<String, Object?>> _jobs = const <Map<String, Object?>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(milliseconds: 750), (_) {
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final jobs = await widget.controller.listLocalRuntimeJobs();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Runtime Jobs'),
        actions: [
          AppIconButton(
            icon: AppIcons.refresh,
            tooltip: 'Refresh Jobs',
            size: 32,
            iconSize: 18,
            onPressed: _loading ? null : () => _refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _jobs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.errorText),
          ),
        ),
      );
    }
    if (_jobs.isEmpty) {
      return Center(
        child: Text(
          'No runtime jobs in this session',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: _jobs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _buildJobCard(_jobs[index]),
    );
  }

  Widget _buildJobCard(Map<String, Object?> job) {
    final state = job['state']?.toString() ?? 'unknown';
    final jobId = job['jobId']?.toString() ?? '';
    final running = state == 'running';
    final stdout = job['stdoutPreview']?.toString() ?? '';
    final stderr = job['stderrPreview']?.toString() ?? '';
    return AppCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: AppColors.surfaceElevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusIndicator(
                status: running ? ChatStatus.running : _statusForState(state),
                size: 8,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$state  $jobId',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (running)
                AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.danger,
                  compact: true,
                  onPressed: () async {
                    await widget.controller.cancelLocalRuntimeJob(jobId);
                    await _refresh();
                  },
                )
              else
                AppButton(
                  label: 'Restart',
                  variant: AppButtonVariant.ghost,
                  compact: true,
                  onPressed: () async {
                    await widget.controller.restartLocalRuntimeJob(jobId);
                    await _refresh();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            job['command']?.toString() ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (job['startedAt'] != null)
                _meta('started ${_timestamp(job['startedAt'])}'),
              if (job['finishedAt'] != null)
                _meta('finished ${_timestamp(job['finishedAt'])}'),
              if (job['exitCode'] != null) _meta('exit ${job['exitCode']}'),
              if (job['durationMs'] != null) _meta('${job['durationMs']} ms'),
              if (job['failureKind'] != null)
                _meta(job['failureKind'].toString(), error: true),
            ],
          ),
          if (stdout.isNotEmpty) ...[
            const SizedBox(height: 8),
            _output('stdout', stdout),
          ],
          if (stderr.isNotEmpty) ...[
            const SizedBox(height: 8),
            _output('stderr', stderr, error: true),
          ],
        ],
      ),
    );
  }

  Widget _meta(String text, {bool error = false}) => Text(
    text,
    style: AppTypography.monoSmall.copyWith(
      color: error ? AppColors.errorText : AppColors.textMuted,
    ),
  );

  Widget _output(String label, String text, {bool error = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: error ? AppColors.errorSubtle : AppColors.codeBackground,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: error
            ? AppColors.error.withValues(alpha: 0.3)
            : AppColors.codeBorder,
      ),
    ),
    child: SelectableText(
      '$label\n$text',
      maxLines: 12,
      style: AppTypography.codeSmall,
    ),
  );

  ChatStatus _statusForState(String state) => switch (state) {
    'completed' => ChatStatus.completed,
    'cancelled' || 'interrupted' => ChatStatus.interrupted,
    _ => ChatStatus.error,
  };

  String _timestamp(Object? value) {
    final milliseconds = value is num ? value.toInt() : int.tryParse('$value');
    if (milliseconds == null) return '$value';
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
    ).toLocal().toString();
  }
}
