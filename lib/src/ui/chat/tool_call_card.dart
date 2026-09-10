// Compact tool timeline card with direct output, previews, copy, and details.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/badge_chip.dart';
import '../widgets/status_indicator.dart';
import '../theme/app_icons.dart';
import '../theme/app_motion.dart';
import 'syntax_highlighted_code.dart';

/// Compact, expandable tool call card matching the developer aesthetics.
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({
    super.key,
    required this.execution,
    this.initiallyExpanded,
  });

  final ToolExecution execution;
  final bool? initiallyExpanded;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  static const int _codePreviewCharacters = 4000;

  @override
  void initState() {
    super.initState();
    // Default collapsed unless running or error occurred
    _expanded =
        widget.initiallyExpanded ??
        (widget.execution.status == ToolExecutionStatus.running ||
            widget.execution.status == ToolExecutionStatus.error);
  }

  @override
  void didUpdateWidget(ToolCallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.execution.status != oldWidget.execution.status &&
        widget.execution.status == ToolExecutionStatus.error) {
      _expanded = true;
    }
  }

  Map<String, Object?> _decode(String? json) {
    if (json == null || json.isEmpty) return <String, Object?>{};
    if (json.length > maxToolCardJsonPreviewCharacters) {
      return <String, Object?>{
        'recovered': true,
        'originalLength': json.length,
        'raw': truncatePersistedText(
          json,
          maxLength: maxToolCardJsonPreviewCharacters,
        ),
      };
    }
    try {
      final decoded = jsonDecode(json);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{'raw': truncatePersistedText(json)};
    }
  }

  int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Map<String, Object?> _toolResult(Map<String, Object?> canonicalResult) {
    final nested = canonicalResult['result'];
    if (nested is Map) return nested.cast<String, Object?>();
    return canonicalResult;
  }

  String _canonicalToolName(String name) => switch (name.toLowerCase()) {
    'jobs_list' => 'jobs.list',
    'jobs_status' => 'jobs.status',
    'jobs_logs' => 'jobs.logs',
    'jobs_wait' => 'jobs.wait',
    'jobs_cancel' => 'jobs.cancel',
    _ => name.toLowerCase(),
  };

  String _formatToolName(String name) {
    return switch (_canonicalToolName(name)) {
      'read' => 'Read',
      'display_image' => 'Display image',
      'write' => 'Write',
      'apply_patch' => 'Apply patch',
      'delete' => 'Delete',
      'list' => 'List',
      'glob' => 'Glob',
      'search' => 'Search',
      'bash' => 'Bash',
      'jobs.list' => 'Jobs list',
      'jobs.status' => 'Job status',
      'jobs.logs' => 'Job logs',
      'jobs.wait' => 'Wait for job',
      'jobs.cancel' => 'Cancel job',
      'copy' => 'Copy',
      _ => name,
    };
  }

  IconData _iconForTool(String name) {
    return switch (_canonicalToolName(name)) {
      'read' => Icons.description_outlined,
      'display_image' => Icons.image_outlined,
      'write' => Icons.note_add_outlined,
      'apply_patch' => Icons.build_circle_outlined,
      'delete' => Icons.delete_outline,
      'list' => Icons.folder_open_outlined,
      'glob' => Icons.manage_search_outlined,
      'search' => Icons.search,
      'bash' => Icons.terminal,
      'jobs.list' ||
      'jobs.status' ||
      'jobs.logs' ||
      'jobs.wait' ||
      'jobs.cancel' => Icons.work_history_outlined,
      'copy' => Icons.content_copy_outlined,
      _ => Icons.build_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final args = _decode(widget.execution.argumentsJson);
    final canonicalResult = _decode(widget.execution.resultJson);
    final result = _toolResult(canonicalResult);
    final isRunning = widget.execution.status == ToolExecutionStatus.running;
    final isError = widget.execution.status == ToolExecutionStatus.error;

    final targetText = _extractTargetText(widget.execution.name, args);
    final metaBadge = _buildMetaBadge(widget.execution.name, args, result);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError
              ? AppColors.error.withValues(alpha: 0.3)
              : isRunning
              ? AppColors.warning.withValues(alpha: 0.3)
              : AppColors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  StatusIndicator.fromTool(widget.execution.status, size: 7),
                  const SizedBox(width: 8),
                  Icon(
                    _iconForTool(widget.execution.name),
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatToolName(widget.execution.name),
                    style: AppTypography.monoSmall.copyWith(
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      targetText,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.monoSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (metaBadge != null) ...[
                    const SizedBox(width: 6),
                    metaBadge,
                  ],
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded Content
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: AppColors.borderSubtle, height: 12),
                  if (_canonicalToolName(widget.execution.name) == 'bash')
                    _buildBashDetails(args, result)
                  else if (_canonicalToolName(widget.execution.name) ==
                      'search')
                    _buildSearchDetails(args, result)
                  else
                    _buildGenericDetails(args, result),
                  if (widget.execution.error != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.errorSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 14,
                            color: AppColors.errorText,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SelectableText(
                              widget.execution.error!,
                              style: AppTypography.monoSmall.copyWith(
                                color: AppColors.errorText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _extractTargetText(String toolName, Map<String, Object?> args) {
    return switch (_canonicalToolName(toolName)) {
      'read' || 'write' || 'delete' || 'list' => args['path']?.toString() ?? '',
      'apply_patch' => 'multi-file patch',
      'glob' => args['pattern']?.toString() ?? '',
      'copy' =>
        '${args['source']?.toString() ?? ''} → ${args['target']?.toString() ?? ''}',
      'search' => '"${args['query']?.toString() ?? ''}"',
      'bash' => args['command']?.toString() ?? '',
      'jobs.status' ||
      'jobs.logs' ||
      'jobs.wait' ||
      'jobs.cancel' => args['jobId']?.toString() ?? '',
      _ => args.entries.map((e) => '${e.key}: ${e.value}').take(2).join(', '),
    };
  }

  Widget? _buildMetaBadge(
    String toolName,
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    if (widget.execution.status == ToolExecutionStatus.running) {
      return BadgeChip.warning(label: 'Running');
    }
    if (widget.execution.status == ToolExecutionStatus.cancelled) {
      return BadgeChip.error(label: 'Cancelled');
    }
    if (widget.execution.status == ToolExecutionStatus.error) {
      if (_canonicalToolName(toolName) == 'bash') {
        final exitCode = result['exitCode'];
        if (exitCode != null && exitCode.toString() != '-1') {
          return BadgeChip.error(label: 'Exit $exitCode');
        }
        final category = result['category']?.toString();
        if (category != null && category.isNotEmpty) {
          return BadgeChip.error(label: category);
        }
      }
      return BadgeChip.error(label: 'Failed');
    }

    return switch (_canonicalToolName(toolName)) {
      'apply_patch' => () {
        final files = result['changedFiles'];
        if (files is List) {
          return BadgeChip.neutral(label: '${files.length} files');
        }
        return null;
      }(),
      'glob' => () {
        final count = _intValue(result['count']);
        return count == null
            ? null
            : BadgeChip.neutral(label: '$count matches');
      }(),
      'jobs.list' => () {
        final jobs = result['jobs'];
        return jobs is List
            ? BadgeChip.neutral(label: '${jobs.length} jobs')
            : null;
      }(),
      'jobs.status' || 'jobs.logs' || 'jobs.wait' || 'jobs.cancel' => () {
        final state = result['state']?.toString();
        return state == null ? null : BadgeChip.neutral(label: state);
      }(),
      'search' => () {
        final results = result['results'];
        if (results is List) {
          return BadgeChip.neutral(label: '${results.length} matches');
        }
        return null;
      }(),
      'bash' => () {
        final durationMs = _intValue(result['durationMs']);
        final exitCode = _intValue(result['exitCode']);
        final durationStr = durationMs != null
            ? '${(durationMs / 1000).toStringAsFixed(1)}s'
            : '';
        if (exitCode != null && exitCode != 0) {
          return BadgeChip.error(label: 'exit $exitCode');
        }
        if (durationStr.isNotEmpty) {
          return BadgeChip.success(label: durationStr);
        }
        return BadgeChip.success(label: 'Done');
      }(),
      'read' => () {
        final totalLines = _intValue(result['totalLines']);
        if (totalLines != null) {
          return BadgeChip.neutral(label: '$totalLines lines');
        }
        return null;
      }(),
      'write' => () {
        final bytes = _intValue(result['bytes']);
        if (bytes != null) {
          return BadgeChip.neutral(label: _formatBytes(bytes));
        }
        return null;
      }(),
      'delete' => BadgeChip.neutral(label: 'Deleted'),
      'list' => () {
        final entries = result['entries'];
        if (entries is List) {
          return BadgeChip.neutral(label: '${entries.length} items');
        }
        return null;
      }(),
      _ => null,
    };
  }

  Widget _buildBashDetails(
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    final command =
        result['command']?.toString() ?? args['command']?.toString() ?? '';
    final workingDirectory = result['workingDirectory']?.toString() ?? '';
    final stdout = result['stdout']?.toString() ?? '';
    final stderr = result['stderr']?.toString() ?? '';
    final durationMs = _intValue(result['durationMs']);
    final exitCode = result['exitCode'];
    final category = result['category']?.toString();
    final failureKind = result['failureKind']?.toString();
    final message = result['message']?.toString();
    final timedOut = result['timedOut'] == true;
    final cancelled = result['cancelled'] == true;

    final outputText = stdout.isNotEmpty || stderr.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (command.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.codeBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.warning, width: 1),
            ),
            child: Text(
              '\$ $command',
              style: AppTypography.monoSmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        if (outputText) const SizedBox(height: 6),
        if (stdout.isNotEmpty)
          _buildPlainOutputBox(
            stdout,
            copyContent: stdout,
            language: 'bash',
            maxHeight: 220,
          ),
        if (stdout.isNotEmpty && stderr.isNotEmpty) const SizedBox(height: 6),
        if (stderr.isNotEmpty)
          _buildPlainOutputBox(
            stderr,
            copyContent: stderr,
            language: 'text',
            isError: true,
            maxHeight: 160,
          ),
        if (!outputText && message == null)
          Text(
            '(no output)',
            style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
          ),
        if (message != null && message.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildPlainOutputBox(message, isError: true),
        ],
        if (workingDirectory.isNotEmpty ||
            exitCode != null ||
            durationMs != null ||
            category != null ||
            failureKind != null ||
            timedOut ||
            cancelled) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (exitCode != null)
                Text('exit $exitCode', style: AppTypography.monoSmall),
              if (durationMs != null)
                Text(
                  '${(durationMs / 1000).toStringAsFixed(2)}s',
                  style: AppTypography.monoSmall,
                ),
              if (category != null)
                Text(category, style: AppTypography.monoSmall),
              if (failureKind != null)
                Text(failureKind, style: AppTypography.monoSmall),
              if (timedOut) Text('timed out', style: AppTypography.monoSmall),
              if (cancelled) Text('cancelled', style: AppTypography.monoSmall),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSearchDetails(
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    final results = result['results'];
    if (results is! List || results.isEmpty) {
      return Text(
        'No matches found.',
        style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MATCHES (${results.length})',
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: AppColors.codeBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.codeBorder, width: 1),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: results.length,
            separatorBuilder: (context, index) =>
                Divider(color: AppColors.borderSubtle, height: 6),
            itemBuilder: (context, index) {
              final item = results[index];
              if (item is! Map) return const SizedBox.shrink();
              final path = item['path']?.toString() ?? '';
              final match = item['match']?.toString() ?? '';
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      path,
                      style: AppTypography.monoSmall.copyWith(
                        color: AppColors.accentText,
                      ),
                    ),
                  ),
                  if (match != 'filename' && match.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        match,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.monoSmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGenericDetails(
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    return switch (_canonicalToolName(widget.execution.name)) {
      'read' || 'display_image' => _buildImageOrReadDetails(args, result),
      'write' => _buildWriteDetails(args, result),
      'apply_patch' => _buildPatchDetails(result),
      'delete' => _buildDeleteDetails(args, result),
      'list' => _buildListDetails(args, result),
      'jobs.logs' => _buildJobLogsDetails(result),
      'jobs.list' ||
      'jobs.status' ||
      'jobs.wait' ||
      'jobs.cancel' => _buildJobDetails(result),
      _ => _buildJsonDetails(args, result),
    };
  }

  Widget _buildImageOrReadDetails(
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    final path = result['path']?.toString() ?? args['path']?.toString() ?? '';
    if (result['kind'] == 'image') {
      final filePath = result['filePath']?.toString() ?? '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildKeyValueDetails([
            ('Path', path),
            ('Type', result['mimeType']?.toString() ?? 'image'),
            ('Size', _formatBytes(_intValue(result['bytes']) ?? 0)),
            if (result['width'] != null && result['height'] != null)
              ('Dimensions', '${result['width']} × ${result['height']}'),
          ], copyValue: path),
          if (filePath.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: Image.file(
                File(filePath),
                fit: BoxFit.contain,
                errorBuilder: (_, error, stackTrace) =>
                    _buildNotReadableImage(),
              ),
            ),
          ],
        ],
      );
    }
    final content = result['content']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCodeBox(title: 'PATH', content: path, copyable: true),
        const SizedBox(height: 6),
        Text(
          'Lines ${result['startLine'] ?? '?'}-${result['endLine'] ?? '?'} of ${result['totalLines'] ?? '?'} · ${result['bytes'] ?? '?'} bytes',
          style: AppTypography.monoSmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        _buildCodeBox(
          title: 'CONTENT',
          content: content,
          copyable: true,
          maxHeight: 220,
        ),
      ],
    );
  }

  Widget _buildNotReadableImage() => Text(
    'Not Readable',
    style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
  );

  Widget _buildWriteDetails(
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    final path = result['path']?.toString() ?? args['path']?.toString() ?? '';
    final content = args['content']?.toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKeyValueDetails([
          ('Path', path),
          ('Bytes written', result['bytes']?.toString() ?? 'unknown'),
          if (result['modifiedAt'] != null)
            ('Modified', result['modifiedAt'].toString()),
        ], copyValue: path),
        if (content != null) ...[
          const SizedBox(height: 6),
          Text(
            'CONTENT',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          _buildPlainOutputBox(
            content,
            copyContent: content,
            language: _languageForPath(path),
            maxHeight: 220,
          ),
        ],
      ],
    );
  }

  Widget _buildPatchDetails(Map<String, Object?> result) {
    final patch = result['diff']?.toString() ?? '';
    return _buildDiffBox(
      title: 'PATCH',
      content: patch.isEmpty ? '(no patch)' : patch,
      copyContent: patch,
      maxHeight: 260,
    );
  }

  Widget _buildJobDetails(Map<String, Object?> result) {
    return _buildKeyValueDetails([
      ('Job', result['jobId']?.toString() ?? ''),
      ('State', result['state']?.toString() ?? 'unknown'),
      if (result['startedAt'] != null)
        ('Started', _formatTimestamp(result['startedAt'])),
      if (result['finishedAt'] != null)
        ('Finished', _formatTimestamp(result['finishedAt'])),
      if (result['exitCode'] != null)
        ('Exit code', result['exitCode'].toString()),
      if (result['durationMs'] != null)
        ('Duration', '${result['durationMs']} ms'),
      if (result['failureKind'] != null)
        ('Failure', result['failureKind'].toString()),
    ]);
  }

  Widget _buildJobLogsDetails(Map<String, Object?> result) {
    final stdout = result['stdout']?.toString() ?? '';
    final stderr = result['stderr']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildJobDetails(result),
        if (stdout.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildPlainOutputBox(
            stdout,
            copyContent: stdout,
            language: 'text',
            maxHeight: 240,
          ),
        ],
        if (stderr.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildPlainOutputBox(
            stderr,
            copyContent: stderr,
            language: 'text',
            isError: true,
            maxHeight: 180,
          ),
        ],
        if (stdout.isEmpty && stderr.isEmpty)
          Text(
            result['message']?.toString() ?? '(no output)',
            style: AppTypography.monoSmall.copyWith(color: AppColors.textMuted),
          ),
      ],
    );
  }

  String _formatTimestamp(Object? value) {
    final milliseconds = _intValue(value);
    if (milliseconds == null) return value?.toString() ?? 'unknown';
    return DateTime.fromMillisecondsSinceEpoch(milliseconds).toIso8601String();
  }

  String? _languageForPath(String path) {
    final basename = path.split(RegExp(r'[\\\\/]')).last;
    final dot = basename.lastIndexOf('.');
    if (dot < 0 || dot == basename.length - 1) return null;
    return basename.substring(dot + 1);
  }

  Widget _buildDeleteDetails(
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    final path = result['path']?.toString() ?? args['path']?.toString() ?? '';
    return _buildKeyValueDetails([
      ('Path', path),
      ('Deleted', result['deleted']?.toString() ?? 'unknown'),
      if (result['reason'] != null) ('Reason', result['reason'].toString()),
    ], copyValue: path);
  }

  Widget _buildListDetails(
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    final path = result['path']?.toString() ?? args['path']?.toString() ?? '.';
    final entries = result['entries'];
    final content = entries is List
        ? entries
              .whereType<Map>()
              .map(
                (entry) =>
                    '${entry['type'] ?? 'unknown'}\t${entry['path'] ?? ''}',
              )
              .join('\n')
        : const JsonEncoder.withIndent('  ').convert(result);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCodeBox(title: 'PATH', content: path, copyable: true),
        const SizedBox(height: 6),
        _buildCodeBox(
          title: 'ENTRIES',
          content: content.isEmpty ? '(empty)' : content,
          copyable: true,
          maxHeight: 220,
        ),
      ],
    );
  }

  Widget _buildJsonDetails(
    Map<String, Object?> args,
    Map<String, Object?> result,
  ) {
    final hasArgs = args.isNotEmpty;
    final hasResult = result.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasArgs)
          _buildCodeBox(
            title: 'ARGUMENTS',
            content: const JsonEncoder.withIndent('  ').convert(args),
            maxHeight: 120,
            copyable: true,
          ),
        if (hasResult) ...[
          if (hasArgs) const SizedBox(height: 6),
          _buildCodeBox(
            title: 'RESULT',
            content: const JsonEncoder.withIndent('  ').convert(result),
            maxHeight: 160,
            copyable: true,
          ),
        ],
      ],
    );
  }

  Widget _buildKeyValueDetails(
    List<(String, String)> rows, {
    String? copyValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SelectableText(
              '${row.$1}: ${row.$2}',
              style: AppTypography.monoSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        if (copyValue != null && copyValue.isNotEmpty)
          _buildCodeBox(
            title: 'COPY VALUE',
            content: copyValue,
            copyable: true,
          ),
      ],
    );
  }

  String _previewText(String content) {
    if (content.length <= _codePreviewCharacters) return content;
    final omitted = content.length - _codePreviewCharacters;
    return '${content.substring(0, _codePreviewCharacters)}\n'
        '[preview truncated $omitted characters; copy gets full value]';
  }

  TextStyle _diffLineStyle(String line) {
    if (line.startsWith('+')) {
      return AppTypography.monoSmall.copyWith(color: AppColors.successText);
    }
    if (line.startsWith('-')) {
      return AppTypography.monoSmall.copyWith(color: AppColors.errorText);
    }
    return AppTypography.monoSmall.copyWith(color: AppColors.textPrimary);
  }

  Widget _buildDiffBox({
    required String title,
    required String content,
    String? copyContent,
    double maxHeight = 220,
  }) {
    final visibleContent = _previewText(content);
    final lines = visibleContent.split('\n');
    final spans = <TextSpan>[
      for (var i = 0; i < lines.length; i++)
        TextSpan(
          text:
              '${(i + 1).toString().padLeft(4)}  ${lines[i]}'
              '${i == lines.length - 1 ? '' : '\n'}',
          style: _diffLineStyle(lines[i]),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: copyContent ?? content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Text(
                'Copy',
                style: AppTypography.caption.copyWith(
                  color: AppColors.accentText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.codeBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.codeBorder, width: 1),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SelectableText.rich(TextSpan(children: spans)),
          ),
        ),
      ],
    );
  }

  Widget _buildPlainOutputBox(
    String content, {
    String? copyContent,
    String? language,
    bool isError = false,
    double maxHeight = 180,
  }) {
    final visibleContent = _previewText(content);
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorSubtle : AppColors.codeBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isError
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.codeBorder,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: copyContent ?? content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          child: SyntaxHighlightedCode(
            text: visibleContent,
            language: language,
          ),
        ),
      ),
    );
  }

  Widget _buildCodeBox({
    required String title,
    required String content,
    String? copyContent,
    bool copyable = false,
    bool isError = false,
    double? maxHeight,
  }) {
    final visibleContent = _previewText(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: AppTypography.caption.copyWith(
                color: isError ? AppColors.errorText : AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (copyable) ...[
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: copyContent ?? content),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Text(
                      'Copy',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.accentText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                GestureDetector(
                  onTap: () =>
                      _openMaximizedViewer(title, copyContent ?? content),
                  child: Icon(
                    AppIcons.maximize,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          constraints: maxHeight != null
              ? BoxConstraints(maxHeight: maxHeight)
              : null,
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isError
                ? AppColors.errorSubtle.withValues(alpha: 0.5)
                : AppColors.codeBackground,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isError
                  ? AppColors.error.withValues(alpha: 0.3)
                  : AppColors.codeBorder,
              width: 1,
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SyntaxHighlightedCode(
              text: visibleContent,
              language: title.toLowerCase(),
            ),
          ),
        ),
      ],
    );
  }

  void _openMaximizedViewer(String title, String content) {
    Navigator.of(context).push(
      AppMotion.pageRoute(
        builder: (context) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(title, style: AppTypography.titleMedium),
            actions: [
              IconButton(
                icon: const Icon(AppIcons.copy, size: 18),
                tooltip: 'Copy all',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.codeBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.codeBorder),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(content, style: AppTypography.code),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
