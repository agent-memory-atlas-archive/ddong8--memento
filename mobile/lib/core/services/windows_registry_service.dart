import 'dart:io';
import 'package:path/path.dart' as p;
import 'update_service.dart';

/// Service managing Windows "Installed Apps" registration (Add/Remove Programs) and uninstaller.
class WindowsRegistryService {
  static const String appKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Memento';

  /// Register Memento in Windows "Installed apps" (Settings -> Apps -> Installed apps).
  /// Safe to call on every app launch; automatically updates version and paths.
  static Future<void> register() async {
    if (!Platform.isWindows) return;

    try {
      final currentExe = Platform.resolvedExecutable;
      final appDir = p.dirname(currentExe);
      final uninstallPs1 = p.join(appDir, 'uninstall.ps1');

      // 1. Generate uninstaller script in the app directory
      const scriptContent = '''
Add-Type -AssemblyName PresentationFramework
\$appDir = \$PSScriptRoot
\$ans = [System.Windows.MessageBox]::Show("确定要从这台电脑卸载 Memento 吗？`n`n点击“确定”将退出程序并清理系统注册信息与自启动配置。", "卸载 Memento", [System.Windows.MessageBoxButton]::OKCancel, [System.Windows.MessageBoxImage]::Question)
if (\$ans -eq [System.Windows.MessageBoxResult]::OK) {
    Stop-Process -Name memento -Force -ErrorAction SilentlyContinue
    reg delete "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" /v Memento /f 2>\$null
    reg delete "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Memento" /f 2>\$null
    
    \$ansData = [System.Windows.MessageBox]::Show("是否一并清理本地所有历史记忆和配置缓存（~/.memento）？", "清理缓存数据", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if (\$ansData -eq [System.Windows.MessageBoxResult]::Yes) {
        \$mementoData = Join-Path \$env:USERPROFILE ".memento"
        if (Test-Path \$mementoData) {
            Remove-Item -Path \$mementoData -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    [System.Windows.MessageBox]::Show("Memento 已成功卸载。您可以直接删除本应用文件夹：`n\$appDir", "卸载完成", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
}
''';
      final file = File(uninstallPs1);
      if (!await file.exists() || (await file.readAsString()) != scriptContent) {
        await file.writeAsString(scriptContent);
      }

      final uninstallCmd = 'powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "$uninstallPs1"';

      // 2. Set registry values under HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Memento
      final commands = [
        ['add', appKey, '/v', 'DisplayName', '/t', 'REG_SZ', '/d', 'Memento', '/f'],
        ['add', appKey, '/v', 'DisplayVersion', '/t', 'REG_SZ', '/d', kAppCurrentVersion, '/f'],
        ['add', appKey, '/v', 'Publisher', '/t', 'REG_SZ', '/d', 'Memento', '/f'],
        ['add', appKey, '/v', 'DisplayIcon', '/t', 'REG_SZ', '/d', '$currentExe,0', '/f'],
        ['add', appKey, '/v', 'InstallLocation', '/t', 'REG_SZ', '/d', appDir, '/f'],
        ['add', appKey, '/v', 'URLInfoAbout', '/t', 'REG_SZ', '/d', 'https://github.com/ddong8/memento', '/f'],
        ['add', appKey, '/v', 'UninstallString', '/t', 'REG_SZ', '/d', uninstallCmd, '/f'],
        ['add', appKey, '/v', 'EstimatedSize', '/t', 'REG_DWORD', '/d', '45000', '/f'],
        ['add', appKey, '/v', 'NoModify', '/t', 'REG_DWORD', '/d', '1', '/f'],
        ['add', appKey, '/v', 'NoRepair', '/t', 'REG_DWORD', '/d', '1', '/f'],
      ];

      for (final args in commands) {
        await Process.run('reg', args);
      }
    } catch (_) {}
  }

  /// Remove Memento from Windows "Installed apps"
  static Future<void> unregister() async {
    if (!Platform.isWindows) return;
    try {
      await Process.run('reg', ['delete', appKey, '/f']);
    } catch (_) {}
  }
}
