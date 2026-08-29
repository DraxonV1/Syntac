import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/cancellation.dart';
import '../models.dart';

class CommandResult {
  const CommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
    this.failureKind,
    this.runtimeSignal,
    this.guestExitCode,
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
    this.stdoutOriginalLength,
    this.stderrOriginalLength,
    required this.timedOut,
    required this.cancelled,
  });

  factory CommandResult.fromMap(Map<Object?, Object?> map, Duration duration) =>
      CommandResult(
        stdout: map['stdout']?.toString() ?? '',
        stderr: map['stderr']?.toString() ?? '',
        exitCode: map['exitCode'] is int
            ? map['exitCode']! as int
            : int.tryParse(map['exitCode']?.toString() ?? '') ?? -1,
        duration: duration,
        timedOut: map['timedOut'] == true,
        failureKind: map['failureKind']?.toString(),
        runtimeSignal: map['runtimeSignal']?.toString(),
        guestExitCode: map['guestExitCode'] is int
            ? map['guestExitCode']! as int
            : int.tryParse(map['guestExitCode']?.toString() ?? ''),
        stdoutTruncated: map['stdoutTruncated'] == true,
        stderrTruncated: map['stderrTruncated'] == true,
        stdoutOriginalLength: map['stdoutOriginalLength'] is int
            ? map['stdoutOriginalLength']! as int
            : int.tryParse(map['stdoutOriginalLength']?.toString() ?? ''),
        stderrOriginalLength: map['stderrOriginalLength'] is int
            ? map['stderrOriginalLength']! as int
            : int.tryParse(map['stderrOriginalLength']?.toString() ?? ''),
        cancelled: map['cancelled'] == true,
      );

  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;
  final String? failureKind;
  final String? runtimeSignal;
  final int? guestExitCode;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final int? stdoutOriginalLength;
  final int? stderrOriginalLength;
  final bool timedOut;
  final bool cancelled;

  bool get success => exitCode == 0 && !timedOut && !cancelled;

  Map<String, Object?> toJson() => {
    'stdout': stdout,
    'stderr': stderr,
    'exitCode': exitCode,
    'durationMs': duration.inMilliseconds,
    if (failureKind != null) 'failureKind': failureKind,
    if (runtimeSignal != null) 'runtimeSignal': runtimeSignal,
    if (guestExitCode != null) 'guestExitCode': guestExitCode,
    if (stdoutTruncated) 'stdoutTruncated': true,
    if (stderrTruncated) 'stderrTruncated': true,
    if (stdoutOriginalLength != null)
      'stdoutOriginalLength': stdoutOriginalLength,
    if (stderrOriginalLength != null)
      'stderrOriginalLength': stderrOriginalLength,
    'timedOut': timedOut,
    'cancelled': cancelled,
  };
}

class CommandOutputUpdate {
  const CommandOutputUpdate({
    required this.stream,
    this.text = '',
    this.stdout,
    this.stderr,
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
    this.stdoutOriginalLength,
    this.stderrOriginalLength,
  });

  final String stream;
  final String text;
  final String? stdout;
  final String? stderr;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final int? stdoutOriginalLength;
  final int? stderrOriginalLength;
}

typedef CommandOutputCallback = FutureOr<void> Function(CommandOutputUpdate);

class _OutputAccumulator {
  _OutputAccumulator(this.maxCharacters);

  final int maxCharacters;
  final buffer = StringBuffer();
  var originalLength = 0;
  var truncated = false;

  void add(String chunk) {
    originalLength += chunk.length;
    if (buffer.length >= maxCharacters) {
      truncated = true;
      return;
    }
    final remaining = maxCharacters - buffer.length;
    if (chunk.length <= remaining) {
      buffer.write(chunk);
      return;
    }
    buffer.write(chunk.substring(0, remaining));
    truncated = true;
  }

  String get text {
    final value = buffer.toString();
    if (!truncated) return value;
    return truncatePersistedText(value, maxLength: maxCharacters);
  }
}

Map<Object?, Object?> _cancelledCommandResult() => <Object?, Object?>{
  'stdout': '',
  'stderr': 'Command cancelled by user.',
  'exitCode': -1,
  'failureKind': 'cancelled',
  'timedOut': false,
  'cancelled': true,
};

