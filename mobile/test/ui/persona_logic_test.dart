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
