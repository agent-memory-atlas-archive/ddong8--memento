import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

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
  });
}

class UpdateService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'application/vnd.github.v3+json',
      'User-Agent': 'Memento-Client/$kAppCurrentVersion',
    },
  ));

  /// Check GitHub Releases for newer version
  static Future<UpdateInfo?> checkUpdate({String? customRepo}) async {
    final repo = customRepo ?? 'ddong8/memento';
    final primaryUrl = 'https://api.github.com/repos/$repo/releases/latest';
    final fallbackUrl = 'https://mirror.ghproxy.com/https://api.github.com/repos/$repo/releases/latest';

    Map<String, dynamic>? data;

    // 1. Try primary GitHub API
    try {
      final res = await _dio.get(primaryUrl);
      if (res.statusCode == 200 && res.data is Map) {
        data = Map<String, dynamic>.from(res.data);
      }
    } catch (e) {
      debugPrint('[UpdateService] Primary check failed: $e, trying fallback proxy...');
    }

    // 2. Try proxy mirror if primary failed
    if (data == null) {
      try {
        final res = await _dio.get(fallbackUrl);
        if (res.statusCode == 200 && res.data is Map) {
          data = Map<String, dynamic>.from(res.data);
        }
      } catch (e) {
        debugPrint('[UpdateService] Fallback check failed: $e');
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
        if (aName.endsWith('.exe') || aName.endsWith('.msi') || (aName.contains('win') && aName.endsWith('.zip'))) {
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

    // If no platform-specific binary asset found, fallback to htmlUrl
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

  /// Download asset with progress callback and initiate platform installation
  static Future<void> downloadAndInstall({
    required String downloadUrl,
    String? fileName,
    required void Function(int received, int total) onProgress,
    required void Function(String error) onError,
    required void Function(String savePath) onComplete,
  }) async {
    try {
      final name = fileName ?? p.basename(Uri.parse(downloadUrl).path);
      final tempDir = Directory.systemTemp.createTempSync('memento_update_');
      final savePath = p.join(tempDir.path, name);

      // Support mirror for downloading GitHub release assets in China
      String finalUrl = downloadUrl;
      if (downloadUrl.contains('github.com') && !downloadUrl.contains('ghproxy')) {
        // Use ghproxy mirror for faster and stable asset download
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

      // Trigger installation
      await installPackage(savePath);
    } catch (e) {
      debugPrint('[UpdateService] Download failed: $e');
      onError('下载更新失败: $e');
    }
  }

  /// Launch platform native installer or open file
  static Future<bool> installPackage(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      if (Platform.isWindows) {
        if (filePath.toLowerCase().endsWith('.exe') || filePath.toLowerCase().endsWith('.msi')) {
          await Process.start(filePath, [], mode: ProcessStartMode.detached);
          exit(0);
        } else {
          // If zip or other asset, open the directory so user can extract
          await Process.run('explorer.exe', ['/select,', filePath]);
          return true;
        }
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
        return true;
      } else if (Platform.isLinux) {
        if (filePath.toLowerCase().endsWith('.appimage')) {
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