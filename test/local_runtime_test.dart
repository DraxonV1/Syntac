import 'dart:convert';
import 'dart:io';

import 'package:syntac/src/core/cancellation.dart';
import 'package:syntac/src/models.dart';
import 'package:syntac/src/runtime/shell_executor.dart';
import 'package:syntac/src/tools/agent_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local runtime installer states parse from platform channel maps', () {
    for (final state in [
      RuntimeState.notInstalled,
      RuntimeState.downloading,
      RuntimeState.verifying,
      RuntimeState.extracting,
      RuntimeState.initializing,
      RuntimeState.testing,
      RuntimeState.ready,
      RuntimeState.error,
    ]) {
      final status = RuntimeStatus.fromMap({
        'state': state.name,
        'message': 'state ${state.name}',
        'details': 'details ${state.name}',
      });
      expect(status.state, state);
      expect(status.message, contains(state.name));
      expect(status.details, contains(state.name));
    }
  });

  test('local runtime selection persists by enum name', () {
    final settings = ShellRuntimeSettings.fromMap({
      'selected': ShellRuntimeId.archLinux.name,
    });
    expect(settings.selected, ShellRuntimeId.archLinux);
    expect(settings.toMap(), {'selected': 'archLinux'});
  });

  test(
    'local runtime diagnostics redact paths and include stable project mount names',
    () async {
      final projectA = Project.create(
        name: 'Test 2',
        folderPath: '/storage/emulated/0/Test 2/project 1',
        mountName: 'project-1',
      );
      final projectB = Project.create(
        name: 'Other Project',
        folderPath: '/storage/emulated/0/Test 2/project 2',
        mountName: 'project-2',
      );
      final diagnostics = await ArchLinuxRuntime(
        activeProject: projectA,
        availableProjects: [projectA, projectB],
      ).diagnostics(projectRoot: projectA.folderPath);

      expect(diagnostics, contains('projectRoot: <path>'));
      expect(diagnostics, contains('activeProjectMount: project-1'));
      expect(
        diagnostics,
        contains('availableProjectMounts: project-1, project-2'),
      );
      expect(diagnostics, isNot(contains(projectA.folderPath)));
      expect(diagnostics, isNot(contains(projectB.folderPath)));
    },
  );

  test('bash normalizes local runtime missing errors', () async {
    final tools = ProjectTools(
      projectRoot: '.',
      shellExecutor: _StaticShellExecutor(
        const CommandResult(
          stdout: '',
          stderr: 'ARCH Linux Runtime is not installed.',
          exitCode: -1,
          duration: Duration(milliseconds: 12),
          failureKind: 'local_runtime_not_installed',
          timedOut: false,
          cancelled: false,
        ),
      ),
    );

    final result = await tools.runBash(
      'echo hello',
      timeout: const Duration(seconds: 5),
    );

    expect(result['runtime'], ShellRuntimeId.archLinux.name);
    expect(result['success'], isFalse);
    expect(result['category'], 'runtime_failure');
    expect(result['failureKind'], 'local_runtime_not_installed');
    expect(result['stderr'], contains('not installed'));
  });

  test('bash classifies PRoot signal crashes as runtime failures', () async {
    final tools = ProjectTools(
      projectRoot: '.',
      shellExecutor: _StaticShellExecutor(
        const CommandResult(
          stdout: '',
          stderr: 'Fatal glibc error',
          exitCode: 139,
          duration: Duration(milliseconds: 12),
          failureKind: 'runtime_signal',
          runtimeSignal: 'SIGSEGV',
          guestExitCode: 139,
          timedOut: false,
          cancelled: false,
        ),
      ),
    );

    final result = await tools.runBash(
      'python3 -c "print(1)"',
      timeout: const Duration(seconds: 5),
    );

    expect(result['category'], 'runtime_failure');
    expect(result['failureKind'], 'runtime_signal');
    expect(result['runtimeSignal'], 'SIGSEGV');
    expect(result['guestExitCode'], 139);
  });

  test(
    'local runtime diagnostics expose only current Termux PRoot runtime',
    () {
      const details = '''
Runtime implementation: Open-source Termux PRoot
PROOT
Version: termux-proot-ab2e3464
Source: https://github.com/termux/proot
Commit: ab2e3464d04483b98a0614b470f3f8950d5a6468
License: Open-source Termux PRoot; PRoot is GPLv2.
Packaged components:
libsyntac_proot.so: found=true
ROOTFS
ARCH Linux Runtime version: arch-linux-runtime-v1
Distro: Arch Linux
Version: proot-distro-v4.29.0
Bundle format version: 2
Bundle compressed size: 126882630
Bundle checksum: e9ba4ff277e432e503cec5e49c412502d398be125ee27bb441e0a2322f034d04
Manifest entry count: 30918
Directories: 1209
Regular files: 21686
Symlinks: 8023
Hard links: 0
Files materialized: 21677
Symlinks created: 8023
Bundle install success: true
Final required tools exist: true
Final CA certificates exist: true
Final rootfs validation: pass
PROOT_TMP_DIR: /data/user/0/com.syntac/files/runtime/tmp
PROOT_TMP_DIR writable: true
Self-test attempted: true
EXECUTION
Capability: RuntimeReady
Rootfs installed: true
''';

      final status = RuntimeStatus.fromMap({
        'state': RuntimeState.ready.name,
        'message': 'ready',
        'details': details,
      });

      expect(status.state, RuntimeState.ready);
      expect(
        status.details,
        contains('Runtime implementation: Open-source Termux PRoot'),
      );
      expect(status.details, contains('Final CA certificates exist: true'));
      expect(status.details, contains('Manifest entry count: 30918'));
      expect(status.details, contains('libsyntac_proot.so: found=true'));
    },
  );

  test(
    'Arch Linux fixture matches pinned proot-distro v4.29.0 aarch64 layout',
    () async {
      final fixture =
          jsonDecode(
                await File(
                  'test/fixtures/archlinux_aarch64_pd_v4_29_0_structure.json',
                ).readAsString(),
              )
              as Map<String, Object?>;
      final critical = fixture['critical']! as Map<String, Object?>;

      expect(fixture['sha256'], hasLength(64));
      expect(
        fixture['sha256'],
        '08d74365213e647c558e561b0a2a7afb6fa3dfe345a1994c62ccac5af1a1cdc6',
      );
      expect(fixture['size'], 151744988);
      expect(critical['bin'], {
        'type': 'symlink',
        'target': 'usr/bin',
        'mode': '0777',
        'size': 0,
      });
      expect(critical['usr/bin/sh'], {
        'type': 'symlink',
        'target': 'bash',
        'mode': '0777',
        'size': 0,
      });
      expect(critical['usr/bin/bash'], {
        'type': 'file',
        'target': null,
        'mode': '0755',
        'size': 1194232,
      });
      expect(critical['usr/bin/pacman'], {
        'type': 'file',
        'target': null,
        'mode': '0755',
        'size': 198696,
      });
      expect(critical['usr/bin/curl'], {
        'type': 'file',
        'target': null,
        'mode': '0755',
        'size': 264472,
      });
      expect(critical['usr/bin/awk'], {
        'type': 'symlink',
        'target': 'gawk',
        'mode': '0777',
        'size': 0,
      });
      expect(critical['etc/os-release'], {
        'type': 'symlink',
        'target': '../usr/lib/os-release',
        'mode': '0777',
        'size': 0,
      });
      expect(critical['usr/lib/ld-linux-aarch64.so.1'], {
        'type': 'file',
        'target': null,
        'mode': '0755',
        'size': 202408,
      });
      expect(critical['usr/lib/libc.so.6'], {
        'type': 'file',
        'target': null,
        'mode': '0755',
        'size': 1722720,
      });
      expect(critical['etc/ssl/certs/ca-certificates.crt'], {
        'type': 'symlink',
        'target': '../../ca-certificates/extracted/tls-ca-bundle.pem',
        'mode': '0777',
        'size': 0,
      });
      final bundle = fixture['bundle']! as Map<String, Object?>;
      expect(bundle['formatVersion'], 2);
      expect(bundle['size'], 126882630);
      expect(
        bundle['sha256'],
        'e9ba4ff277e432e503cec5e49c412502d398be125ee27bb441e0a2322f034d04',
      );
      final counts = fixture['counts']! as Map<String, Object?>;
      expect(counts['total'], 30918);
      expect(counts['dirs'], 1209);
      expect(counts['files'], 21686);
      expect(counts['symlinks'], 8023);
      expect(counts['hardlinks'], 0);
      expect(counts['other'], 0);
      expect(counts['packages'], 107);
      expect(fixture['glibc'], contains('GNU libc'));
      expect(fixture['glibc'], contains('2.41'));
      expect(critical['etc/ca-certificates/extracted/cadir'], {
        'type': 'directory',
        'target': null,
        'mode': '0555',
        'size': 0,
      });
      expect(critical['etc/ca-certificates/extracted/cadir/ACCVRAIZ1.pem'], {
        'type': 'file',
        'target': null,
        'mode': '0444',
        'size': 2772,
      });

      expect(fixture['overlayPackages'], ['libgcc', 'libstdc++']);
      expect(critical['var/lib/pacman/local/ALPM_DB_VERSION'], {
        'type': 'file',
        'target': null,
        'mode': '0644',
        'size': 2,
      });
      expect(critical['etc/pacman.d/gnupg'], {
        'type': 'directory',
        'target': null,
        'mode': '0755',
        'size': 0,
      });
      expect(critical['usr/lib/libstdc++.so.6.0.35'], {
        'type': 'file',
        'target': null,
        'mode': '0755',
        'size': 3017768,
      });

      expect(fixture['first100'], contains('bin'));
    },
  );

  test('rootfs resolver handles absolute and component symlinks', () {
    final fs = <String, String?>{
      '/rootfs/bin': 'usr/bin',
      '/rootfs/usr/bin/sh': 'bash',
      '/rootfs/usr/bin/bash': null,
    };

    expect(_validRootfsPath('/rootfs', '/bin/sh', fs), isTrue);
    expect(_validRootfsPath('/rootfs', '/bin/bash', fs), isTrue);
    expect(fs, isNot(contains('/bin/bash')));
  });
}

