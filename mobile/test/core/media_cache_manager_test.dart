import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/core/services/media_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late Directory tempDir;
  late MediaCacheManager cacheManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('memento_cache_test_');
    cacheManager = MediaCacheManager(customCacheDir: tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('getCacheFileName generates deterministic name with extension', () {
    final name1 = cacheManager.getCacheFileName('/path/to/my_recording.mp4');
    final name2 = cacheManager.getCacheFileName('/path/to/my_recording.mp4');
    final nameOther = cacheManager.getCacheFileName('/path/to/other.mp4');

    expect(name1, equals(name2));
    expect(name1.endsWith('.mp4'), isTrue);
    expect(name1, isNot(equals(nameOther)));
  });

  test('getCachedFile returns null for uncached keys', () async {
    final file = await cacheManager.getCachedFile('unknown_video_key.mp4');
    expect(file, isNull);
    expect(cacheManager.isCached('unknown_video_key.mp4'), isFalse);
  });

  test('startCaching downloads, caches file atomically, and hits cache on replay', () async {
    // 1. Create a mock HTTP server serving a fake video file
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mockData = List<int>.generate(1024 * 64, (i) => i % 256); // 64KB mock video

    server.listen((HttpRequest request) {
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = mockData.length;
      request.response.add(mockData);
      request.response.close();
    });

    final testUrl = 'http://${server.address.host}:${server.port}/video.mp4';
    const cacheKey = '/remote/server/artifacts/recording_1.mp4';

    // 2. Start caching with progress tracking
    final progressUpdates = <double>[];
    final cachedFile = await cacheManager.startCaching(
      testUrl,
      cacheKey,
      onProgress: (p) => progressUpdates.add(p),
    );

    expect(cachedFile, isNotNull);
    expect(cachedFile!.existsSync(), isTrue);
    expect(cachedFile.lengthSync(), equals(mockData.length));
    expect(progressUpdates.isNotEmpty, isTrue);
    expect(progressUpdates.last, equals(1.0));

    // 3. Verify .part temporary file is removed after completion
    final partFile = File('${cachedFile.path}.part');
    expect(partFile.existsSync(), isFalse);

    // 4. Verify subsequent getCachedFile hits immediately without network
    final hitFile = await cacheManager.getCachedFile(cacheKey);
    expect(hitFile, isNotNull);
    expect(hitFile!.path, equals(cachedFile.path));
    expect(cacheManager.isCached(cacheKey), isTrue);

    // 5. Subsequent startCaching returns existing file directly
    bool subsequentHit = false;
    final cachedAgain = await cacheManager.startCaching(
      testUrl,
      cacheKey,
      onCompleted: (_) => subsequentHit = true,
    );
    expect(cachedAgain?.path, equals(cachedFile.path));
    expect(subsequentHit, isTrue);

    await server.close();
  });

  test('enforceMaxCacheSize evicts oldest files when threshold is exceeded', () async {
    final cacheDir = cacheManager.getCacheDirectory();
    final now = DateTime.now();

    // Create 3 files of 100KB each
    final f1 = File('${cacheDir.path}/video_oldest.mp4');
    f1.writeAsBytesSync(List.filled(100 * 1024, 1));
    f1.setLastModifiedSync(now.subtract(const Duration(hours: 3)));

    final f2 = File('${cacheDir.path}/video_middle.mp4');
    f2.writeAsBytesSync(List.filled(100 * 1024, 2));
    f2.setLastModifiedSync(now.subtract(const Duration(hours: 2)));

    final f3 = File('${cacheDir.path}/video_newest.mp4');
    f3.writeAsBytesSync(List.filled(100 * 1024, 3));
    f3.setLastModifiedSync(now.subtract(const Duration(hours: 1)));

    expect(await cacheManager.getTotalCacheSizeBytes(), equals(300 * 1024));

    // Enforce limit of 280KB:
    // targetSize = (280 * 1024 * 0.75).toInt() = 215040 (210KB)
    // Deleting f1 (100KB) reduces total to 200KB <= 210KB.
    // So only f1 is evicted, while f2 and f3 are preserved.
    await cacheManager.enforceMaxCacheSize(maxBytes: 280 * 1024);

    expect(f1.existsSync(), isFalse);
    expect(f2.existsSync(), isTrue);
    expect(f3.existsSync(), isTrue);
    expect(await cacheManager.getTotalCacheSizeBytes(), equals(200 * 1024));
  });

  test('clearAllCache deletes all cached files', () async {
    final cacheDir = cacheManager.getCacheDirectory();
    File('${cacheDir.path}/dummy1.mp4').writeAsStringSync('dummy 1');
    File('${cacheDir.path}/dummy2.mp4').writeAsStringSync('dummy 2');

    expect(await cacheManager.getTotalCacheSizeBytes(), greaterThan(0));

    await cacheManager.clearAllCache();

    expect(await cacheManager.getTotalCacheSizeBytes(), equals(0));
  });
}