String redactRuntimeDiagnostics(String value) => value
    .replaceAll(RegExp(r'[A-Za-z]:[\\/][^\s,]+'), '<path>')
    .replaceAll(RegExp(r'/storage/emulated/\d+/[^\s,]+'), '<path>')
    .replaceAll(RegExp(r'/data/data/[^\s,]+'), '<path>');

class _CommandOutputQueue {
  _CommandOutputQueue(this._callback);

  final CommandOutputCallback _callback;
  Future<void> _tail = Future<void>.value();
  Object? _error;
  StackTrace? _stackTrace;

  void add(CommandOutputUpdate update) {
    _tail = _tail.then((_) async {
      if (_error != null) return;
      try {
        await _callback(update);
      } catch (error, stackTrace) {
        _error = error;
        _stackTrace = stackTrace;
      }
    });
  }

  Future<void> close() async {
    await _tail;
    final error = _error;
    if (error != null) {
      Error.throwWithStackTrace(error, _stackTrace ?? StackTrace.current);
    }
  }
}

class _NativeCommandOutput {
  const _NativeCommandOutput(this.commandId, this.update);

  final String commandId;
  final CommandOutputUpdate update;
}

class _NativeCommandOutputBus {
  static final _controller = StreamController<_NativeCommandOutput>.broadcast();
  static var _attached = false;

  static Stream<_NativeCommandOutput> get stream => _controller.stream;

  static void attach(MethodChannel channel) {
    if (_attached) return;
    _attached = true;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'commandOutput') return null;
      final raw = call.arguments;
      if (raw is! Map) return null;
      final id = raw['id']?.toString();
      final stream = raw['stream']?.toString() ?? 'status';
      if (id == null || id.isEmpty) return null;
      _controller.add(
        _NativeCommandOutput(
          id,
          CommandOutputUpdate(
            stream: stream,
            text: raw['text']?.toString() ?? '',
            stdout:
                raw['stdout']?.toString() ?? raw['stdoutPreview']?.toString(),
            stderr:
                raw['stderr']?.toString() ?? raw['stderrPreview']?.toString(),
            stdoutTruncated: raw['stdoutTruncated'] == true,
            stderrTruncated: raw['stderrTruncated'] == true,
            stdoutOriginalLength: raw['stdoutOriginalLength'] is int
                ? raw['stdoutOriginalLength']! as int
                : int.tryParse(raw['stdoutOriginalLength']?.toString() ?? ''),
            stderrOriginalLength: raw['stderrOriginalLength'] is int
                ? raw['stderrOriginalLength']! as int
                : int.tryParse(raw['stderrOriginalLength']?.toString() ?? ''),
          ),
        ),
      );
      return null;
    });
  }
}

abstract class ShellExecutor {
  String get runtimeId;
  Future<RuntimeStatus> status();
  Future<CommandResult> run({
    required String command,
    required String workingDirectory,
    required Duration timeout,
    CancellationToken? cancellationToken,
    CommandOutputCallback? onOutput,
  });
  Future<void> cancel(String commandId);
}

abstract class ShellRuntime implements ShellExecutor {
  String get label;
  Future<RuntimeStatus> install();
  Future<RuntimeStatus> remove();
  Future<String> diagnostics({String? projectRoot});
}

