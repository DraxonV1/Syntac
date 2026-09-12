// Bounded chat-owned task transitions. Invalid operations never mutate input.
import 'dart:convert';

Map<String, Object?> transitionChatTodo(
  Map<String, Object?> previous,
  Map<String, Object?> arguments,
) {
  String text(Object? value, String field) {
    if (value is! String || value.trim().isEmpty || value.length > 120) {
      throw FormatException('$field must contain 1–120 characters');
    }
    return value.trim();
  }

  final state = jsonDecode(jsonEncode(previous)) as Map<String, dynamic>;
  final phases = ((state['phases'] as List?) ?? [])
      .cast<Map<String, dynamic>>();
  final op = arguments['op'];
  final phaseName = arguments['phase'];
  final taskName = arguments['task'];
  final statuses = {
    'pending',
    'in_progress',
    'completed',
    'abandoned',
    'blocked',
  };

  List<Map<String, dynamic>> newTasks(Object? raw) {
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('items required');
    }
    return raw
        .map(
          (item) => <String, dynamic>{
            'text': text(item, 'Task'),
            'status': 'pending',
          },
        )
        .toList();
  }

  switch (op) {
    case 'view':
      break;
    case 'init':
      phases.clear();
      final list = arguments['list'];
      if (list != null) {
        if (list is! List || list.isEmpty) {
          throw const FormatException('list required');
        }
        for (final group in list) {
          if (group is! Map) throw const FormatException('Invalid phase');
          phases.add({
            'phase': text(group['phase'], 'Phase'),
            'items': newTasks(group['items']),
          });
        }
      } else {
        phases.add({'phase': 'Tasks', 'items': newTasks(arguments['items'])});
      }
      break;
    case 'append':
      final name = text(phaseName, 'Phase');
      final matches = phases.where((p) => p['phase'] == name).toList();
      final phase = matches.isEmpty
          ? <String, dynamic>{'phase': name, 'items': <dynamic>[]}
          : matches.single;
      if (matches.isEmpty) phases.add(phase);
      (phase['items'] as List).addAll(newTasks(arguments['items']));
      break;
    case 'rm':
      if (taskName == null && phaseName == null) {
        phases.clear();
      } else if (taskName == null) {
        final before = phases.length;
        phases.removeWhere((p) => p['phase'] == phaseName);
        if (phases.length == before) {
          throw const FormatException('Unknown phase');
        }
      } else {
        var removed = false;
        for (final phase in phases) {
          if (phaseName != null && phase['phase'] != phaseName) continue;
          (phase['items'] as List).removeWhere((item) {
            if ((item as Map)['text'] != taskName) return false;
            removed = true;
            return true;
          });
        }
        if (!removed) throw const FormatException('Unknown task');
      }
      break;
    case 'start':
    case 'done':
    case 'drop':
    case 'block':
    case 'unblock':
      if (taskName == null && phaseName == null) {
        throw const FormatException('task or phase required');
      }
      final targets = <Map>[];
      for (final phase in phases) {
        if (phaseName != null && phase['phase'] != phaseName) continue;
        for (final raw in phase['items'] as List) {
          final item = raw as Map;
          if (taskName == null || item['text'] == taskName) targets.add(item);
        }
      }
      if (targets.isEmpty) throw const FormatException('Unknown task or phase');
      if (op == 'start') {
        for (final task in [
          for (final phase in phases) ...(phase['items'] as List).cast<Map>(),
        ]) {
          if (task['status'] == 'in_progress') task['status'] = 'pending';
        }
      }
      for (final item in targets) {
        if (op == 'start' &&
            {'blocked', 'completed', 'abandoned'}.contains(item['status'])) {
          throw const FormatException(
            'Only pending tasks can start; unblock first',
          );
        }
        if (op == 'unblock' && item['status'] != 'blocked') {
          throw const FormatException('Only blocked tasks can be unblocked');
        }
        item['status'] = switch (op) {
          'start' => 'in_progress',
          'done' => 'completed',
          'drop' => 'abandoned',
          'block' => 'blocked',
          _ => 'pending',
        };
        item.remove('reason');
        if (op == 'block' && arguments['reason'] != null) {
          item['reason'] = text(arguments['reason'], 'Reason');
        }
      }
      break;
    default:
      throw const FormatException('Unknown todo operation');
  }

  final names = <String>{};
  final phaseNames = <String>{};
  final tasks = <Map>[];
  for (final phase in phases) {
    if (!phaseNames.add(text(phase['phase'], 'Phase'))) {
      throw const FormatException('Duplicate phase');
    }
    for (final raw in phase['items'] as List) {
      final item = raw as Map;
      if (!names.add(text(item['text'], 'Task'))) {
        throw const FormatException('Duplicate task');
      }
      if (!statuses.contains(item['status'])) {
        throw const FormatException('Invalid status');
      }
      tasks.add(item);
    }
  }
  if (phases.length > 8 || tasks.length > 40) {
    throw const FormatException('Todo limit: 8 phases and 40 tasks');
  }
  if (op != 'view') {
    var active = false;
    for (final task in tasks) {
      if (task['status'] != 'in_progress') continue;
      if (active) task['status'] = 'pending';
      active = true;
    }
    if (!active) {
      for (final task in tasks) {
        if (task['status'] == 'pending') {
          task['status'] = 'in_progress';
          break;
        }
      }
    }
  }
  final result = <String, Object?>{
    'phases': phases,
    'total': tasks.length,
    'completed': tasks.where((t) => t['status'] == 'completed').length,
  };
  if (jsonEncode(result).length > 9000) {
    throw const FormatException('Todo state exceeds 9000 characters');
  }
  return result;
}
