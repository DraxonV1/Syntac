// Execute bounded shell commands and expose truncated output artifacts.

import 'dart:async';

import '../core/cancellation.dart';
import 'tool_context.dart';

mixin BashTool on ToolContext {
  Future<Map<String, Object?>> runBash(
    String command, {
    required Duration timeout,
    bool background = false,
    CancellationToken? cancellationToken,
    ToolUpdateCallback? onUpdate,
  }) async {
    if (command.trim().isEmpty) throw ToolFailure('Command is required');
    final risk = assessCommandRisk(command, background: background);
    if (commandRequiresApproval(risk)) {
      final approval = commandApproval;
      if (approval == null) {
        return {
          'command': command,
          'workingDirectory': projectRoot,
          'success': false,
          'runtime': shellExecutor.runtimeId,
          'category': 'command_approval_required',
          'failureKind': 'command_approval_required',
          'risk': commandRiskLabel(risk),
          'message': 'Command requires explicit user approval.',
        };
      }
      final approved = await approval(
        CommandApprovalRequest(
          command: command,
          workingDirectory: projectRoot,
          runtime: shellExecutor.runtimeId,
          risk: risk,
          reason: 'Shell command classified as ${commandRiskLabel(risk)}.',
          timeout: timeout,
          background: background,
        ),
      );
      if (!approved) {
        return {
          'command': command,
          'workingDirectory': projectRoot,
          'success': false,
          'runtime': shellExecutor.runtimeId,
          'category': 'command_denied',
          'failureKind': 'command_denied',
          'risk': commandRiskLabel(risk),
          'message': 'User denied command execution.',
        };
      }
    }
    var liveStdout = '';
    var liveStderr = '';
    var liveStdoutTruncated = false;
    var liveStderrTruncated = false;
    int? liveStdoutOriginalLength;
    int? liveStderrOriginalLength;
    final result = await shellExecutor.run(
      command: command,
      workingDirectory: projectRoot,
      timeout: timeout,
      background: background,
      cancellationToken: cancellationToken,
      onOutput: onUpdate == null
          ? null
          : (update) async {
              if (update.stdout != null) {
                liveStdout = update.stdout!;
                liveStdoutTruncated = update.stdoutTruncated;
                liveStdoutOriginalLength = update.stdoutOriginalLength;
              }
              if (update.stderr != null) {
                liveStderr = update.stderr!;
                liveStderrTruncated = update.stderrTruncated;
                liveStderrOriginalLength = update.stderrOriginalLength;
              }
              final output = boundedOutputPair(liveStdout, liveStderr);
              await onUpdate({
                'command': command,
                'workingDirectory': projectRoot,
                'success': false,
                'runtime': shellExecutor.runtimeId,
                'category': 'running',
                'stdout': output.stdout,
                'stderr': output.stderr,
                if (output.stdoutTruncated || liveStdoutTruncated)
                  'stdoutTruncated': true,
                if (output.stderrTruncated || liveStderrTruncated)
                  'stderrTruncated': true,
                ...?liveStdoutOriginalLength == null
                    ? null
                    : {'stdoutOriginalLength': liveStdoutOriginalLength},
                ...?liveStderrOriginalLength == null
                    ? null
                    : {'stderrOriginalLength': liveStderrOriginalLength},
              });
            },
    );
    final json = result.toJson();
    final output = boundedOutputPair(result.stdout, result.stderr);
    final artifactUri = output.stdoutTruncated || output.stderrTruncated
        ? await writeOutputArtifact(
            command: command,
            stdout: result.stdout,
            stderr: result.stderr,
          )
        : null;
    final notice = artifactUri == null
        ? null
        : 'Output truncated: showing first ${ToolContext.maxPreviewLines} lines. Read full output with read path $artifactUri.';
    final rendered = notice == null
        ? output
        : boundedOutputPair(
            '${output.stdout}\n\n$notice',
            output.stderr,
            limitLines: false,
          );
    json['stdout'] = rendered.stdout;
    json['stderr'] = rendered.stderr;
    if (artifactUri != null) {
      json['outputTruncated'] = true;
      json['outputArtifact'] = artifactUri;
      json['truncationNotice'] = notice;
    }
    if (rendered.stdoutTruncated || output.stdoutTruncated) {
      json['stdoutTruncated'] = true;
      json.putIfAbsent('stdoutOriginalLength', () => result.stdout.length);
    }
    if (rendered.stderrTruncated || output.stderrTruncated) {
      json['stderrTruncated'] = true;
      json.putIfAbsent('stderrOriginalLength', () => result.stderr.length);
    }
    final failureKind = result.failureKind;
    final category = result.background
        ? 'background_started'
        : result.cancelled
        ? 'cancelled'
        : failureKind == 'TermuxBackgroundRestricted'
        ? 'termux_background_restricted'
        : failureKind != null
        ? 'runtime_failure'
        : result.timedOut
        ? 'timeout'
        : result.exitCode == 0
        ? 'success'
        : 'command_exit_error';
    return {
      'command': command,
      'workingDirectory': projectRoot,
      'success': result.success,
      'runtime': shellExecutor.runtimeId,
      'category': category,
      'risk': commandRiskLabel(risk),
      ...?failureKind == null ? null : {'failureKind': failureKind},
      if (result.timedOut)
        'message': 'Command exceeded ${timeout.inSeconds} seconds.',
      if (failureKind == 'CallbackFailed')
        'message': 'Runtime did not return a command result callback.',
      if (failureKind == 'TermuxBackgroundRestricted')
        'message':
            'Android blocked starting a Termux command while Syntac was in the background.',
      ...json,
    };
  }
}