class PlatformShellExecutor implements ShellExecutor {
  PlatformShellExecutor({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('syntac/runtime') {
    _NativeCommandOutputBus.attach(_channel);
  }

  final MethodChannel _channel;
  @override
  String get runtimeId => ShellRuntimeId.termux.name;

  @override
  Future<RuntimeStatus> status() async {
    if (!Platform.isAndroid) {
      return const RuntimeStatus(
        state: RuntimeState.unavailable,
        message: 'Local shell execution is unavailable on this platform.',
        details:
            'This platform cannot invoke Termux. File tools still work for accessible project paths.',
      );
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>('runtimeStatus') ??
        <Object?, Object?>{};
    return RuntimeStatus.fromMap(raw);
  }

  @override
  Future<CommandResult> run({
    required String command,
    required String workingDirectory,
    required Duration timeout,
    CancellationToken? cancellationToken,
    CommandOutputCallback? onOutput,
  }) async {
    if (!Platform.isAndroid) {
      return CommandResult(
        stdout: '',
        stderr: 'Shell execution is unavailable on this platform.',
        exitCode: 127,
        duration: Duration.zero,
        timedOut: false,
        cancelled: false,
      );
    }
    final commandId = newId();
    final started = DateTime.now();
    final outputQueue = onOutput == null ? null : _CommandOutputQueue(onOutput);
    final outputSub = outputQueue == null
        ? null
        : _NativeCommandOutputBus.stream
              .where((event) => event.commandId == commandId)
              .listen((event) => outputQueue.add(event.update));
    final future = _channel.invokeMapMethod<Object?, Object?>('runCommand', {
      'id': commandId,
      'command': command,
      'workingDirectory': workingDirectory,
      'timeoutSeconds': timeout.inSeconds,
    });
    final timed = future.timeout(
      timeout,
      onTimeout: () async {
        await cancel(commandId);
        return <Object?, Object?>{
          'stdout': '',
          'stderr':
              'Termux result callback did not arrive after ${timeout.inSeconds}s. Check Termux allow-external-apps, RUN_COMMAND permission, and callback configuration.',
          'exitCode': -1,
          'failureKind': 'CallbackFailed',
          'timedOut': false,
          'cancelled': false,
        };
      },
    );
    final cancelResult = cancellationToken?.whenCancelled.then((_) async {
      await cancel(commandId);
      return _cancelledCommandResult();
    });
    try {
      final raw = await (cancelResult == null
          ? timed
          : Future.any<Map<Object?, Object?>?>([timed, cancelResult]));
      return CommandResult.fromMap(
        raw ?? <Object?, Object?>{},
        DateTime.now().difference(started),
      );
    } on PlatformException catch (error) {
      return CommandResult(
        stdout: '',
        stderr: error.message ?? error.code,
        exitCode: -1,
        failureKind: 'LaunchFailed',
        duration: DateTime.now().difference(started),
        timedOut: false,
        cancelled: cancellationToken?.isCancelled ?? false,
      );
    } finally {
      await outputSub?.cancel();
      await outputQueue?.close();
    }
  }

  @override
  Future<void> cancel(String commandId) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('cancelCommand', {'id': commandId});
  }
}

class TermuxRuntime extends PlatformShellExecutor implements ShellRuntime {
  TermuxRuntime({super.channel});

  @override
  String get label => ShellRuntimeId.termux.label;

  @override
  Future<String> diagnostics({String? projectRoot}) async {
    final current = await status();
    return [
      'runtime: ${ShellRuntimeId.termux.name}',
      'label: $label',
      'state: ${current.state.name}',
      'message: ${redactRuntimeDiagnostics(current.message)}',
      if (current.details != null)
        'details: ${redactRuntimeDiagnostics(current.details!)}',
      if (projectRoot != null) 'projectRoot: <path>',
    ].join('\n');
  }

  @override
  Future<RuntimeStatus> install() async => const RuntimeStatus(
    state: RuntimeState.configurationRequired,
    message: 'Install and configure Termux outside Syntac.',
    details:
        'Install Termux from F-Droid or GitHub, enable allow-external-apps=true, and grant RUN_COMMAND permission.',
  );

  @override
  Future<RuntimeStatus> remove() async => const RuntimeStatus(
    state: RuntimeState.configurationRequired,
    message: 'Termux is managed outside Syntac.',
  );
}

class ArchLinuxRuntime implements ShellRuntime {
  ArchLinuxRuntime({
    Project? activeProject,
    List<Project> availableProjects = const [],
    MethodChannel? channel,
  }) : _activeProject = activeProject,
       _availableProjects = availableProjects,
       _channel = channel ?? const MethodChannel('syntac/runtime');

  final Project? _activeProject;
  final List<Project> _availableProjects;
  final MethodChannel _channel;

  @override
  String get runtimeId => ShellRuntimeId.archLinux.name;

  @override
  String get label => ShellRuntimeId.archLinux.label;

  @override
  Future<RuntimeStatus> status() async {
    if (!Platform.isAndroid) {
      return const RuntimeStatus(
        state: RuntimeState.unavailable,
        message: 'ARCH Linux Runtime is Android-only.',
      );
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'localRuntimeStatus',
        ) ??
        <Object?, Object?>{};
    return RuntimeStatus.fromMap(raw);
  }

  @override
  Future<CommandResult> run({
    required String command,
    required String workingDirectory,
    required Duration timeout,
    CancellationToken? cancellationToken,
    CommandOutputCallback? onOutput,
  }) async {
    if (!Platform.isAndroid) {
      return CommandResult(
        stdout: '',
        stderr: 'ARCH Linux Runtime is Android-only.',
        exitCode: 127,
        duration: Duration.zero,
        failureKind: 'UnsupportedRuntime',
        timedOut: false,
        cancelled: false,
      );
    }
    final commandId = newId();
    final started = DateTime.now();
    _NativeCommandOutputBus.attach(_channel);
    final outputQueue = onOutput == null ? null : _CommandOutputQueue(onOutput);
    final outputSub = outputQueue == null
        ? null
        : _NativeCommandOutputBus.stream
              .where((event) => event.commandId == commandId)
              .listen((event) => outputQueue.add(event.update));
    final future = _channel
        .invokeMapMethod<Object?, Object?>('runLocalCommand', {
          'id': commandId,
          'command': command,
          'workingDirectory': workingDirectory,
          'timeoutSeconds': timeout.inSeconds,
          if (_activeProject != null)
            'activeProject': _projectPayload(_activeProject),
          'availableProjects': _availableProjects.map(_projectPayload).toList(),
        });
    try {
      final timed = future.timeout(
        timeout,
        onTimeout: () async {
          await cancel(commandId);
          return <Object?, Object?>{
            'stdout': '',
            'stderr':
                'ARCH Linux Runtime command exceeded ${timeout.inSeconds}s.',
            'exitCode': -1,
            'failureKind': 'command_timeout',
            'timedOut': true,
            'cancelled': false,
          };
        },
      );
      final cancelResult = cancellationToken?.whenCancelled.then((_) async {
        await cancel(commandId);
        return _cancelledCommandResult();
      });
      final raw = await (cancelResult == null
          ? timed
          : Future.any<Map<Object?, Object?>?>([timed, cancelResult]));
      return CommandResult.fromMap(
        raw ?? <Object?, Object?>{},
        DateTime.now().difference(started),
      );
    } finally {
      await outputSub?.cancel();
      await outputQueue?.close();
    }
  }

  @override
  Future<void> cancel(String commandId) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('cancelLocalCommand', {'id': commandId});
  }

  @override
  Future<RuntimeStatus> install() async {
    if (!Platform.isAndroid) {
      return const RuntimeStatus(
        state: RuntimeState.unavailable,
        message: 'ARCH Linux Runtime install is Android-only.',
      );
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'installLocalRuntime',
        ) ??
        <Object?, Object?>{};
    return RuntimeStatus.fromMap(raw);
  }

  Future<RuntimeStatus> retrySelfTest() async {
    if (!Platform.isAndroid) {
      return const RuntimeStatus(
        state: RuntimeState.unavailable,
        message: 'ARCH Linux Runtime test is Android-only.',
      );
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'retryLocalRuntimeTest',
        ) ??
        <Object?, Object?>{};
    return RuntimeStatus.fromMap(raw);
  }

  @override
  Future<RuntimeStatus> remove() async {
    if (!Platform.isAndroid) {
      return const RuntimeStatus(
        state: RuntimeState.unavailable,
        message: 'ARCH Linux Runtime removal is Android-only.',
      );
    }
    final raw =
        await _channel.invokeMapMethod<Object?, Object?>(
          'removeLocalRuntime',
        ) ??
        <Object?, Object?>{};
    return RuntimeStatus.fromMap(raw);
  }

  @override
  Future<String> diagnostics({String? projectRoot}) async {
    final current = await status();
    return [
      'runtime: ${ShellRuntimeId.archLinux.name}',
      'label: $label',
      'state: ${current.state.name}',
      'message: ${redactRuntimeDiagnostics(current.message)}',
      if (current.details != null)
        'details: ${redactRuntimeDiagnostics(current.details!)}',
      if (projectRoot != null) 'projectRoot: <path>',
      if (_activeProject != null)
        'activeProjectMount: ${_activeProject.mountName}',
      if (_availableProjects.isNotEmpty)
        'availableProjectMounts: ${_availableProjects.map((project) => project.mountName).join(', ')}',
    ].join('\n');
  }

  static Map<String, Object?> _projectPayload(Project project) => {
    'id': project.id,
    'name': project.name,
    'folderPath': project.folderPath,
    'mountName': project.mountName,
  };
}

class LocalProcessShellExecutor implements ShellExecutor {
  @override
  String get runtimeId => 'localProcess';
  @override
  Future<RuntimeStatus> status() async => const RuntimeStatus(
    state: RuntimeState.ready,
    message: 'Local process executor ready',
  );

