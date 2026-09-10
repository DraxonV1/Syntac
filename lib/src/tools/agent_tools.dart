// Project tool registry; each tool implementation lives in its own source file.

import 'dart:io';
import '../core/cancellation.dart';
import 'bash_tool.dart';
import 'copy_tool.dart';
import 'delete_tool.dart';
import 'edit_tool.dart';
import 'list_tool.dart';
import 'read_tool.dart';
import 'search_tool.dart';
import 'tool_context.dart';
import 'write_tool.dart';

export 'tool_context.dart' show ToolFailure, ToolUpdateCallback;

class ProjectTools extends ToolContext
    with
        ReadTool,
        WriteTool,
        EditTool,
        DeleteTool,
        ListTool,
        SearchTool,
        BashTool,
        CopyTool {
  ProjectTools({
    required super.projectRoot,
    required super.shellExecutor,
    super.commandApproval,
    super.attachments,
    super.maxReadBytes,
    super.maxSearchResults,
    super.maxCommandOutputCharacters,
  });

  List<Map<String, Object?>> get specs => [
    _spec(
      'read',
      'Read text, or inspect an attached image. Attachments use local://attachment-N. Use includeImage for bounded vision data.',
      {
        'path': _string('Relative file path or local://attachment-N'),
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
      'copy',
      'Copy an attached file or project file to a project path or Android shared-storage path. Use local://attachment-N for attachments.',
      {
        'source': _string('Relative file path or local://attachment-N'),
        'target': _string(
          'Destination path inside project or Android shared storage',
        ),
      },
      ['source', 'target'],
    ),
    _spec(
      'edit',
      'Replace one unambiguous text target inside a file.',
      {
        'path': _string('Relative file path'),
        'target': _string('Existing text'),
        'replacement': _string('Replacement text'),
        'requireUnique': {'type': 'boolean'},
        'replaceAll': {'type': 'boolean'},
        'expectedReplacements': {'type': 'integer'},
      },
      ['path', 'target', 'replacement'],
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
        'read' => await readFile(
          args['path'] as String? ?? '',
          offset: args['offset'] as int?,
          limit: args['limit'] as int?,
          startLine: args['startLine'] as int?,
          endLine: args['endLine'] as int?,
          unit: args['unit'] as String?,
          raw: args['raw'] == true,
          includeImage: args['includeImage'] == true,
        ),
        'display_image' => await displayImage(args['path'] as String? ?? ''),
        'write' => await writeFile(
          args['path'] as String? ?? '',
          args['content'] as String? ?? '',
        ),
        'edit' => await editFile(
          args['path'] as String? ?? '',
          args['target'] as String? ?? '',
          args['replacement'] as String? ?? '',
          requireUnique: args['requireUnique'] as bool? ?? true,
          replaceAll: args['replaceAll'] == true,
          expectedReplacements: args['expectedReplacements'] as int?,
        ),
        'delete' => await deletePath(
          args['path'] as String? ?? '',
          recursive: args['recursive'] as bool? ?? false,
        ),
        'list' => await listDirectory(
          args['path'] as String? ?? '.',
          depth: args['depth'] as int? ?? 1,
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
