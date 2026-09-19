import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../storage.dart';

/// Current application version — MUST match pubspec.yaml `version` on every release!
const String kAppCurrentVersion = '1.0.20';

class UpdateInfo {
  final String version;
  final String currentVersion;
  final bool hasUpdate;
  final String title;
  final String releaseNotes;
  final DateTime? publishedAt;
  final String? downloadUrl;
  final String? upstreamUrl;
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
    this.upstreamUrl,
    this.assetName,
    this.assetSize,
    required this.htmlUrl,
    this.isFromCustomServer = false,
  });
}

class UpdateService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent': 'Memento-Client/$kAppCurrentVersion',
    },
  ));

  /// Check update from primary Memento Server, with fallback to GitHub Releases
  static Future<UpdateInfo?> checkUpdate({String? customServerUrl, String? customRepo}) async {
    // Only desktop platforms (Windows, macOS, Linux) support in-app binary updates.
    // iOS and Android do not allow in-place binary execution or self-update.
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return null;
    }

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

        final upstreamUrl = data['upstream_url']?.toString();

        DateTime? publishedAt;
        if (data['published_at'] != null) {
          publishedAt = DateTime.tryParse(data['published_at'].toString());
        }

        // If server indicates update available but has no download url and no asset, fallback to GitHub
        if (hasUpdate && (downloadUrl == null || downloadUrl.isEmpty)) {
          debugPrint('[UpdateService] Server reported update but missing downloadUrl, falling back to GitHub');
          return null;
        }

        // If server says no update
        if (!hasUpdate && downloadUrl == null) {
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
              upstreamUrl: null,
              htmlUrl: serverUrl,
              isFromCustomServer: true,
            );
          }
          // If server data is stale (version older than client) or not hosted, fallback to GitHub
          if (latestVersion.isEmpty || isNewerVersion(kAppCurrentVersion, latestVersion)) {
            debugPrint('[UpdateService] Server version ($latestVersion) is older than client ($kAppCurrentVersion) or empty, falling back to GitHub');
            return null;
          }
        }

        return UpdateInfo(
          version: latestVersion.isNotEmpty ? latestVersion : kAppCurrentVersion,
          currentVersion: kAppCurrentVersion,
          hasUpdate: hasUpdate,
          title: title,
          releaseNotes: releaseNotes,
          publishedAt: publishedAt,
          downloadUrl: downloadUrl,
          upstreamUrl: upstreamUrl,
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
        if (aName.contains('win') || aName.contains('windows')) {
          // Prefer setup.exe for reliable UAC installer upgrade; fallback to .zip
          if (aName.endsWith('setup.exe') || aName.endsWith('.exe') || aName.endsWith('.msi')) {
            downloadUrl = aUrl;
            assetName = raw['name']?.toString();
            assetSize = aSize;
            break;
          } else if (aName.endsWith('.zip') && downloadUrl == null) {
            downloadUrl = aUrl;
            assetName = raw['name']?.toString();
            assetSize = aSize;
          }
        }
      } else if (Platform.isMacOS) {
        // Prefer .zip for fastest in-place hot auto-update; fallback to .dmg
        if ((aName.contains('mac') || aName.contains('darwin')) && aName.endsWith('.zip')) {
          downloadUrl = aUrl;
          assetName = raw['name']?.toString();
          assetSize = aSize;
          break;
        } else if ((aName.contains('mac') || aName.contains('darwin')) && aName.endsWith('.dmg') && downloadUrl == null) {
          downloadUrl = aUrl;
          assetName = raw['name']?.toString();
          assetSize = aSize;
        }
      } else if (Platform.isLinux) {
        if (aName.contains('linux')) {
          if (aName.endsWith('.tar.gz') || aName.endsWith('.appimage')) {
            downloadUrl = aUrl;
            assetName = raw['name']?.toString();
            assetSize = aSize;
            break;
          } else if (aName.endsWith('.deb') && downloadUrl == null) {
            downloadUrl = aUrl;
            assetName = raw['name']?.toString();
            assetSize = aSize;
          }
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
      upstreamUrl: downloadUrl,
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

  /// Get deterministic cache directory for update packages:
  /// e.g. <systemTemp>/memento_updates/<version>
  static Directory getUpdateCacheDir(String version) {
    final cleanVersion = version.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final dir = Directory(p.join(Directory.systemTemp.path, 'memento_updates', cleanVersion));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Get normalized file name for an update package
  static String getUpdateFileName(UpdateInfo info) {
    if (info.assetName != null && info.assetName!.isNotEmpty) {
      return info.assetName!;
    }
    if (info.downloadUrl != null && info.downloadUrl!.isNotEmpty) {
      try {
        final uri = Uri.parse(info.downloadUrl!);
        final bName = p.basename(uri.path);
        if (bName.isNotEmpty && bName.contains('.')) {
          return bName;
        }
      } catch (_) {}
    }
    return 'memento_update_${info.version}.zip';
  }

  /// Check if an update package has already been downloaded and is valid in local cache
  static Future<String?> checkCachedPackage(UpdateInfo info) async {
    try {
      final fileName = getUpdateFileName(info);
      final cacheDir = getUpdateCacheDir(info.version);
      final targetFile = File(p.join(cacheDir.path, fileName));
      if (await targetFile.exists()) {
        final size = await targetFile.length();
        // If we know expected size, verify size match; otherwise require > 1MB
        if (info.assetSize != null && info.assetSize! > 0) {
          if (size == info.assetSize) {
            return targetFile.path;
          }
        } else if (size > 1024 * 1024) {
          return targetFile.path;
        }
      }
    } catch (e) {
      debugPrint('[UpdateService] checkCachedPackage error: $e');
    }
    return null;
  }

  /// Download update package to deterministic local cache without triggering immediate installation.
  /// Returns the downloaded/cached file path if successful.
  static Future<String> downloadUpdate({
    required UpdateInfo info,
    void Function(String sourceLabel)? onSourceChanged,
    void Function(int received, int total)? onProgress,
    void Function(String error)? onError,
  }) async {
    // 1. Check if valid cached package already exists
    final cached = await checkCachedPackage(info);
    if (cached != null) {
      debugPrint('[UpdateService] Found cached update package at $cached, skipping download');
      onProgress?.call(info.assetSize ?? 100, info.assetSize ?? 100);
      return cached;
    }

    final downloadUrl = info.downloadUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      const err = '缺少有效的下载地址';
      onError?.call(err);
      throw Exception(err);
    }

    final fileName = getUpdateFileName(info);
    final cacheDir = getUpdateCacheDir(info.version);
    final savePath = p.join(cacheDir.path, fileName);
    final partPath = '$savePath.part';

    // Build structured candidate list with labeled routes
    final candidateList = <Map<String, String>>[];
    final seenUrls = <String>{};

    void addCandidate(String label, String? url) {
      if (url == null || url.trim().isEmpty) return;
      final clean = url.trim();
      if (seenUrls.add(clean)) {
        candidateList.add({'label': label, 'url': clean});
      }
    }

    // 1. Primary provided URL
    if (!downloadUrl.contains('github.com')) {
      addCandidate('私有服务器', downloadUrl);
    }

    // 2. Upstream GitHub Release Direct URL
    if (info.upstreamUrl != null && info.upstreamUrl!.isNotEmpty) {
      addCandidate('GitHub 官方源', info.upstreamUrl);
    } else if (info.version.isNotEmpty) {
      final tag = info.version.startsWith('v') ? info.version : 'v${info.version}';
      addCandidate('GitHub 官方源', 'https://github.com/ddong8/memento/releases/download/$tag/$fileName');
    } else if (downloadUrl.contains('github.com')) {
      addCandidate('GitHub 官方源', downloadUrl);
    }

    // 3. Fallback mirrors
    final primaryGhUrl = candidateList.firstWhere(
      (c) => c['url']!.contains('github.com'),
      orElse: () => {'url': ''},
    )['url'];

    if (primaryGhUrl != null && primaryGhUrl.isNotEmpty) {
      addCandidate('备选加速节点 1', 'https://ghfast.top/$primaryGhUrl');
      addCandidate('备选加速节点 2', 'https://ghproxy.net/$primaryGhUrl');
      addCandidate('备选加速节点 3', 'https://gh-proxy.com/$primaryGhUrl');
    }

    Object? lastError;
    bool downloaded = false;

    for (final candidate in candidateList) {
      final label = candidate['label']!;
      final targetUrl = candidate['url']!;
      onSourceChanged?.call(label);
      debugPrint('[UpdateService] Attempting download from [$label]: $targetUrl');

      try {
        final partFile = File(partPath);
        if (await partFile.exists()) {
          try { await partFile.delete(); } catch (_) {}
        }

        // Connect timeout is set to 8s: if the host is blocked/unreachable, quickly fail-over to the next candidate
        await _dio.download(
          targetUrl,
          partPath,
          onReceiveProgress: onProgress,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(minutes: 10),
          ),
        );

        if (await partFile.exists()) {
          final len = await partFile.length();
          if (len > 1024) {
            if (info.assetSize != null && info.assetSize! > 0) {
              if (len != info.assetSize) {
                throw Exception('下载包大小 ($len) 与预期 (${info.assetSize}) 不符');
              }
            }
            final finalFile = File(savePath);
            if (await finalFile.exists()) {
              try { await finalFile.delete(); } catch (_) {}
            }
            await partFile.rename(savePath);
            downloaded = true;
            debugPrint('[UpdateService] Successfully downloaded update from [$label] ($len bytes) to $savePath');
            break;
          }
        }
        throw Exception('下载文件大小异常或为空');
      } catch (e) {
        debugPrint('[UpdateService] Download attempt failed from [$label]: $e');
        lastError = e;
        final f = File(partPath);
        if (await f.exists()) {
          try { await f.delete(); } catch (_) {}
        }
      }
    }

    if (!downloaded) {
      final err = lastError != null ? '$lastError' : '所有更新下载通道均失败，请稍后重试';
      onError?.call(err);
      throw Exception(err);
    }

    return savePath;
  }

  /// Download asset with progress callback and initiate platform installation / in-place replacement
  static Future<void> downloadAndInstall({
    required String downloadUrl,
    String? upstreamUrl,
    String? version,
    String? fileName,
    void Function(String sourceLabel)? onSourceChanged,
    required void Function(int received, int total) onProgress,
    required void Function(String error) onError,
    required void Function(String savePath) onComplete,
  }) async {
    try {
      final info = UpdateInfo(
        version: version ?? 'latest',
        currentVersion: kAppCurrentVersion,
        hasUpdate: true,
        title: 'Memento Update',
        releaseNotes: '',
        downloadUrl: downloadUrl,
        upstreamUrl: upstreamUrl,
        assetName: fileName,
        htmlUrl: downloadUrl,
      );

      final savePath = await downloadUpdate(
        info: info,
        onSourceChanged: onSourceChanged,
        onProgress: onProgress,
        onError: onError,
      );

      onComplete(savePath);

      // Trigger installation or hot in-place replacement
      await installPackage(savePath);
    } catch (e) {
      debugPrint('[UpdateService] downloadAndInstall failed: $e');
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
        if (lowerPath.endsWith('.dmg')) {
          return await _installMacDmg(filePath);
        } else if (lowerPath.endsWith('.pkg')) {
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

  /// Resolve the enclosing .app bundle path from executable path on macOS
  static String _getMacAppBundlePath(String exePath) {
    final parts = p.split(exePath);
    final appIndex = parts.lastIndexWhere((part) => part.toLowerCase().endsWith('.app'));
    if (appIndex != -1) {
      return p.joinAll(parts.sublist(0, appIndex + 1));
    }
    return '/Applications/Memento.app';
  }

  /// Silently attach DMG, overwrite local Memento.app, detach and restart application
  static Future<bool> _installMacDmg(String dmgPath) async {
    try {
      final currentExe = Platform.resolvedExecutable;
      final targetApp = _getMacAppBundlePath(currentExe);
      final currentPid = pid;
      final tempDir = p.dirname(dmgPath);
      final shPath = p.join(tempDir, 'dmg_updater.sh');

      const shContent = '''#!/bin/sh
TARGET_PID="\$1"
DMG_PATH="\$2"
TARGET_APP="\$3"
TEMP_DIR="\$4"

# 1. Wait for current process to exit (with max 10s fallback)
COUNT=0
while kill -0 "\$TARGET_PID" 2>/dev/null; do
    sleep 0.5
    COUNT=\$((COUNT + 1))
    if [ "\$COUNT" -ge 20 ]; then
        kill -9 "\$TARGET_PID" 2>/dev/null
        break
    fi
done
sleep 1

# 2. Attach DMG silently
MOUNT_DIR=\$(mktemp -d /tmp/memento_mnt.XXXXXX)
hdiutil attach -nobrowse -readonly -mountpoint "\$MOUNT_DIR" "\$DMG_PATH"

# 3. Locate source .app inside mounted DMG
SRC_APP=\$(find "\$MOUNT_DIR" -maxdepth 2 -name "*.app" 2>/dev/null | head -n 1)

if [ -n "\$SRC_APP" ] && [ -d "\$SRC_APP" ] && [ -n "\$TARGET_APP" ]; then
    rm -rf "\$TARGET_APP"
    cp -R "\$SRC_APP" "\$TARGET_APP"
    xattr -cr "\$TARGET_APP" 2>/dev/null || true
    codesign --force --deep -s - -r='designated => identifier "com.ihasy.memento"' "\$TARGET_APP" 2>/dev/null || true
fi

# 4. Detach DMG and clean up
hdiutil detach "\$MOUNT_DIR" -force 2>/dev/null || true
rm -rf "\$MOUNT_DIR"
rm -f "\$DMG_PATH"
if [ -n "\$TEMP_DIR" ] && [ -d "\$TEMP_DIR" ]; then
    rm -rf "\$TEMP_DIR"
fi

# 5. Relaunch single instance
open "\$TARGET_APP"

rm -f "\$0"
''';
      await File(shPath).writeAsString(shContent);
      await Process.run('chmod', ['+x', shPath]);

      await Process.start(
        '/bin/sh',
        [shPath, currentPid.toString(), dmgPath, targetApp, tempDir],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (e) {
      debugPrint('[UpdateService] _installMacDmg failed, fallback to open: $e');
      await Process.run('open', [dmgPath]);
      return true;
    }
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

      // Detect real source directory (some archives wrap everything in a single
      // root folder, or contain stray marker files like .release_marker alongside
      // the actual content directory/app bundle)
      var sourceDir = extractDir.path;
      final entries = extractDir.listSync();
      // Filter to only directories — ignore loose marker files like .release_marker
      final subDirs = entries.whereType<Directory>().toList();
      if (subDirs.length == 1) {
        sourceDir = subDirs.first.path;
      }

      final currentExe = Platform.resolvedExecutable;
      final appDir = p.dirname(currentExe);
      final currentPid = pid;

      if (Platform.isWindows) {
        final expectedExeName = p.basename(currentExe).toLowerCase();
        final hasValidExe = Directory(sourceDir)
            .listSync(recursive: true)
            .any((f) => f.path.toLowerCase().endsWith(expectedExeName) || f.path.toLowerCase().endsWith('.exe'));
        if (!hasValidExe) {
          debugPrint('[UpdateService] Extracted package does not contain $expectedExeName! Aborting invalid hot-swap.');
          return false;
        }
      }

      debugPrint('[UpdateService] Ready to hot-swap. Source: $sourceDir, AppDir: $appDir, PID: $currentPid');

      if (Platform.isWindows) {
        // Windows: Create updater.ps1 and launcher.vbs (vbHide) for 100% zero-console-window silent hot replacement
        final ps1Path = p.join(tempDir, 'updater.ps1');
        final vbsPath = p.join(tempDir, 'launcher.vbs');

        const ps1Content = r'''param(
    [int]$TargetPid,
    [string]$SourceDir,
    [string]$DestDir,
    [string]$ExePath
)

# 1. Wait safely for the previous process to exit
if ($TargetPid -gt 0) {
    try {
        $proc = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
        if ($proc) {
            $null = $proc.WaitForExit(15000)
            Stop-Process -Id $TargetPid -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

# Buffer to ensure all file handles (dll, exe) are fully released
Start-Sleep -Milliseconds 800

# 2. Check write permission on target directory
$testFile = Join-Path $DestDir (".memento_test_" + [Guid]::NewGuid().ToString("N"))
$hasPermission = $false
try {
    [IO.File]::WriteAllText($testFile, "test")
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        $hasPermission = $true
    }
} catch {
    $hasPermission = $false
}

if (-not $hasPermission) {
    # Relaunch updater with Administrator privileges (UAC prompt) to overwrite Program Files safely
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`" 0 `"$SourceDir`" `"$DestDir`" `"$ExePath`""
    exit 0
}

# 3. Overwrite files into target app directory
try {
    Copy-Item -Path "$SourceDir\*" -Destination "$DestDir" -Recurse -Force -ErrorAction Stop
} catch {
    robocopy "$SourceDir" "$DestDir" /E /IS /IT /NP /R:3 /W:1 *>$null
}

# 4. Relaunch new version of the application
Start-Process -FilePath "$ExePath" -WorkingDirectory "$DestDir"

# 4. Clean up temporary extracted folder and updater scripts
Start-Sleep -Seconds 2
try {
    Remove-Item -LiteralPath "$SourceDir" -Recurse -Force -ErrorAction SilentlyContinue
    $parentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Remove-Item -LiteralPath (Join-Path $parentDir "launcher.vbs") -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
} catch {}
''';
        await File(ps1Path).writeAsString(ps1Content);

        // VBScript launches PowerShell with vbHide (0) and async (False) - zero console window
        final vbsContent = '''
Set WshShell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""$ps1Path"" $currentPid ""$sourceDir"" ""$appDir"" ""$currentExe"""
WshShell.Run cmd, 0, False
''';
        await File(vbsPath).writeAsString(vbsContent);

        // wscript.exe is a native GUI process: completely silent, detached, immune to console handle issues
        await Process.start(
          'wscript.exe',
          [vbsPath],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      } else if (Platform.isMacOS) {
        // macOS: Accurately locate .app bundle inside extractDir
        String? srcAppPath;
        // Search top-level and one level deep for .app bundle (avoid deep recursion inside .app)
        try {
          for (final entity in extractDir.listSync()) {
            if (entity is Directory && entity.path.endsWith('.app')) {
              srcAppPath = entity.path;
              break;
            }
          }
          // If not found at top level, check one level deep (e.g. zip wraps in subfolder)
          if (srcAppPath == null) {
            for (final entity in extractDir.listSync()) {
              if (entity is Directory && !entity.path.endsWith('.app')) {
                for (final sub in entity.listSync()) {
                  if (sub is Directory && sub.path.endsWith('.app')) {
                    srcAppPath = sub.path;
                    break;
                  }
                }
                if (srcAppPath != null) break;
              }
            }
          }
        } catch (_) {}
        srcAppPath ??= sourceDir;

        final targetApp = _getMacAppBundlePath(currentExe);
        debugPrint('[UpdateService] macOS hot replace: srcApp=$srcAppPath, targetApp=$targetApp');

        final shPath = p.join(tempDir, 'updater.sh');
        const shContent = '''#!/bin/sh
TARGET_PID="\$1"
SRC_APP="\$2"
TARGET_APP="\$3"
TEMP_DIR="\$4"

# 1. Wait for existing process to exit (with max 10s fallback)
COUNT=0
while kill -0 "\$TARGET_PID" 2>/dev/null; do
    sleep 0.5
    COUNT=\$((COUNT + 1))
    if [ "\$COUNT" -ge 20 ]; then
        kill -9 "\$TARGET_PID" 2>/dev/null
        break
    fi
done
sleep 1

# 2. Overwrite application bundle cleanly
if [ -n "\$SRC_APP" ] && [ -d "\$SRC_APP" ] && [ -n "\$TARGET_APP" ]; then
    rm -rf "\$TARGET_APP"
    cp -R "\$SRC_APP" "\$TARGET_APP"
    xattr -cr "\$TARGET_APP" 2>/dev/null || true
    codesign --force --deep -s - -r='designated => identifier "com.ihasy.memento"' "\$TARGET_APP" 2>/dev/null || true
fi

# 3. Clean up temporary extraction folder completely
if [ -n "\$TEMP_DIR" ] && [ -d "\$TEMP_DIR" ]; then
    rm -rf "\$TEMP_DIR"
fi

# 4. Relaunch single instance cleanly via open
open "\$TARGET_APP"

rm -f "\$0"
''';
        await File(shPath).writeAsString(shContent);
        await Process.run('chmod', ['+x', shPath]);

        await Process.start(
          '/bin/sh',
          [shPath, currentPid.toString(), srcAppPath, targetApp, tempDir],
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
  static Future<void> openReleasePage([String? url]) async {
    try {
      final target = (url != null && url.isNotEmpty)
          ? url
          : 'https://github.com/ddong8/memento/releases';
      final uri = Uri.parse(target);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}