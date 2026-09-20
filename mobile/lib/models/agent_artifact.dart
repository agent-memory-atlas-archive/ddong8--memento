import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import '../core/storage.dart';

enum ArtifactType {
  video,
  audio,
  image,
  html,
  markdown,
  document,
  code;

  String get label {
    switch (this) {
      case ArtifactType.video:
        return '视频产物';
      case ArtifactType.audio:
        return '音频产物';
      case ArtifactType.image:
        return '图像产物';
      case ArtifactType.html:
        return '交互网页原型';
      case ArtifactType.markdown:
        return '排版报告';
      case ArtifactType.document:
        return '数据文档';
      case ArtifactType.code:
        return '源码/补丁';
    }
  }

  String get iconEmoji {
    switch (this) {
      case ArtifactType.video:
        return '🎬';
      case ArtifactType.audio:
        return '🎵';
      case ArtifactType.image:
        return '🖼️';
      case ArtifactType.html:
        return '🌐';
      case ArtifactType.markdown:
        return '📑';
      case ArtifactType.document:
        return '📊';
      case ArtifactType.code:
        return '💻';
    }
  }
}

/// Dual-mode playback source descriptor containing both direct IPv6 P2P URL
/// and central server relay fallback URL.
class PlaybackSourceInfo {
  final String primaryUrl;
  final String? p2pUrl;
  final String relayUrl;
  final bool hasP2p;
  final String? deviceName;

  const PlaybackSourceInfo({
    required this.primaryUrl,
    this.p2pUrl,
    required this.relayUrl,
    this.hasP2p = false,
    this.deviceName,
  });
}

class AgentArtifact {
  final String id;
  final String title;
  final ArtifactType type;
  final String rawPath;
  final String? deviceId;
  final String? sizeLabel;
  final String? rawMarkdownLink;

  AgentArtifact({
    required this.id,
    required this.title,
    required this.type,
    required this.rawPath,
    this.deviceId,
    this.sizeLabel,
    this.rawMarkdownLink,
  });

  /// Generate playable or streamable URL via Memento Server media proxy.
  String getStreamUrl(String serverBaseUrl, {String? token}) {
    if (rawPath.startsWith('http://') || rawPath.startsWith('https://')) {
      return rawPath;
    }
    final cleanPath = rawPath.replaceFirst(RegExp(r'^file://'), '');
    final base = serverBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final dev = deviceId != null && deviceId!.isNotEmpty ? deviceId! : 'auto';
    final fileName = p.basename(cleanPath);
    var url = '$base/api/devices/$dev/files/stream';
    if (fileName.isNotEmpty) {
      url += '/${Uri.encodeComponent(fileName)}';
    }
    url += '?path=${Uri.encodeComponent(cleanPath)}';
    final effectiveToken = token ?? AppStorage.currentToken;
    if (effectiveToken != null && effectiveToken.isNotEmpty) {
      url += '&token=${Uri.encodeComponent(effectiveToken)}';
    }
    return url;
  }

