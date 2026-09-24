import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memento_mobile/models/ask_turn.dart';
import 'package:memento_mobile/state/ask_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AskNotifier Foreground Resumed Sync Tests', () {
    test('syncOnForegroundResumed returns early if activeConversationId is null', () async {
      final notifier = AskNotifier();
      // Initially activeConversationId is null
      expect(notifier.state.activeConversationId, isNull);
      await notifier.syncOnForegroundResumed();
      // Should remain untouched
      expect(notifier.state.turns, isEmpty);
      expect(notifier.state.isStreaming, isFalse);
    });

    test('syncOnForegroundResumed returns early if no sync is needed', () async {
      final notifier = AskNotifier();
      notifier.setSessionTurns([
        AskTurn(role: 'user', content: 'hello'),
        AskTurn(role: 'assistant', content: 'world'),
      ], title: 'Test Title');

      // No activeConversationId and completed content -> early return
      await notifier.syncOnForegroundResumed();
      expect(notifier.state.turns.length, equals(2));
      expect(notifier.state.turns.last.content, equals('world'));
    });

    test('syncOnForegroundResumed safely swallows network errors when activeConversationId is invalid', () async {
      final notifier = AskNotifier();
      // Set active conversation ID but simulate broken network / unconfigured client
      notifier.setSessionTurns([
        AskTurn(role: 'user', content: 'hello'),
        AskTurn(role: 'assistant', content: '部分内容... > ⚠️ *[网络连接提前中断，若回答未完成可发送“继续”]*'),
      ], title: 'Test Title');

      // Manually set activeConversationId to trigger sync check
      notifier.state = notifier.state.copyWith(
        activeConversationId: 'test-nonexistent-conv-id',
        isStreaming: true,
      );

      // Should safely handle network failure without throwing
      await expectLater(notifier.syncOnForegroundResumed(), completes);
    });
  });
}
