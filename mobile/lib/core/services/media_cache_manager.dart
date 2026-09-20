import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum MediaCacheStatus {
  idle,
  caching,
  cached,
  failed,
}

class MediaCacheProgress {
  final String cacheKey;
  final MediaCacheStatus status;
  final double progress; // 0.0 to 1.0 (-1.0 if unknown)
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  final File? file;

  const MediaCacheProgress({
    required this.cacheKey,
    required this.status,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
    this.file,
  });

  bool get isCompleted => status == MediaCacheStatus.cached;
  bool get isCaching => status == MediaCacheStatus.caching;
  bool get hasFailed => status == MediaCacheStatus.failed;
}

/// MediaCacheManager handles local disk caching for media streams (video/audio).
/// It enables instant replay, offline seeking, and eliminates redundant bandwidth usage.
class MediaCacheManager {
  static MediaCacheManager? _instance;
  static MediaCacheManager get instance => _instance ??= MediaCacheManager();

  final Directory? _customCacheDir;
  final HttpClient Function()? _clientFactory;
  final Map<String, Future<File?>> _activeDownloads = {};
  final Map<String, MediaCacheProgress> _cacheStates = {};
  final StreamController<MediaCacheProgress> _progressStreamController =
      StreamController<MediaCacheProgress>.broadcast();

  MediaCacheManager({
    Directory? customCacheDir,
    HttpClient Function()? clientFactory,
  })  : _customCacheDir = customCacheDir,
        _clientFactory = clientFactory;

  Stream<MediaCacheProgress> get progressStream => _progressStreamController.stream;

  /// Returns current cache progress state for a key.
  MediaCacheProgress? getProgress(String cacheKey) => _cacheStates[cacheKey];