class _StaticShellExecutor implements ShellExecutor {
  const _StaticShellExecutor(this.result);

  final CommandResult result;

  @override
  String get runtimeId => ShellRuntimeId.archLinux.name;

  @override
  Future<void> cancel(String commandId) async {}

  @override
  Future<CommandResult> run({
    required String command,
    required String workingDirectory,
    required Duration timeout,
    CancellationToken? cancellationToken,
    CommandOutputCallback? onOutput,
  }) async => result;

  @override
  Future<RuntimeStatus> status() async => const RuntimeStatus(
    state: RuntimeState.notInstalled,
    message: 'not installed',
  );
}

bool _validRootfsPath(String rootfs, String path, Map<String, String?> fs) {
  final pending = path
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  return _resolveRootfsPath(rootfs, rootfs, pending, fs, <String>{}) != null;
}

String? _resolveRootfsPath(
  String rootfs,
  String current,
  List<String> pending,
  Map<String, String?> fs,
  Set<String> seen,
) {
  for (var i = 0; i < 80; i++) {
    if (!_withinRoot(rootfs, current)) return null;
    if (pending.isEmpty) {
      if (!fs.containsKey(current)) return null;
      final target = fs[current];
      if (target == null) return current;
      if (!seen.add(current)) return null;
      current = _normalizeRootfsPath(rootfs, target, parent: _parent(current));
      continue;
    }
    final next = _normalizeRootfsPath(
      rootfs,
      pending.removeAt(0),
      parent: current,
    );
    if (!fs.containsKey(next)) return null;
    final target = fs[next];
    if (target == null) {
      current = next;
      continue;
    }
    if (!seen.add(next)) return null;
    current = _normalizeRootfsPath(rootfs, target, parent: _parent(next));
  }
  return null;
}

String _normalizeRootfsPath(
  String rootfs,
  String path, {
  required String parent,
}) {
  final raw = path.startsWith('/') ? '$rootfs$path' : '$parent/$path';
  final parts = <String>[];
  for (final part in raw.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return '/${parts.join('/')}';
}

String _parent(String path) => path.substring(0, path.lastIndexOf('/'));

bool _withinRoot(String rootfs, String path) {
  final root = rootfs.endsWith('/')
      ? rootfs.substring(0, rootfs.length - 1)
      : rootfs;
  return path == root || path.startsWith('$root/');
}