  /// Check if the artifact physical file exists directly on the local filesystem.
  bool get isLocalFile {
    if (rawPath.isEmpty) return false;
    final clean = rawPath.replaceFirst(RegExp(r'^file://'), '');
    try {
      return File(clean).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Returns local physical file if it exists on current host machine,
  /// otherwise returns server relay stream URL.
  String getPlayableSource(String serverBaseUrl, {String? token}) {
    if (rawPath.isNotEmpty) {
      final clean = rawPath.replaceFirst(RegExp(r'^file://'), '');
      try {
        final f = File(clean);
        if (f.existsSync()) {
          return f.path;
        }
      } catch (_) {}
    }
    return getStreamUrl(serverBaseUrl, token: token);
  }

  /// Resolves dual-mode playback sources: queries the server's playback-source endpoint
  /// for an IPv6 P2P direct URL while guaranteeing seamless server relay fallback.
  Future<PlaybackSourceInfo> resolvePlaybackSource(
    String serverBaseUrl, {
    String? token,
    Dio? dioClient,
  }) async {
    // 1. If it exists on local filesystem of current device, play directly!
    if (rawPath.isNotEmpty) {
      final clean = rawPath.replaceFirst(RegExp(r'^file://'), '');
      try {
        final f = File(clean);
        if (f.existsSync()) {
          return PlaybackSourceInfo(
            primaryUrl: f.path,
            relayUrl: f.path,
            hasP2p: false,
          );
        }
      } catch (_) {}
    }

    final relayUrl = getStreamUrl(serverBaseUrl, token: token);

    // 2. Query playback-source discovery API
    try {
      final cleanPath = rawPath.replaceFirst(RegExp(r'^file://'), '');
      final base = serverBaseUrl.replaceAll(RegExp(r'/+$'), '');
      final dev = deviceId != null && deviceId!.isNotEmpty ? deviceId! : 'auto';
      final effectiveToken = token ?? AppStorage.currentToken;

      final dio = dioClient ?? Dio(BaseOptions(
        connectTimeout: const Duration(milliseconds: 1500),
        receiveTimeout: const Duration(milliseconds: 1500),
      ));

      final uri = '$base/api/devices/$dev/files/playback-source';
      final queryParams = <String, dynamic>{
        'path': cleanPath,
        if (effectiveToken != null && effectiveToken.isNotEmpty) 'token': effectiveToken,
      };

      final resp = await dio.get(
        uri,
        queryParameters: queryParams,
        options: Options(headers: {
          if (effectiveToken != null && effectiveToken.isNotEmpty) 'Authorization': 'Bearer $effectiveToken',
        }),
      );

      if (resp.statusCode == 200 && resp.data is Map) {
        final data = resp.data as Map<String, dynamic>;
        final hasP2p = data['has_p2p'] == true;
        final p2pUrl = data['p2p_url']?.toString();
        final serverRelay = data['relay_url']?.toString() ?? relayUrl;
        final devName = data['device_name']?.toString();

        return PlaybackSourceInfo(
          primaryUrl: (hasP2p && p2pUrl != null && p2pUrl.isNotEmpty) ? p2pUrl : serverRelay,
          p2pUrl: hasP2p ? p2pUrl : null,
          relayUrl: serverRelay,
          hasP2p: hasP2p && p2pUrl != null && p2pUrl.isNotEmpty,
          deviceName: devName,
        );
      }
    } catch (_) {}

    return PlaybackSourceInfo(
      primaryUrl: relayUrl,
      p2pUrl: null,
      relayUrl: relayUrl,
      hasP2p: false,
    );
  }

  /// Sniff and extract artifacts from agent message turns.
  static List<AgentArtifact> extractArtifacts(String content, {String? defaultDeviceId}) {
    if (content.isEmpty) return [];

    final List<AgentArtifact> results = [];
    final seenPaths = <String>{};

    // 1. Structured tag: <memento-artifact ... />
    final tagRegex = RegExp(
      r'<memento-artifact\s+([^>]+)/?>',
      caseSensitive: false,
    );
    for (final match in tagRegex.allMatches(content)) {
      final attrs = match.group(1) ?? '';
      final pathMatch = RegExp(r'path="([^"]+)"').firstMatch(attrs);
      final titleMatch = RegExp(r'title="([^"]+)"').firstMatch(attrs);
      final typeMatch = RegExp(r'type="([^"]+)"').firstMatch(attrs);
      final sizeMatch = RegExp(r'size="([^"]+)"').firstMatch(attrs);
      final devMatch = RegExp(r'device="([^"]+)"').firstMatch(attrs);

      if (pathMatch != null) {
        final path = pathMatch.group(1)!;
        if (seenPaths.add(path)) {
          final type = _detectType(path, typeMatch?.group(1));
          if (type != null) {
            results.add(AgentArtifact(
              id: 'tag-${results.length + 1}',
              title: titleMatch?.group(1) ?? p.basename(path),
              type: type,
              rawPath: path,
              deviceId: devMatch?.group(1) ?? defaultDeviceId,
              sizeLabel: sizeMatch?.group(1),
            ));
          }
        }
      }
    }

    // 2. Markdown link regex: [title](path_or_url)
    final mdLinkRegex = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    for (final match in mdLinkRegex.allMatches(content)) {
      final title = match.group(1)!.trim();
      final pathOrUrl = match.group(2)!.trim();

      // Extract size in title if present like "生活片段 | 60 秒初稿（32 MB）"
      String? sizeStr;
      final sizeMatch = RegExp(r'[\(（](\d+(?:\.\d+)?\s*(?:MB|KB|GB|B))[\)）]', caseSensitive: false).firstMatch(title);
      if (sizeMatch != null) {
        sizeStr = sizeMatch.group(1);
      }

      final type = _detectType(pathOrUrl, null, titleText: title);
      if (type != null) {
        if (seenPaths.add(pathOrUrl)) {
          results.add(AgentArtifact(
            id: 'link-${results.length + 1}',
            title: title.replaceAll(RegExp(r'^[▶️🎬🎵🖼️🌐📑📊\s]+'), ''),
            type: type,
            rawPath: pathOrUrl,
            deviceId: defaultDeviceId,
            sizeLabel: sizeStr,
            rawMarkdownLink: match.group(0),
          ));
        }
      }
    }

    // 3. Raw file path enclosed in backticks: `/Volume1/.../output.mp4`
    final backtickRegex = RegExp(r'`((?:/[^`\r\n]+|[a-zA-Z]:\\[^`\r\n]+)\.([a-zA-Z0-9]{2,5}))`');
    for (final match in backtickRegex.allMatches(content)) {
      final rawPath = match.group(1)!.trim();
      final type = _detectType(rawPath, null);
      if (type != null && seenPaths.add(rawPath)) {
        results.add(AgentArtifact(
          id: 'code-${results.length + 1}',
          title: p.basename(rawPath),
          type: type,
          rawPath: rawPath,
          deviceId: defaultDeviceId,
          rawMarkdownLink: match.group(0),
        ));
      }
    }

    return results;
  }

  static ArtifactType? _detectType(String pathOrUrl, String? explicitType, {String? titleText}) {
    if (explicitType != null && explicitType.isNotEmpty) {
      switch (explicitType.toLowerCase()) {
        case 'video':
          return ArtifactType.video;
        case 'audio':
          return ArtifactType.audio;
        case 'image':
          return ArtifactType.image;
        case 'html':
          return ArtifactType.html;
        case 'markdown':
          return ArtifactType.markdown;
        case 'doc':
        case 'document':
          return ArtifactType.document;
        case 'code':
          return ArtifactType.code;
      }
    }

    final lower = pathOrUrl.toLowerCase().split('?').first;
    final ext = lower.contains('.') ? lower.split('.').last : '';

    if (const {'mp4', 'mov', 'webm', 'mkv', 'm4v', 'avi', 'flv'}.contains(ext)) {
      return ArtifactType.video;
    }
    if (const {'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'wma'}.contains(ext)) {
      return ArtifactType.audio;
    }
    if (const {'png', 'jpg', 'jpeg', 'webp', 'svg', 'gif', 'bmp'}.contains(ext)) {
      return ArtifactType.image;
    }
    if (const {'html', 'htm'}.contains(ext)) {
      return ArtifactType.html;
    }
    if (const {'md', 'markdown'}.contains(ext)) {
      return ArtifactType.markdown;
    }
    if (const {'pdf', 'csv', 'json', 'xlsx', 'xls', 'parquet'}.contains(ext)) {
      return ArtifactType.document;
    }

    // Contextual sniffing for links like [▶️ 打开视频](...)
    if (titleText != null) {
      final t = titleText.toLowerCase();
      if (t.contains('▶️') || t.contains('视频') || t.contains('video') || t.contains('秒初稿') || t.contains('剪辑初稿')) {
        return ArtifactType.video;
      }
      if (t.contains('音频') || t.contains('配乐') || t.contains('录音') || t.contains('audio') || t.contains('播客')) {
        return ArtifactType.audio;
      }
    }

    return null;
  }
}
