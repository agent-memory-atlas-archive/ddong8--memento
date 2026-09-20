import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/collector/services/p2p_media_server.dart';

void main() {
  HttpOverrides.global = null;

  group('P2pMediaServer IPv6 HTTP Streaming Tests', () {
    late Directory tempDir;
    late File testFile;
    late P2pMediaServer server;
    const testToken = 'test-secret-token-12345';
    late int port;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('p2p_test_');
      testFile = File('${tempDir.path}/sample.mp4');
      // Create a test file of 1000 bytes with known sequence
      final bytes = List<int>.generate(1000, (i) => i % 256);
      await testFile.writeAsBytes(bytes);

      server = P2pMediaServer(
        authToken: testToken,
        preferredPort: 0, // Ephemeral port
      );
      final ok = await server.start();
      expect(ok, isTrue);
      expect(server.isRunning, isTrue);
      port = server.port!;
      expect(port, greaterThan(0));
    });

    tearDown(() async {
      await server.stop();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('HEAD request with valid token returns file metadata and Accept-Ranges', () async {
      final client = HttpClient();
      final uri = Uri.parse('http://localhost:$port/p2p/stream?path=${Uri.encodeComponent(testFile.path)}&token=$testToken');
      final req = await client.headUrl(uri);
      final resp = await req.close();

      expect(resp.statusCode, HttpStatus.ok);
      expect(resp.headers.value('accept-ranges'), 'bytes');
      expect(resp.headers.value('content-length'), '1000');
      expect(resp.headers.contentType?.mimeType, 'video/mp4');
      client.close();
    });

    test('GET request without token is rejected with 403 Forbidden', () async {
      final client = HttpClient();
      final uri = Uri.parse('http://localhost:$port/p2p/stream?path=${Uri.encodeComponent(testFile.path)}');
      final req = await client.getUrl(uri);
      final resp = await req.close();

      expect(resp.statusCode, HttpStatus.forbidden);
      client.close();
    });

    test('GET request with Range header returns 206 Partial Content slice', () async {
      final client = HttpClient();
      final uri = Uri.parse('http://localhost:$port/p2p/stream?path=${Uri.encodeComponent(testFile.path)}&token=$testToken');
      final req = await client.getUrl(uri);
      req.headers.set('Range', 'bytes=100-199');
      final resp = await req.close();

      expect(resp.statusCode, HttpStatus.partialContent);
      expect(resp.headers.value('content-range'), 'bytes 100-199/1000');
      expect(resp.headers.value('content-length'), '100');

      final receivedBytes = <int>[];
      await for (final chunk in resp) {
        receivedBytes.addAll(chunk);
      }

      expect(receivedBytes.length, 100);
      expect(receivedBytes[0], 100 % 256);
      expect(receivedBytes[99], 199 % 256);
      client.close();
    });

    test('Path traversal attempt with .. is blocked with 403 Forbidden', () async {
      final client = HttpClient();
      final uri = Uri.parse('http://localhost:$port/p2p/stream?path=${Uri.encodeComponent("${tempDir.path}/../etc/passwd")}&token=$testToken');
      final req = await client.getUrl(uri);
      final resp = await req.close();

      expect(resp.statusCode, HttpStatus.forbidden);
      client.close();
    });
  });
}
