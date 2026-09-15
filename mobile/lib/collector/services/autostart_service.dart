import 'dart:io';
import 'package:path/path.dart' as p;

/// Service for managing automatic startup on user login across Windows, macOS, and Linux.
class AutostartService {
  static const String appName = 'Memento';

  /// Check if desktop platform (Windows / macOS / Linux)
  static bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Check if the standalone daemon process is already running
  static Future<bool> isDaemonRunning() async {
    try {
      final home = _userHome;
      final pidFile = File(p.join(home, '.memento', 'collector.pid'));
      if (await pidFile.exists()) {
        final pidStr = (await pidFile.readAsString()).trim();
        final pid = int.tryParse(pidStr);
        if (pid != null && pid > 0) {
          if (!Platform.isWindows) {
            final res = await Process.run('kill', ['-0', pid.toString()]);
            return res.exitCode == 0;
          } else {
            final res = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
            return res.exitCode == 0 && res.stdout.toString().contains(pid.toString());
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Check if autostart on login is currently enabled and points to current executable
  static Future<bool> isEnabled() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('reg', [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          appName,
        ]);
        if (result.exitCode != 0) return false;
        final output = result.stdout.toString();
        final currentExe = Platform.resolvedExecutable.toLowerCase();
        // Check if registry entry actually points to current executable (or current app directory)
        return output.toLowerCase().contains(p.basename(currentExe).toLowerCase());
      } else if (Platform.isMacOS) {
        final plistFile = File(_macLaunchAgentPath);
        return await plistFile.exists();
      } else if (Platform.isLinux) {
        final desktopFile = File(_linuxAutostartPath);
        return await desktopFile.exists();
      }
    } catch (_) {}
    return false;
  }

  /// Ensure autostart path is up-to-date.
  /// If autostart was enabled previously but pointed to a stale path (e.g. old Tauri client),
  /// update it to the current Flutter client path seamlessly.
  static Future<void> ensureCorrectPath() async {
    if (!isSupported) return;
    try {
      if (Platform.isWindows) {
        final result = await Process.run('reg', [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          appName,
        ]);
        if (result.exitCode == 0) {
          final output = result.stdout.toString();
          final currentExe = Platform.resolvedExecutable;
          // If registry exists but doesn't point to current executable, repair it
          if (!output.contains(currentExe)) {
            await enable();
          }
        }
      } else if (Platform.isMacOS) {
        final plist = File(_macLaunchAgentPath);
        if (await plist.exists()) {
          final content = await plist.readAsString();
          if (!content.contains(Platform.resolvedExecutable)) {
            await enable();
          }
        }
      } else if (Platform.isLinux) {
        final desktop = File(_linuxAutostartPath);
        if (await desktop.exists()) {
          final content = await desktop.readAsString();
          if (!content.contains(Platform.resolvedExecutable)) {
            await enable();
          }
        }
      }
    } catch (_) {}
  }

  /// Enable autostart on login across Windows, macOS, and Linux
  static Future<bool> enable() async {
    if (!isSupported) return false;
    try {
      final exePath = Platform.resolvedExecutable;

      if (Platform.isWindows) {
        // Add to Current User Run registry key with --minimized argument
        final result = await Process.run('reg', [
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          appName,
          '/t',
          'REG_SZ',
          '/d',
          '"$exePath" --minimized',
          '/f',
        ]);
        return result.exitCode == 0;
      } else if (Platform.isMacOS) {
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
        <string>--minimized</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>''';
        await plistFile.writeAsString(plistContent);
        return true;
      } else if (Platform.isLinux) {
        // XDG Desktop Autostart specification
        final desktopFile = File(_linuxAutostartPath);
        if (!await desktopFile.parent.exists()) {
          await desktopFile.parent.create(recursive: true);
        }
        final desktopContent = '''[Desktop Entry]
Type=Application
Version=1.0
Name=Memento
Comment=Memento AI Coding Assistant & Context Collector
Exec="$exePath" --minimized
Icon=memento
Terminal=false
StartupNotify=false
Categories=Utility;Development;
X-GNOME-Autostart-enabled=true
''';
        await desktopFile.writeAsString(desktopContent);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Disable autostart on login across all desktop platforms
  static Future<bool> disable() async {
    if (!isSupported) return false;
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
        return true;
      } else if (Platform.isLinux) {
        final desktopFile = File(_linuxAutostartPath);
        if (await desktopFile.exists()) {
          await desktopFile.delete();
          return true;
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  static String get _userHome =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';

  static String get _macLaunchAgentPath =>
      p.join(_userHome, 'Library', 'LaunchAgents', 'com.memento.app.plist');

  static String get _linuxAutostartPath =>
      p.join(_userHome, '.config', 'autostart', 'memento.desktop');
}
