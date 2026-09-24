import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memento_mobile/core/storage.dart';
import 'package:memento_mobile/models/ask_turn.dart';
import 'package:memento_mobile/state/ask_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Workspace Persistence Tests', () {
    test('AppStorage gets and sets workspace execution mode', () async {
      expect(await AppStorage.getLastExecutionMode(), isNull);

      await AppStorage.setLastExecutionMode('claude');
      expect(await AppStorage.getLastExecutionMode(), equals('claude'));

      await AppStorage.setLastExecutionMode(null);
      expect(await AppStorage.getLastExecutionMode(), isNull);
    });

    test('AppStorage gets and sets project and session context', () async {
      await AppStorage.setLastProjectId('proj-123');
      await AppStorage.setLastSessionId('session-456');

      expect(await AppStorage.getLastProjectId(), equals('proj-123'));
      expect(await AppStorage.getLastSessionId(), equals('session-456'));

      await AppStorage.setLastProjectId(null);
      await AppStorage.setLastSessionId(null);

      expect(await AppStorage.getLastProjectId(), isNull);
      expect(await AppStorage.getLastSessionId(), isNull);
    });

    test('AppStorage gets and sets model, custom model flag, effort, timeout, and cwd', () async {
      await AppStorage.setLastModel('sonnet');
      await AppStorage.setLastIsCustomModel(false);
      await AppStorage.setLastEffort('high');
      await AppStorage.setLastTimeoutSeconds(900);
      await AppStorage.setLastCwd('/Users/haixingdong/dev/memento');

      expect(await AppStorage.getLastModel(), equals('sonnet'));
      expect(await AppStorage.getLastIsCustomModel(), isFalse);
      expect(await AppStorage.getLastEffort(), equals('high'));
      expect(await AppStorage.getLastTimeoutSeconds(), equals(900));
      expect(await AppStorage.getLastCwd(), equals('/Users/haixingdong/dev/memento'));

      // Test custom model flag
      await AppStorage.setLastModel('deepseek-r1');
      await AppStorage.setLastIsCustomModel(true);
      expect(await AppStorage.getLastModel(), equals('deepseek-r1'));
      expect(await AppStorage.getLastIsCustomModel(), isTrue);
    });

    test('AskNotifier newChat and setSessionTurns reset last_ask_conversation_id', () async {
      await AppStorage.setLastAskConversationId('conv-789');
      expect(await AppStorage.getLastAskConversationId(), equals('conv-789'));

      final notifier = AskNotifier();
      notifier.newChat();
      expect(await AppStorage.getLastAskConversationId(), isNull);

      await AppStorage.setLastAskConversationId('conv-789');
      notifier.setSessionTurns([
        AskTurn(role: 'user', content: 'test'),
      ]);
      expect(await AppStorage.getLastAskConversationId(), isNull);
    });
  });
}
