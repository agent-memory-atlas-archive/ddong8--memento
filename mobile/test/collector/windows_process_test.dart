import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/collector/services/ws_task_client.dart';

void main() {
  group('WsTaskClient Windows Process Execution Tests', () {
    test('Non-Windows platform runs executable directly with runInShell false', () async {
      final res = await WsTaskClient.prepareCommand(
        '/usr/local/bin/codex',
        ['exec', '-p', 'hello'],
        isWindowsOverride: false,
      );

      expect(res.executable, '/usr/local/bin/codex');
      expect(res.arguments, ['exec', '-p', 'hello']);
      expect(res.runInShell, isFalse);
    });

    test('Windows native .exe with spaces in path runs directly with runInShell false', () async {
      final res = await WsTaskClient.prepareCommand(
        r'C:\Program Files\OpenAI\codex.exe',
        ['exec', '-m', 'gpt-4o'],
        isWindowsOverride: true,
      );

      expect(res.executable, r'C:\Program Files\OpenAI\codex.exe');
      expect(res.arguments, ['exec', '-m', 'gpt-4o']);
      expect(res.runInShell, isFalse);
    });

    test('Windows npm batch script resolves directly to node.exe and JS script', () async {
      const npmCmdContent = '''
@ECHO off
GOTO start
:find_dp0
SET dp0=%~dp0
EXIT /b
:start
SETLOCAL
CALL :find_dp0

IF EXIST "%dp0%\\node.exe" (
  SET "_prog=%dp0%\\node.exe"
) ELSE (
  SET "_prog=node"
  SET PATHEXT=%PATHEXT:;.JS;=;%
)

endLocal & goto #_undefined_# 2>NUL || title %COMSPEC% & "%_prog%"  "%dp0%\\node_modules\\@openai\\codex\\bin\\codex.js" %*
''';

      final res = await WsTaskClient.prepareCommand(
        r'C:\Program Files\nodejs\codex.cmd',
        ['exec', '--skip-git-repo-check', 'hello'],
        isWindowsOverride: true,
        fileReaderOverride: (path) async => npmCmdContent,
        fileExistsOverride: (path) {
          // Both .cmd, node.exe, and target JS exist
          return true;
        },
      );

      expect(res.executable, contains('node.exe'));
      expect(res.arguments.first, contains(r'node_modules\@openai\codex\bin\codex.js'));
      expect(res.arguments.sublist(1), ['exec', '--skip-git-repo-check', 'hello']);
      expect(res.runInShell, isFalse);
    });

    test('Windows Python batch script resolves directly to python and py script', () async {
      const pyCmdContent = '@echo off\r\npython "C:\\Users\\admin\\AppData\\Local\\agy\\bin\\agy_cli.py" %*\r\n';

      final res = await WsTaskClient.prepareCommand(
        r'C:\Users\admin\AppData\Local\agy\bin\agy.cmd',
        ['-p', 'fix bug'],
        isWindowsOverride: true,
        fileReaderOverride: (path) async => pyCmdContent,
        fileExistsOverride: (path) => true,
      );

      expect(res.executable, 'python');
      expect(res.arguments.first, r'C:\Users\admin\AppData\Local\agy\bin\agy_cli.py');
      expect(res.arguments.sublist(1), ['-p', 'fix bug']);
      expect(res.runInShell, isFalse);
    });

    test('Windows arbitrary batch file with spaces uses COMSPEC /d /c call to prevent C:\\Program split', () async {
      final res = await WsTaskClient.prepareCommand(
        r'C:\Program Files\Some Vendor\custom_tool.bat',
        ['--flag', 'value with spaces'],
        isWindowsOverride: true,
        comSpecOverride: r'C:\Windows\system32\cmd.exe',
        fileReaderOverride: (path) async => '@echo custom batch script',
        fileExistsOverride: (path) => true,
      );

      expect(res.executable, r'C:\Windows\system32\cmd.exe');
      expect(res.arguments, [
        '/d',
        '/c',
        'call',
        r'C:\Program Files\Some Vendor\custom_tool.bat',
        '--flag',
        'value with spaces',
      ]);
      expect(res.runInShell, isFalse);
    });
  });
}
