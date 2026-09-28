import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/ui/screens/health_screen.dart';
import 'package:memento_mobile/ui/screens/memory_screen.dart';
import 'package:memento_mobile/ui/screens/skills_tab.dart';
import 'package:memento_mobile/ui/widgets/todo_panel.dart';

void main() {
  final today = DateTime(2026, 9, 28, 15);

  test('todo due state relative to today', () {
    expect(todoDueState(null, today), TodoDue.none);
    expect(todoDueState('2026-09-27', today), TodoDue.overdue);
    expect(todoDueState('2026-09-28', today), TodoDue.today);
    expect(todoDueState('2026-09-30', today), TodoDue.soon);
    expect(todoDueState('2026-10-07', today), TodoDue.later);
    expect(todoDueText('2026-09-25', today), '逾期 3 天');
    expect(todoDueText('2026-09-28', today), '今天到期');
    expect(todoDueText('2026-10-07', today), '10-7 到期');
  });

  test('skill write results collapse into counts', () {
    final c = skillResultCounts({
      'claude/a': 'written',
      'claude/b': 'unchanged',
      'agents/a': 'kept: edited locally',
      'agents': 'skipped: tool not installed',
      'claude/c': 'error: disk full',
      'claude/d': 'removed',
    });
    expect(c, {'ok': 2, 'kept': 1, 'skipped': 1, 'error': 1, 'removed': 1});
    expect(skillResultCounts(null), isEmpty);
  });

  test('review result reads as one line', () {
    expect(reviewLearned({}), '没有新东西');
    expect(
      reviewLearned({'skill': 'deploy', 'skill_event': 'new', 'pitfalls_new': 2, 'pitfalls_seen': ['x'], 'todos_new': 1}),
      '新技能 deploy · 2 个坑 · 又踩了 1 个老坑 · 1 条待办',
    );
  });

  test('memory status and source labels', () {
    expect(memoryStatusLabel('active'), isNull);
    expect(memoryStatusLabel(null), isNull);
    expect(memoryStatusLabel('dormant'), '沉睡');
    expect(memoryStatusLabel('superseded'), '已取代');
    expect(memorySourceLabel('outcome'), '🧭 会话复盘');
    expect(memorySourceLabel('manual'), '✍️ 手动');
  });

  test('inactive leaves and emptied folders are pruned from the tree', () {
    final tree = [
      {
        'is_folder': true,
        'children': [
          {'is_folder': false, 'status': 'active', 'id': 'a'},
          {'is_folder': false, 'status': 'dormant', 'id': 'b'},
        ],
      },
      {
        'is_folder': true,
        'children': [
          {'is_folder': false, 'status': 'superseded', 'id': 'c'},
        ],
      },
      {'is_folder': false, 'id': 'd'},
    ];
    final pruned = pruneInactiveMemories(tree);
    expect(pruned.length, 2);
    expect((pruned.first['children'] as List).map((n) => (n as Map)['id']), ['a']);
    expect(pruned.last['id'], 'd');
  });

  test('ratios render as whole percents', () {
    expect(healthPercent(null), '—');
    expect(healthPercent(0.6607), '66%');
    expect(healthPercent(1), '100%');
  });
}
