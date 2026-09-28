import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/ui/screens/persona_tab.dart';

void main() {
  test('diff compares bullet lines only', () {
    const published = '### 沟通\n- 用中文回复\n- 旧规则\n';
    const draft = '### 沟通\n- 用中文回复\n\n### 铁律\n- 只走 GitOps\n';
    final diff = personaLineDiff(draft, published);
    expect(diff.added, ['- 只走 GitOps']);
    expect(diff.removed, ['- 旧规则']);
  });

  test('diff against nothing published lists every bullet as added', () {
    expect(personaLineDiff('- a\n- b', null).added, ['- a', '- b']);
  });

  group('sections', () {
    test('groups bullets under their headings', () {
      final s = personaSections('### 沟通\n- 用中文回复\n- 先给结论\n\n### 铁律\n- 只走 GitOps\n');
      expect(s.map((e) => e.title), ['沟通', '铁律']);
      expect(s.first.items, ['用中文回复', '先给结论']);
      expect(s.last.items, ['只走 GitOps']);
    });

    test('bullets before any heading form an untitled group', () {
      final s = personaSections('- 用中文回复\n### 铁律\n- 只走 GitOps');
      expect(s.first.title, '');
      expect(s.first.items, ['用中文回复']);
    });

    test('prose without bullets falls back to markdown', () {
      expect(personaSections('这是一段没有条目的说明。'), isEmpty);
    });

    test('empty headings are dropped', () {
      expect(personaSections('### 沟通\n- a\n### 技术偏好\n').map((e) => e.title), ['沟通']);
    });
  });

  test('scope labels', () {
    expect(personaScopeLabel('project:chembook'), '只在「chembook」项目里');
    expect(personaScopeLabel('device:DESKTOP-KR9IPP4'), '只在「DESKTOP-KR9IPP4」这台设备上');
    expect(personaScopeLabel('global'), isNull);
    expect(personaScopeLabel(null), isNull);
    expect(personaSectionCaption('项目：chembook'), isNotNull);
    expect(personaSectionCaption('铁律'), isNull);
  });

  test('scoped sections parse as their own groups', () {
    final s = personaSections('### 沟通\n- 用中文回复\n\n## 项目：chembook\n- 结构式带手性');
    expect(s.map((e) => e.title), ['沟通', '项目：chembook']);
  });

  group('target state', () {
    PersonaTargetState? state(bool enabled, String? result, {int? reported = 2, int? published = 2}) =>
        personaTargetState(enabled: enabled, result: result, reportedVersion: reported, publishedVersion: published);

    test('off and never written shows nothing', () => expect(state(false, null), isNull));
    test('just enabled is pending', () => expect(state(true, null), PersonaTargetState.pending));
    test('written at current version', () => expect(state(true, 'written'), PersonaTargetState.written));
    test('older version is pending', () => expect(state(true, 'unchanged', reported: 1), PersonaTargetState.pending));
    test('switched off but not yet removed is pending', () => expect(state(false, 'written'), PersonaTargetState.pending));
    test('removed and off shows nothing', () => expect(state(false, 'removed'), isNull));
    test('errors surface', () => expect(state(true, 'error: disk full'), PersonaTargetState.error));
    test('missing tool is skipped', () =>
        expect(state(true, 'skipped: tool not installed'), PersonaTargetState.skipped));
  });
}
