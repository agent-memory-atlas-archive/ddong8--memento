import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/core/sse_client.dart';
import 'package:memento_mobile/core/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('AskSseClient Resiliency & Error Recovery Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('ignores keepalive SSE comments and receives delta cleanly', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      await AppStorage.setServerUrl('http://127.0.0.1:${server.port}');

      server.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('text', 'event-stream');
        request.response.headers.set('Cache-Control', 'no-cache');

        request.response.write(': keepalive\n\n');
        await request.response.flush();

        request.response.write('data: {"type": "delta", "text": "Hello world"}\n\n');
        await request.response.flush();

        request.response.write('data: {"type": "done"}\n\n');
        await request.response.close();
      });

      final client = AskSseClient();
      final deltas = <String>[];
      final completer = Completer<void>();

      await client.ask(
        question: 'ping',
        onConversationId: (_, __) {},
        onSources: (_) {},
        onToolCall: (_) {},
        onTaskProgress: (_, __, ___, ____) {},
        onTaskChunk: (_, __, ___, ____, _____) {},
        onToolResult: (_, __, ___) {},
        onThinking: (_) {},
        onDelta: (text) => deltas.add(text),
        onError: (err) => fail('Should not error: $err'),
        onDone: () => completer.complete(),
      );

      await completer.future;
      await server.close();

      expect(deltas, equals(['Hello world']));
    });

    test('transparently retries when connection drops before first chunk', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      await AppStorage.setServerUrl('http://127.0.0.1:${server.port}');

      int requestCount = 0;
      server.listen((HttpRequest request) async {
        requestCount++;
        if (requestCount == 1) {
          // Simulate premature connection drop before any content
          request.response.headers.contentType = ContentType('text', 'event-stream');
          await request.response.flush();
          // Abruptly detach socket
          final socket = await request.response.detachSocket();
          socket.destroy();
        } else {
          // Second attempt succeeds
          request.response.headers.contentType = ContentType('text', 'event-stream');
          request.response.write('data: {"type": "delta", "text": "Recovered"}\n\n');
          request.response.write('data: {"type": "done"}\n\n');
          await request.response.close();
        }
      });

      final client = AskSseClient();
      final deltas = <String>[];
      final completer = Completer<void>();

      await client.ask(
        question: 'retry test',
        onConversationId: (_, __) {},
        onSources: (_) {},
        onToolCall: (_) {},
        onTaskProgress: (_, __, ___, ____) {},
        onTaskChunk: (_, __, ___, ____, _____) {},
        onToolResult: (_, __, ___) {},
        onThinking: (_) {},
        onDelta: (text) => deltas.add(text),
        onError: (err) => fail('Should have recovered on retry: $err'),
        onDone: () => completer.complete(),
      );

      await completer.future;
      await server.close();

      expect(requestCount, equals(2));
      expect(deltas, equals(['Recovered']));
    });

    test('returns friendly error message when all retries fail without content', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      await AppStorage.setServerUrl('http://127.0.0.1:${server.port}');

      server.listen((HttpRequest request) async {
        request.response.headers.contentType = ContentType('text', 'event-stream');
        await request.response.flush();
        final socket = await request.response.detachSocket();
        socket.destroy();
      });

      final client = AskSseClient();
      String? errorMessage;
      final completer = Completer<void>();

      await client.ask(
        question: 'fail test',
        onConversationId: (_, __) {},
        onSources: (_) {},
        onToolCall: (_) {},
        onTaskProgress: (_, __, ___, ____) {},
        onTaskChunk: (_, __, ___, ____, _____) {},
        onToolResult: (_, __, ___) {},
        onThinking: (_) {},
        onDelta: (_) {},
        onError: (err) {
          errorMessage = err;
        },
        onDone: () => completer.complete(),
      );

      await completer.future;
      await server.close();

      expect(errorMessage, isNotNull);
      expect(errorMessage, contains('服务器连接中断'));
      expect(errorMessage, isNot(contains('请求异常: HttpException')));
    });
  });
}
