// Project tool registry; each tool implementation lives in its own source file.

import 'dart:io';
import '../core/cancellation.dart';
import 'apply_patch_tool.dart';
import 'bash_tool.dart';
import 'copy_tool.dart';
import 'delete_tool.dart';
import 'glob_tool.dart';
import 'list_tool.dart';
import 'read_tool.dart';
import 'runtime_jobs_tool.dart';
import 'search_tool.dart';
import 'tool_context.dart';
import 'write_tool.dart';

export 'tool_context.dart' show ToolFailure, ToolUpdateCallback;

class ProjectTools extends ToolContext
    with
        ReadTool,
        WriteTool,
        ApplyPatchTool,
        DeleteTool,
        ListTool,
        GlobTool,
        SearchTool,
        BashTool,
        RuntimeJobsTool,
        CopyTool {
  ProjectTools({
    required super.projectRoot,
    required super.shellExecutor,
    super.commandApproval,
    super.attachments,
    super.maxReadBytes,
    super.maxSearchResults,
    super.maxCommandOutputCharacters,
    this.todoHandler,
  });

  final Future<Map<String, Object?>> Function(Map<String, Object?>)?
  todoHandler;

  List<Map<String, Object?>> get specs => [
    _spec(
      'read',
      'Read text, or inspect an attached image. Attachments use local://attachment-N. Use includeImage for bounded vision data.',
      {
        'path': _string(
          'Relative file path or local://attachment-N; absolute only with systemwide: true',
        ),
        'offset': {
          'type': 'integer',
          'description':
              'Line offset for line reads, byte offset for byte reads',
        },
        'limit': {
          'type': 'integer',
          'description': 'Maximum lines or bytes to return',
        },
        'startLine': {'type': 'integer'},
        'endLine': {'type': 'integer'},
        'unit': {
          'type': 'string',
          'enum': ['line', 'byte'],
        },
        'raw': {'type': 'boolean'},
        'includeImage': {
          'type': 'boolean',
          'description':
              'Include bounded base64 data for vision-capable providers',
        },
        'systemwide': {
          'type': 'boolean',
          'description':
              'Read an absolute system path instead of a project-relative path; read-only and sensitive paths are blocked.',
        },
      },
      ['path'],
    ),
    _spec(
      'display_image',
      'Inspect an image and return metadata for the chat image viewer.',
      {'path': _string('Relative image path or local://attachment-N')},
      ['path'],
    ),
    _spec(
      'write',
      'Create or overwrite a file inside the project.',
      {
        'path': _string('Relative file path'),
        'content': _string('File content'),
      },
      ['path', 'content'],
    ),
    _spec(
      'apply_patch',
      'Apply bounded multi-file patch. Read every updated/deleted file first, then pass exact path-to-snapshot map. Stale snapshots reject whole patch before writes.',
      {
        'patch': _string('Patch using *** Begin Patch / *** End Patch syntax'),
        'expectedSnapshots': {
          'type': 'object',
          'additionalProperties': {'type': 'string'},
          'description':
              'Map updated/deleted paths to snapshots returned by read',
        },
      },
      ['patch', 'expectedSnapshots'],
    ),
    _spec(
      'delete',
      'Delete a file inside the project. Recursive directory deletion is disabled unless explicitly requested.',
      {
        'path': _string('Relative path'),
        'recursive': {'type': 'boolean'},
      },
      ['path'],
    ),
    _spec(
      'list',
      'List directory contents inside the project.',
      {
        'path': _string('Relative directory path'),
        'depth': {'type': 'integer'},
      },
      ['path'],
    ),
    _spec(
      'glob',
      'Match project files and directories with a bounded glob pattern.',
      {
        'pattern': _string('Relative glob pattern such as lib/**/*.dart'),
        'maxResults': {'type': 'integer'},
        'offset': {'type': 'integer'},
        'includeDirectories': {'type': 'boolean'},
        'includeFiles': {'type': 'boolean'},
        'caseSensitive': {'type': 'boolean'},
      },
      ['pattern'],
    ),
    _spec(
      'search',
      'Search filenames and text content with bounded, pageable results.',
      {
        'query': _string('Search query'),
        'path': _string('Optional relative directory path'),
        'maxResults': {'type': 'integer'},
        'offset': {
          'type': 'integer',
          'description': 'Number of matches to skip for pagination',
        },
        'regex': {'type': 'boolean'},
        'caseSensitive': {'type': 'boolean'},
        'include': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'exclude': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'contextLines': {'type': 'integer'},
      },
      ['query'],
    ),
    _spec(
      'bash',
      'Run shell command. UI shows first 50 lines; full output is saved to local:// artifact when truncated.',
      {
        'command': _string('Command'),
        'timeout_seconds': {
          'type': 'integer',
          'description':
              'Optional timeout in seconds, 0 disables deadline, 1-1800 otherwise',
        },
        'background': {
          'type': 'boolean',
          'description':
              'Start durable ARCH Linux Runtime job and return jobId.',
        },
      },
      ['command'],
    ),
    _spec(
      'jobs.list',
      'List durable runtime jobs with lifecycle metadata.',
      const <String, Object?>{},
      const <String>[],
    ),
    _spec(
      'jobs.status',
      'Read one durable runtime job status, timestamps, exit code, and failure.',
      {'jobId': _string('Durable runtime job id')},
      ['jobId'],
    ),
    _spec(
      'jobs.logs',
      'Read durable runtime job logs. Follow running jobs by default and stream updates to the user.',
      {
        'jobId': _string('Durable runtime job id'),
        'maxCharacters': {'type': 'integer'},
        'follow': {'type': 'boolean'},
        'timeout_seconds': {
          'type': 'integer',
          'description':
              'Follow timeout in seconds; 0 waits without a deadline',
        },
      },
      ['jobId'],
    ),
    _spec(
      'jobs.wait',
      'Wait until durable runtime job exits or timeout expires.',
      {
        'jobId': _string('Durable runtime job id'),
        'timeout_seconds': {
          'type': 'integer',
          'description': 'Wait timeout in seconds; 0 waits without a deadline',
        },
      },
      ['jobId'],
    ),
    _spec(
      'jobs.cancel',
      'Cancel one durable runtime job and its process tree.',
      {'jobId': _string('Durable runtime job id')},
      ['jobId'],
    ),
    if (todoHandler != null)
      _spec(
        'todo',
        'Manage persistent tasks for this chat. Use exact task text; one active task. Blocked tasks require unblock. Limits: 8 phases, 40 tasks, 120 characters per label.',
        {
          'op': {
            'type': 'string',
            'enum': [
              'init',
              'start',
              'done',
              'rm',
              'drop',
              'block',
              'unblock',
              'append',
              'view',
            ],
          },
          'task': _string('Exact task text'),
          'phase': _string('Exact phase name'),
          'reason': _string('Why task is blocked'),
          'items': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'list': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'phase': {'type': 'string'},
                'items': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
              'required': ['phase', 'items'],
            },
          },
        },
        ['op'],
      ),
  ];

  static Map<String, Object?> _string(String description) => {
    'type': 'string',
    'description': description,
  };

  static Map<String, Object?> _spec(
    String name,
    String description,
    Map<String, Object?> properties,
    List<String> required,
  ) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
      },
    },
  };
  static int _timeoutSeconds(Object? raw, Duration? fallback) {
    final parsed = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    return (parsed ?? fallback?.inSeconds ?? 120).clamp(0, 1800).toInt();
  }

  Future<Map<String, Object?>> execute(
    String name,
    Map<String, Object?> args, {
    CancellationToken? cancellationToken,
    Duration? commandTimeout,
    ToolUpdateCallback? onUpdate,
  }) async {
    try {
      cancellationToken?.throwIfCancelled();
      final result = switch (name) {
        'todo' when todoHandler != null => await todoHandler!(args),
        'read' => await readFile(
          args['path'] as String? ?? '',
          offset: args['offset'] as int?,
          limit: args['limit'] as int?,
          startLine: args['startLine'] as int?,
          endLine: args['endLine'] as int?,
          unit: args['unit'] as String?,
          raw: args['raw'] == true,
          includeImage: args['includeImage'] == true,
          systemwide:
              args['systemwide'] == true ||
              args['scope']?.toString() == 'system',
        ),
        'display_image' => await displayImage(args['path'] as String? ?? ''),
        'write' => await writeFile(
          args['path'] as String? ?? '',
          args['content'] as String? ?? '',
        ),
        'apply_patch' => await applyPatch(
          args['patch'] as String? ?? '',
          expectedSnapshots: args['expectedSnapshots'] is Map
              ? (args['expectedSnapshots'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value),
                )
              : const {},
        ),
        'delete' => await deletePath(
          args['path'] as String? ?? '',
          recursive: args['recursive'] as bool? ?? false,
        ),
        'list' => await listDirectory(
          args['path'] as String? ?? '.',
          depth: args['depth'] as int? ?? 1,
        ),
        'glob' => await globPaths(
          args['pattern'] as String? ?? '',
          maxResults: args['maxResults'] as int? ?? 200,
          offset: args['offset'] as int? ?? 0,
          includeDirectories: args['includeDirectories'] as bool? ?? true,
          includeFiles: args['includeFiles'] as bool? ?? true,
          caseSensitive: args['caseSensitive'] as bool?,
        ),
        'search' => await search(
          args['query'] as String? ?? '',
          path: args['path'] as String?,
          maxResults: args['maxResults'] as int?,
          offset: args['offset'] as int?,
          regex: args['regex'] == true,
          caseSensitive: args['caseSensitive'] as bool?,
          include: stringList(args['include']),
          exclude: stringList(args['exclude']),
          contextLines: args['contextLines'] as int?,
        ),
        'bash' => await runBash(
          args['command'] as String? ?? '',
          timeout: Duration(
            seconds: _timeoutSeconds(
              args['timeout_seconds'] ?? args['timeoutSeconds'],
              commandTimeout,
            ),
          ),
          background: args['background'] == true || args['async'] == true,
          cancellationToken: cancellationToken,
          onUpdate: onUpdate,
        ),
        'copy' => await copyFile(
          source: args['source'] as String? ?? '',
          target: args['target'] as String? ?? '',
        ),
        'jobs.list' || 'jobs_list' => await listRuntimeJobs(),
        'jobs.status' ||
        'jobs_status' => await runtimeJobStatus(args['jobId'] as String? ?? ''),
        'jobs.logs' || 'jobs_logs' => await runtimeJobLogs(
          args['jobId'] as String? ?? '',
          maxCharacters: args['maxCharacters'] as int? ?? 200000,
          follow: args['follow'] as bool? ?? true,
          timeout: Duration(
            seconds: _timeoutSeconds(
              args['timeout_seconds'] ?? args['timeoutSeconds'],
              const Duration(seconds: 30),
            ),
          ),
          cancellationToken: cancellationToken,
          onUpdate: onUpdate,
        ),
        'jobs.wait' || 'jobs_wait' => await waitForRuntimeJob(
          args['jobId'] as String? ?? '',
          timeout: Duration(
            seconds: _timeoutSeconds(
              args['timeout_seconds'] ?? args['timeoutSeconds'],
              const Duration(seconds: 120),
            ),
          ),
          cancellationToken: cancellationToken,
        ),
        'jobs.cancel' ||
        'jobs_cancel' => await cancelRuntimeJob(args['jobId'] as String? ?? ''),
        _ => throw ToolFailure('Unknown tool: $name'),
      };
      return {'ok': true, 'result': result};
    } on OperationCancelledException {
      return {
        'ok': false,
        'category': 'cancelled',
        'cancelled': true,
        'error': 'Tool execution cancelled',
      };
    } on ToolFailure catch (error) {
      return {
        'ok': false,
        'category': 'validation_error',
        'error': error.message,
      };
    } on FormatException catch (error) {
      return {
        'ok': false,
        'category': 'validation_error',
        'error': error.message,
      };
    } on FileSystemException catch (error) {
      return {
        'ok': false,
        'category': 'filesystem_error',
        'error': error.message,
        'osError': error.osError?.message,
        'path': error.path,
      };
    } catch (error) {
      return {'ok': false, 'category': 'tool_error', 'error': error.toString()};
    }
  }
}
