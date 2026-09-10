// Inspect, follow, wait for, and cancel durable runtime jobs.

import 'dart:async';

import '../core/cancellation.dart';
import '../runtime/shell_executor.dart';
import 'tool_context.dart';

mixin RuntimeJobsTool on ToolContext {
  RuntimeJobExecutor get _runtimeJobs {
    final executor = shellExecutor;
    if (executor is! RuntimeJobExecutor) {
      throw ToolFailure(
        'Persistent runtime jobs are unavailable for ${executor.runtimeId}.',
      );
    }
    return executor as RuntimeJobExecutor;
  }

  Map<String, Object?> _jobMap(Map<Object?, Object?> value) =>
      value.map((key, child) => MapEntry(key.toString(), child));

  Future<Map<String, Object?>> listRuntimeJobs() async {
    final jobs = await _runtimeJobs.listJobs();
    return {
      'category': 'jobs_list',
      'success': true,
      'jobs': jobs
          .whereType<Map<Object?, Object?>>()
          .map(_jobMap)
          .toList(growable: false),
    };
  }

  Future<Map<String, Object?>> runtimeJobStatus(String inputId) async {
    final id = inputId.trim();
    if (id.isEmpty) throw ToolFailure('jobId is required');
    final status = _jobMap(await _runtimeJobs.jobStatus(id));
    return {
      ...status,
      'jobId': id,
      'category': 'jobs_status',
      'success': status['failureKind'] != 'runtime_job_not_found',
    };
  }

  Future<Map<String, Object?>> runtimeJobLogs(
    String inputId, {
    int maxCharacters = 200_000,
    bool follow = true,
    Duration timeout = const Duration(seconds: 30),
    CancellationToken? cancellationToken,
    ToolUpdateCallback? onUpdate,
  }) async {
    final id = inputId.trim();
    if (id.isEmpty) throw ToolFailure('jobId is required');
    final limit = maxCharacters.clamp(1, 2 * 1024 * 1024).toInt();
    final started = DateTime.now();
    var current = _jobMap(await _runtimeJobs.jobLogs(id, maxCharacters: limit));
    var lastSignature = '';

    Future<void> publish(Map<String, Object?> value) async {
      final update = {
        ...value,
        'jobId': id,
        'category': 'jobs_logs_running',
        'success': true,
      };
      final signature =
          '${update['state']}|${update['stdout']}|${update['stderr']}|${update['exitCode']}';
      if (signature == lastSignature) return;
      lastSignature = signature;
      await onUpdate?.call(update);
    }

    await publish(current);
    while (follow && current['state'] == 'running') {
      cancellationToken?.throwIfCancelled();
      if (timeout != Duration.zero &&
          DateTime.now().difference(started) >= timeout) {
        current = {
          ...current,
          'jobId': id,
          'category': 'jobs_logs_follow_timeout',
          'success': true,
          'followTimedOut': true,
          'message':
              'Stopped following job logs after ${timeout.inSeconds} seconds; job is still running.',
        };
        await publish(current);
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      current = _jobMap(await _runtimeJobs.jobLogs(id, maxCharacters: limit));
      await publish(current);
    }

    return {
      ...current,
      'jobId': id,
      'category': current['followTimedOut'] == true
          ? 'jobs_logs_follow_timeout'
          : 'jobs_logs',
      'success': current['failureKind'] != 'runtime_job_not_found',
      'follow': follow,
    };
  }

  Future<Map<String, Object?>> waitForRuntimeJob(
    String inputId, {
    Duration timeout = const Duration(seconds: 120),
    CancellationToken? cancellationToken,
  }) async {
    final id = inputId.trim();
    if (id.isEmpty) throw ToolFailure('jobId is required');
    final started = DateTime.now();
    Map<String, Object?> status = _jobMap(await _runtimeJobs.jobStatus(id));
    while (status['state'] == 'running') {
      cancellationToken?.throwIfCancelled();
      if (timeout != Duration.zero &&
          DateTime.now().difference(started) >= timeout) {
        return {
          ...status,
          'jobId': id,
          'category': 'jobs_wait_timeout',
          'success': true,
          'waitTimedOut': true,
          'message':
              'Stopped waiting after ${timeout.inSeconds} seconds; job is still running.',
        };
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      status = _jobMap(await _runtimeJobs.jobStatus(id));
    }
    return {
      ...status,
      'jobId': id,
      'category': 'jobs_wait',
      'success': status['failureKind'] != 'runtime_job_not_found',
      'waited': true,
    };
  }

  Future<Map<String, Object?>> cancelRuntimeJob(String inputId) async {
    final id = inputId.trim();
    if (id.isEmpty) throw ToolFailure('jobId is required');
    final result = _jobMap(await _runtimeJobs.cancelJob(id));
    return {
      ...result,
      'jobId': id,
      'category': 'jobs_cancel',
      'success': result['failureKind'] != 'runtime_job_not_found',
    };
  }
}
