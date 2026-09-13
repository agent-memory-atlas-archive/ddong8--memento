import 'dart:io';
import 'package:path/path.dart' as p;

/// Service for managing automatic startup on user login across Windows and macOS.
class AutostartService {
  static const String appName = 'Memento';

  /// Check if autostart on login is currently enabled
  static Future<bool> isEnabled() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('reg', [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          appName,
        ]);
        return result.exitCode == 0;
      } else if (Platform.isMacOS) {
        final plistFile = File(_macLaunchAgentPath);
        return await plistFile.exists();
      }
    } catch (_) {}
    return false;
  }

  /// Enable autostart on login without requiring administrator privileges
  static Future<bool> enable() async {
    try {
      final exePath = Platform.resolvedExecutable;

      if (Platform.isWindows) {
        // Add to Current User Run registry key (no admin/UAC required)
        final result = await Process.run('reg', [
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          appName,
          '/t',
          'REG_SZ',
          '/d',
          '"$exePath"',
          '/f',
        ]);
        return result.exitCode == 0;
      } else if (Platform.isMacOS) {
        // Add user LaunchAgent plist
        final plistFile = File(_macLaunchAgentPath);
        if (!await plistFile.parent.exists()) {
          await plistFile.parent.create(recursive: true);
        }
        final plistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.memento.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>$exePath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>''';
        await plistFile.writeAsString(plistContent);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Disable autostart on login
  static Future<bool> disable() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('reg', [
          'delete',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          appName,
          '/f',
        ]);
        return result.exitCode == 0;
      } else if (Platform.isMacOS) {
        final plistFile = File(_macLaunchAgentPath);
        if (await plistFile.exists()) {
          await plistFile.delete();
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static String get _macLaunchAgentPath {
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, 'Library', 'LaunchAgents', 'com.memento.app.plist');
  }
}