  /// Get or create the cache directory.
  Directory getCacheDirectory() {
    final dir = _customCacheDir ??
        Directory(p.join(Directory.systemTemp.path, 'memento_media_cache'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Generate a deterministic cache filename based on cacheKey.
  String getCacheFileName(String cacheKey, {String? defaultExt}) {
    // Extract extension if available
    String ext = defaultExt ?? '.mp4';
    try {
      final clean = cacheKey.split('?').first.split('#').first;
      final detectedExt = p.extension(clean);
      if (detectedExt.isNotEmpty && detectedExt.length <= 6) {
        ext = detectedExt;
      }
    } catch (_) {}

    final hash = sha256.convert(utf8.encode(cacheKey)).toString().substring(0, 24);
    return '$hash$ext';
  }

  /// Get target File location for a given cacheKey.
  File getTargetFile(String cacheKey, {String? defaultExt}) {
    final dir = getCacheDirectory();
    final fileName = getCacheFileName(cacheKey, defaultExt: defaultExt);
    return File(p.join(dir.path, fileName));
  }

  /// Synchronously check if valid cached file exists.
  File? getCachedFileSync(String cacheKey, {String? defaultExt}) {
    try {
      final file = getTargetFile(cacheKey, defaultExt: defaultExt);
      if (file.existsSync() && file.lengthSync() > 1024) {
        // Update access time asynchronously for LRU tracking
        file.setLastModified(DateTime.now()).catchError((_) {});
        return file;
      }
    } catch (_) {}
    return null;
  }

  /// Asynchronously check if valid cached file exists.
  Future<File?> getCachedFile(String cacheKey, {String? defaultExt}) async {
    return getCachedFileSync(cacheKey, defaultExt: defaultExt);
  }

  /// Checks if given cacheKey is cached on disk.
  bool isCached(String cacheKey, {String? defaultExt}) {
    return getCachedFileSync(cacheKey, defaultExt: defaultExt) != null;
  }

  /// Streams or downloads the media file to local disk cache in the background.
  /// Deduplicates parallel requests for the same cacheKey.
  Future<File?> startCaching(
    String url,
    String cacheKey, {
    String? defaultExt,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
    void Function(File file)? onCompleted,
  }) async {
    // 1. If already cached, return immediately
    final existing = getCachedFileSync(cacheKey, defaultExt: defaultExt);
    if (existing != null) {
      final progress = MediaCacheProgress(
        cacheKey: cacheKey,
        status: MediaCacheStatus.cached,
        progress: 1.0,
        receivedBytes: existing.lengthSync(),
        totalBytes: existing.lengthSync(),
        file: existing,
      );
      _cacheStates[cacheKey] = progress;
      _progressStreamController.add(progress);
      onProgress?.call(1.0);
      onCompleted?.call(existing);
      return existing;
    }

    // 2. If a download task is already in progress, join it
    if (_activeDownloads.containsKey(cacheKey)) {
      if (onProgress != null) {
        final current = _cacheStates[cacheKey];
        if (current != null && current.progress > 0) {
          onProgress(current.progress);
        }
      }
      return _activeDownloads[cacheKey]!;
    }

    // 3. Initiate a new download task
    final taskFuture = _downloadTask(
      url,
      cacheKey,
      defaultExt: defaultExt,
      headers: headers,
      onProgress: onProgress,
      onCompleted: onCompleted,
    );

    _activeDownloads[cacheKey] = taskFuture;
    return taskFuture;
  }

  Future<File?> _downloadTask(
    String url,
    String cacheKey, {
    String? defaultExt,
    Map<String, String>? headers,
    void Function(double progress)? onProgress,
    void Function(File file)? onCompleted,
  }) async {
    final targetFile = getTargetFile(cacheKey, defaultExt: defaultExt);
    final partFile = File('${targetFile.path}.part');

    _emitProgress(MediaCacheProgress(
      cacheKey: cacheKey,
      status: MediaCacheStatus.caching,
      progress: 0.0,
    ));

    HttpClient? client;
    try {
      client = _clientFactory != null
          ? _clientFactory!()
          : (HttpClient()
            ..badCertificateCallback = ((cert, host, port) => true)
            ..connectionTimeout = const Duration(seconds: 10));

      final req = await client.getUrl(Uri.parse(url));
      headers?.forEach((key, val) => req.headers.set(key, val));
      final resp = await req.close();

      if (resp.statusCode != HttpStatus.ok && resp.statusCode != HttpStatus.partialContent) {
        throw HttpException('Server returned HTTP ${resp.statusCode}');
      }

      final totalBytes = resp.contentLength;
      int receivedBytes = 0;

      if (partFile.existsSync()) {
        partFile.deleteSync();
      }

      final sink = partFile.openWrite();
      await for (final chunk in resp) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        final double ratio = (totalBytes > 0) ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : -1.0;
        final prog = MediaCacheProgress(
          cacheKey: cacheKey,
          status: MediaCacheStatus.caching,
          progress: ratio,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes > 0 ? totalBytes : 0,
        );
        _cacheStates[cacheKey] = prog;
        _progressStreamController.add(prog);
        onProgress?.call(ratio);
      }

      await sink.flush();
      await sink.close();

      // Integrity check
      if (totalBytes > 0 && partFile.lengthSync() < totalBytes) {
        throw const FileSystemException('Downloaded file is incomplete');
      }

      // Atomic rename to final cache file
      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      final finalFile = await partFile.rename(targetFile.path);

      final successState = MediaCacheProgress(
        cacheKey: cacheKey,
        status: MediaCacheStatus.cached,
        progress: 1.0,
        receivedBytes: finalFile.lengthSync(),
        totalBytes: finalFile.lengthSync(),
        file: finalFile,
      );
      _emitProgress(successState);
      onProgress?.call(1.0);
      onCompleted?.call(finalFile);

      // Async LRU enforcement
      unawaited(enforceMaxCacheSize());

      debugPrint('[MediaCacheManager] Successfully cached $cacheKey -> ${finalFile.path} (${finalFile.lengthSync()} bytes)');
      return finalFile;
    } catch (e) {
      debugPrint('[MediaCacheManager] Failed to cache $cacheKey: $e');
      if (partFile.existsSync()) {
        try {
          partFile.deleteSync();
        } catch (_) {}
      }
      _emitProgress(MediaCacheProgress(
        cacheKey: cacheKey,
        status: MediaCacheStatus.failed,
        error: e.toString(),
      ));
      return null;
    } finally {
      client?.close();
      _activeDownloads.remove(cacheKey);
    }
  }

  void _emitProgress(MediaCacheProgress progress) {
    _cacheStates[progress.cacheKey] = progress;
    _progressStreamController.add(progress);
  }

  /// Enforce maximum cache size by evicting least recently used (LRU) files.
  /// Default max size: 2 GB (2048 MB).
  Future<void> enforceMaxCacheSize({int maxBytes = 2 * 1024 * 1024 * 1024}) async {
    try {
      final dir = getCacheDirectory();
      if (!dir.existsSync()) return;

      final entities = dir.listSync();
      final now = DateTime.now();

      // Clean up orphaned .part files older than 2 hours
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.part')) {
          try {
            final stat = entity.statSync();
            if (now.difference(stat.modified).inHours >= 2) {
              entity.deleteSync();
            }
          } catch (_) {}
        }
      }

      // Calculate total cache size of completed files
      final files = <File>[];
      int totalSize = 0;

      for (final entity in entities) {
        if (entity is File && !entity.path.endsWith('.part')) {
          files.add(entity);
          totalSize += entity.lengthSync();
        }
      }

      if (totalSize <= maxBytes) return;

      debugPrint('[MediaCacheManager] Cache size ($totalSize bytes) exceeds limit ($maxBytes bytes), evicting LRU files...');

      // Sort by modified time ascending (oldest first)
      files.sort((a, b) {
        final aTime = a.lastModifiedSync();
        final bTime = b.lastModifiedSync();
        return aTime.compareTo(bTime);
      });

      // Evict down to 75% of maxBytes
      final targetSize = (maxBytes * 0.75).toInt();
      int currentSize = totalSize;

      for (final file in files) {
        if (currentSize <= targetSize) break;
        try {
          final size = file.lengthSync();
          file.deleteSync();
          currentSize -= size;
          debugPrint('[MediaCacheManager] Evicted LRU cached file: ${file.path}');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[MediaCacheManager] Error enforcing LRU cache limit: $e');
    }
  }

  /// Get total disk space occupied by cached media files in bytes.
  Future<int> getTotalCacheSizeBytes() async {
    try {
      final dir = getCacheDirectory();
      if (!dir.existsSync()) return 0;
      int total = 0;
      for (final entity in dir.listSync()) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Delete all cached media files.
  Future<void> clearAllCache() async {
    try {
      final dir = getCacheDirectory();
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
      _cacheStates.clear();
      debugPrint('[MediaCacheManager] Cleared all media cache.');
    } catch (e) {
      debugPrint('[MediaCacheManager] Failed to clear media cache: $e');
    }
  }

  /// Delete a single cached media file.
  Future<void> removeCachedFile(String cacheKey, {String? defaultExt}) async {
    try {
      final file = getTargetFile(cacheKey, defaultExt: defaultExt);
      if (file.existsSync()) {
        file.deleteSync();
      }
      final partFile = File('${file.path}.part');
      if (partFile.existsSync()) {
        partFile.deleteSync();
      }
      _cacheStates.remove(cacheKey);
    } catch (_) {}
  }
}