  @override
  Future<CommandResult> run({
    required String command,
    required String workingDirectory,
    required Duration timeout,
    CancellationToken? cancellationToken,
    CommandOutputCallback? onOutput,
  }) async {
    final started = DateTime.now();
    final process = await Process.start(
      Platform.isWindows ? 'cmd.exe' : '/bin/sh',
      Platform.isWindows ? ['/c', command] : ['-lc', command],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    final stdout = _OutputAccumulator(maxPersistedTextCharacters);
    final stderr = _OutputAccumulator(maxPersistedTextCharacters);
    final outputQueue = onOutput == null ? null : _CommandOutputQueue(onOutput);
    final outDone = Completer<void>();
    final errDone = Completer<void>();
    final outSub = process.stdout.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      stdout.add(chunk);
      outputQueue?.add(
        CommandOutputUpdate(
          stream: 'stdout',
          text: chunk,
          stdout: stdout.text,
          stdoutTruncated: stdout.truncated,
          stdoutOriginalLength: stdout.originalLength,
        ),
      );
    }, onDone: outDone.complete);
    final errSub = process.stderr.transform(systemEncoding.decoder).listen((
      chunk,
    ) {
      stderr.add(chunk);
      outputQueue?.add(
        CommandOutputUpdate(
          stream: 'stderr',
          text: chunk,
          stderr: stderr.text,
          stderrTruncated: stderr.truncated,
          stderrOriginalLength: stderr.originalLength,
        ),
      );
    }, onDone: errDone.complete);
    late final StreamSubscription<void> cancelSub;
    if (cancellationToken != null) {
      cancelSub = cancellationToken.whenCancelled.asStream().listen(
        (_) => _killProcessTree(process),
      );
    }
    var timedOut = false;
    var cancelled = false;
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          _killProcessTree(process, force: true);
          return -1;
        },
      );
      cancelled = cancellationToken?.isCancelled ?? false;
    } finally {
      await Future.wait([
        outDone.future,
        errDone.future,
      ]).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
      await outSub.cancel();
      await errSub.cancel();
      await outputQueue?.close();
      if (cancellationToken != null) await cancelSub.cancel();
    }
    return CommandResult(
      stdout: stdout.text,
      stderr: stderr.text,
      exitCode: exitCode,
      duration: DateTime.now().difference(started),
      stdoutTruncated: stdout.truncated,
      stderrTruncated: stderr.truncated,
      stdoutOriginalLength: stdout.truncated ? stdout.originalLength : null,
      stderrOriginalLength: stderr.truncated ? stderr.originalLength : null,
      timedOut: timedOut,
      cancelled: cancelled,
    );
  }

  Future<void> _killProcessTree(Process process, {bool force = false}) async {
    if (Platform.isWindows) {
      await Process.run('taskkill', [
        '/PID',
        process.pid.toString(),
        '/T',
        if (force) '/F',
      ]);
      return;
    }
    process.kill(force ? ProcessSignal.sigkill : ProcessSignal.sigterm);
  }

  @override
  Future<void> cancel(String commandId) async {}
}
