import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../storage.dart';

/// Current application version
const String kAppCurrentVersion = '1.0.0';

class UpdateInfo {
  final String version;
  final String currentVersion;
  final bool hasUpdate;
  final String title;
  final String releaseNotes;
  final DateTime? publishedAt;
  final String? downloadUrl;
  final String? assetName;
  final int? assetSize;
  final String htmlUrl;
  final bool isFromCustomServer;

  UpdateInfo({
    required this.version,
    required this.currentVersion,
    required this.hasUpdate,
    required this.title,
    required this.releaseNotes,
    this.publishedAt,
    this.downloadUrl,
    this.assetName,
    this.assetSize,
    required this.htmlUrl,
    this.isFromCustomServer = false,
  });
}

class UpdateService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'Memento-Client/$kAppCurrentVersion',
    },
  ));

  /// Check update from primary Memento Server, with fallback to GitHub Releases
  static Future<UpdateInfo?> checkUpdate({String? customServerUrl, String? customRepo}) async {
    // 1. Try Memento Server first
    try {
      final serverUrl = (customServerUrl ?? await AppStorage.getServerUrl()).trim().replaceAll(RegExp(r'/+$'), '');
      if (serverUrl.isNotEmpty) {
        final serverInfo = await _checkServerUpdate(serverUrl);
        if (serverInfo != null) {
          debugPrint('[UpdateService] Successfully checked update from Memento Server: hasUpdate=${serverInfo.hasUpdate}, version=${serverInfo.version}');
          return serverInfo;
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] Server check failed, falling back to GitHub: $e');
    }

    // 2. Fallback to GitHub Releases API
    return _checkGithubUpdate(customRepo: customRepo);
  }

  /// Query Memento self-hosted update API: /api/system/update/check
  static Future<UpdateInfo?> _checkServerUpdate(String serverUrl) async {
    try {
      final platformStr = Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
              ? 'macos'
              : 'linux';

      final uri = '$serverUrl/api/system/update/check?platform=$platformStr&version=$kAppCurrentVersion';
      final res = await _dio.get(uri);
      if (res.statusCode == 200 && res.data is Map) {
        final data = Map<String, dynamic>.from(res.data);
        final hasUpdate = data['has_update'] == true;
        final latestVersion = (data['latest_version'] ?? '').toString();
        final releaseNotes = (data['release_notes'] ?? '').toString();
        final title = (data['title'] ?? 'Memento v$latestVersion').toString();
        final assetName = data['asset_name']?.toString();
        final assetSize = (data['asset_size'] is int) ? data['asset_size'] as int : null;

        String? downloadUrl = data['download_url']?.toString();
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          if (downloadUrl.startsWith('/')) {
            downloadUrl = '$serverUrl$downloadUrl';
          }
        }

        DateTime? publishedAt;
        if (data['published_at'] != null) {
          publishedAt = DateTime.tryParse(data['published_at'].toString());
        }

        // If server says no update or not hosted
        if (!hasUpdate && downloadUrl == null && (latestVersion.isEmpty || latestVersion == kAppCurrentVersion)) {
          // If server explicitly confirms current version is up to date
          if (latestVersion == kAppCurrentVersion) {
            return UpdateInfo(
              version: latestVersion,
              currentVersion: kAppCurrentVersion,
              hasUpdate: false,
              title: title,
              releaseNotes: releaseNotes.isNotEmpty ? releaseNotes : '当前已是最新版本',
              publishedAt: publishedAt,
              downloadUrl: null,
              htmlUrl: serverUrl,
              isFromCustomServer: true,
            );
          }
          // Server does not host updates, return null to fallback to GitHub
          return null;
        }

        return UpdateInfo(
          version: latestVersion.isNotEmpty ? latestVersion : kAppCurrentVersion,
          currentVersion: kAppCurrentVersion,
          hasUpdate: hasUpdate,
          title: title,
          releaseNotes: releaseNotes,
          publishedAt: publishedAt,
          downloadUrl: downloadUrl,
          assetName: assetName,
          assetSize: assetSize,
          htmlUrl: serverUrl,
          isFromCustomServer: true,
        );
      }
    } catch (e) {
      debugPrint('[UpdateService] _checkServerUpdate error: $e');
    }
    return null;
  }

  /// Check GitHub Releases for newer version
  static Future<UpdateInfo?> _checkGithubUpdate({String? customRepo}) async {
    final repo = customRepo ?? 'ddong8/memento';
    final primaryUrl = 'https://api.github.com/repos/$repo/releases/latest';
    final fallbackUrl = 'https://mirror.ghproxy.com/https://api.github.com/repos/$repo/releases/latest';

    Map<String, dynamic>? data;

    // 1. Try primary GitHub API
    try {
      final res = await _dio.get(primaryUrl, options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}));
      if (res.statusCode == 200 && res.data is Map) {
        data = Map<String, dynamic>.from(res.data);
      }
    } catch (e) {
      debugPrint('[UpdateService] GitHub primary check failed: $e, trying fallback proxy...');
    }

    // 2. Try proxy mirror if primary failed
    if (data == null) {
      try {
        final res = await _dio.get(fallbackUrl, options: Options(headers: {'Accept': 'application/vnd.github.v3+json'}));
        if (res.statusCode == 200 && res.data is Map) {
          data = Map<String, dynamic>.from(res.data);
        }
      } catch (e) {
        debugPrint('[UpdateService] GitHub fallback check failed: $e');
      }
    }

    if (data == null) return null;

    final tagName = (data['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
    final name = (data['name'] ?? tagName).toString();
    final body = (data['body'] ?? '暂无更新日志').toString();
    final htmlUrl = (data['html_url'] ?? 'https://github.com/$repo/releases').toString();
    DateTime? publishedAt;
    if (data['published_at'] != null) {
      publishedAt = DateTime.tryParse(data['published_at'].toString());
    }

    final hasUpdate = isNewerVersion(tagName, kAppCurrentVersion);

    // Find best asset for current operating system
    String? downloadUrl;
    String? assetName;
    int? assetSize;

    final assets = (data['assets'] as List<dynamic>?) ?? [];
    for (final raw in assets) {
      if (raw is! Map) continue;
      final aName = (raw['name'] ?? '').toString().toLowerCase();
      final aUrl = (raw['browser_download_url'] ?? '').toString();
      final aSize = (raw['size'] is int) ? raw['size'] as int : null;

      if (Platform.isWindows) {
        if (aName.endsWith('.zip') || aName.endsWith('.exe') || aName.endsWith('.msi')) {
          downloadUrl = aUrl;
          assetName = raw['name']?.toString();
          assetSize = aSize;
          break;
        }
      } else if (Platform.isMacOS) {
        if (aName.endsWith('.dmg') || (aName.contains('mac') && aName.endsWith('.zip'))) {
          downloadUrl = aUrl;
          assetName = raw['name']?.toString();
          assetSize = aSize;
          break;
        }
      } else if (Platform.isLinux) {
        if (aName.endsWith('.appimage') || aName.endsWith('.deb') || aName.endsWith('.tar.gz')) {
          downloadUrl = aUrl;
          assetName = raw['name']?.toString();
          assetSize = aSize;
          break;
        }
      }
    }

    downloadUrl ??= htmlUrl;

    return UpdateInfo(
      version: tagName,
      currentVersion: kAppCurrentVersion,
      hasUpdate: hasUpdate,
      title: name,
      releaseNotes: body,
      publishedAt: publishedAt,
      downloadUrl: downloadUrl,
      assetName: assetName,
      assetSize: assetSize,
      htmlUrl: htmlUrl,
      isFromCustomServer: false,
    );
  }

  /// SemVer comparison: returns true if target > current
  static bool isNewerVersion(String target, String current) {
    if (target.isEmpty) return false;
    final tParts = target.split('.').map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    final cParts = current.split('.').map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();

    final maxLen = tParts.length > cParts.length ? tParts.length : cParts.length;
    while (tParts.length < maxLen) {
      tParts.add(0);
    }
    while (cParts.length < maxLen) {
      cParts.add(0);
    }

    for (int i = 0; i < maxLen; i++) {
      if (tParts[i] > cParts[i]) return true;
      if (tParts[i] < cParts[i]) return false;
    }
    return false;
  }

  /// Download asset with progress callback and initiate platform installation / in-place replacement
  static Future<void> downloadAndInstall({
    required String downloadUrl,
    String? fileName,
    required void Function(int received, int total) onProgress,
    required void Function(String error) onError,
    required void Function(String savePath) onComplete,
  }) async {
    try {
      final uri = Uri.parse(downloadUrl);
      var name = fileName ?? p.basename(uri.path);
      if (name.isEmpty || !name.contains('.')) {
        name = 'memento_update_${DateTime.now().millisecondsSinceEpoch}.zip';
      }

      final tempDir = Directory.systemTemp.createTempSync('memento_update_');
      final savePath = p.join(tempDir.path, name);

      // Support mirror for downloading GitHub release assets in China
      String finalUrl = downloadUrl;
      if (downloadUrl.contains('github.com') && !downloadUrl.contains('ghproxy') && !downloadUrl.contains('mirror.ghproxy')) {
        finalUrl = 'https://mirror.ghproxy.com/$downloadUrl';
      }

      await _dio.download(
        finalUrl,
        savePath,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );

      onComplete(savePath);

      // Trigger installation or hot in-place replacement
      await installPackage(savePath);
    } catch (e) {
      debugPrint('[UpdateService] Download failed: $e');
      onError('下载更新失败: $e');
    }
  }

  /// Launch platform native installer or perform in-place self replacement
  static Future<bool> installPackage(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final lowerPath = filePath.toLowerCase();

      // 1. If it is a zip archive, perform in-place replacement and restart
      if (lowerPath.endsWith('.zip') || lowerPath.endsWith('.tar.gz')) {
        return await _performInPlaceReplacement(filePath);
      }

      // 2. Windows: Native installer (.exe / .msi)
      if (Platform.isWindows) {
        if (lowerPath.endsWith('.exe') || lowerPath.endsWith('.msi')) {
          await Process.start(filePath, [], mode: ProcessStartMode.detached);
          exit(0);
        } else {
          await Process.run('explorer.exe', ['/select,', filePath]);
          return true;
        }
      }

      // 3. macOS: Native installer (.dmg / .pkg)
      if (Platform.isMacOS) {
        if (lowerPath.endsWith('.dmg') || lowerPath.endsWith('.pkg')) {
          await Process.run('open', [filePath]);
          return true;
        }
      }

      // 4. Linux: AppImage / Deb
      if (Platform.isLinux) {
        if (lowerPath.endsWith('.appimage')) {
          await Process.run('chmod', ['+x', filePath]);
          await Process.start(filePath, [], mode: ProcessStartMode.detached);
          exit(0);
        } else {
          await Process.run('xdg-open', [p.dirname(filePath)]);
          return true;
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] installPackage failed: $e');
    }
    return false;
  }

  /// Perform in-place unzipping, file overwriting, and application restart
  static Future<bool> _performInPlaceReplacement(String archivePath) async {
    try {
      final tempDir = p.dirname(archivePath);
      final extractDir = Directory(p.join(tempDir, 'extracted'));
      if (!await extractDir.exists()) {
        await extractDir.create(recursive: true);
      }

      debugPrint('[UpdateService] Extracting $archivePath to ${extractDir.path}...');

      // Extract archive using system tool (tar is available on Windows 10+, macOS, Linux)
      bool extractSuccess = false;
      try {
        final res = await Process.run('tar', ['-xf', archivePath, '-C', extractDir.path]);
        if (res.exitCode == 0) {
          extractSuccess = true;
        } else {
          debugPrint('[UpdateService] tar extraction returned ${res.exitCode}: ${res.stderr}');
        }
      } catch (e) {
        debugPrint('[UpdateService] tar failed: $e, trying fallback extractor...');
      }

      // Fallback extraction
      if (!extractSuccess) {
        if (Platform.isWindows) {
          final psCmd = "Expand-Archive -LiteralPath '$archivePath' -DestinationPath '${extractDir.path}' -Force";
          final res = await Process.run('powershell', ['-NoProfile', '-Command', psCmd]);
          extractSuccess = res.exitCode == 0;
        } else {
          final res = await Process.run('unzip', ['-o', archivePath, '-d', extractDir.path]);
          extractSuccess = res.exitCode == 0;
        }
      }

      if (!extractSuccess) {
        debugPrint('[UpdateService] All extraction attempts failed');
        return false;
      }

      // Detect real source directory (some archives wrap everything in a single root folder)
      var sourceDir = extractDir.path;
      final entries = extractDir.listSync();
      if (entries.length == 1 && entries.first is Directory) {
        sourceDir = entries.first.path;
      }

      final currentExe = Platform.resolvedExecutable;
      final appDir = p.dirname(currentExe);
      final currentPid = pid;

      debugPrint('[UpdateService] Ready to hot-swap. Source: $sourceDir, AppDir: $appDir, PID: $currentPid');

      if (Platform.isWindows) {
        // Windows: Create updater.bat to wait for current process exit, copy files, and restart
        final batPath = p.join(tempDir, 'updater.bat');
        const batContent = '''
@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
set TARGET_PID=%~1
set SRC_DIR=%~2
set DEST_DIR=%~3
set EXE_PATH=%~4

:WAIT_LOOP
tasklist /FI "PID eq !TARGET_PID!" 2>NUL | find /I "!TARGET_PID!" >NUL
if not errorlevel 1 (
    timeout /t 1 /nobreak >NUL
    goto WAIT_LOOP
)

timeout /t 1 /nobreak >NUL

xcopy "!SRC_DIR!\\*" "!DEST_DIR!\\" /E /Y /I /Q >NUL

start "" "!EXE_PATH!"

rd /s /q "!SRC_DIR!" >NUL 2>&1
(goto) 2>nul & del "%~f0"
exit
''';
        await File(batPath).writeAsString(batContent);

        // Start updater detached and exit current process to release file locks
        await Process.start(
          'cmd.exe',
          ['/c', batPath, currentPid.toString(), sourceDir, appDir, currentExe],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      } else if (Platform.isMacOS) {
        // macOS: Create updater.sh
        final shPath = p.join(tempDir, 'updater.sh');
        const shContent = '''#!/bin/sh
TARGET_PID="\$1"
SRC_DIR="\$2"
DEST_DIR="\$3"
EXE_PATH="\$4"

while kill -0 "\$TARGET_PID" 2>/dev/null; do
    sleep 1
done
sleep 1

if [ -d "\$SRC_DIR/Memento.app" ]; then
    APP_TARGET=\$(echo "\$EXE_PATH" | sed -E 's/(.*\\.app).*/\\1/')
    if [ -n "\$APP_TARGET" ]; then
        rm -rf "\$APP_TARGET"
        cp -R "\$SRC_DIR/Memento.app" "\$APP_TARGET"
        open -n "\$APP_TARGET"
    else
        cp -R "\$SRC_DIR/"* "\$DEST_DIR/"
        open -n "\$EXE_PATH"
    fi
else
    cp -R "\$SRC_DIR/"* "\$DEST_DIR/"
    nohup "\$EXE_PATH" >/dev/null 2>&1 &
fi

rm -rf "\$SRC_DIR"
rm -f "\$0"
''';
        await File(shPath).writeAsString(shContent);
        await Process.run('chmod', ['+x', shPath]);

        await Process.start(
          shPath,
          [currentPid.toString(), sourceDir, appDir, currentExe],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      } else {
        // Linux: Create updater.sh
        final shPath = p.join(tempDir, 'updater.sh');
        const shContent = '''#!/bin/sh
TARGET_PID="\$1"
SRC_DIR="\$2"
DEST_DIR="\$3"
EXE_PATH="\$4"

while kill -0 "\$TARGET_PID" 2>/dev/null; do
    sleep 1
done
sleep 1

cp -rf "\$SRC_DIR/"* "\$DEST_DIR/"
chmod +x "\$EXE_PATH" 2>/dev/null || true
nohup "\$EXE_PATH" >/dev/null 2>&1 &

rm -rf "\$SRC_DIR"
rm -f "\$0"
''';
        await File(shPath).writeAsString(shContent);
        await Process.run('chmod', ['+x', shPath]);

        await Process.start(
          shPath,
          [currentPid.toString(), sourceDir, appDir, currentExe],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      }
    } catch (e) {
      debugPrint('[UpdateService] _performInPlaceReplacement error: $e');
    }
    return false;
  }

  /// Open release webpage in default browser
  static Future<void> openReleasePage(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}