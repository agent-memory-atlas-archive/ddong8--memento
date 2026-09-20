import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Lightweight, secure IPv6 P2P HTTP Media Streaming Server.
///
/// Runs directly inside Memento Collector on remote host machines (Mac, Windows, Linux),
/// enabling clients on mobile and desktop to stream video artifacts at full broadband
/// line speed without incurring central relay server bandwidth or Base64 decoding overhead.
class P2pMediaServer {
  final String authToken;
  final int preferredPort;
  final void Function(String msg)? onLog;

  HttpServer? _server;
  int? _boundPort;
  String? _currentIpv6;
  bool _isRunning = false;

  P2pMediaServer({
    required this.authToken,
    this.preferredPort = 8765,
    this.onLog,
  });

  bool get isRunning => _isRunning;
  int? get port => _boundPort;
  String? get ipv6 => _currentIpv6;

  /// Start the IPv6 HTTP server
  Future<bool> start() async {
    if (_isRunning) return true;

    try {
      // 1. Discover local global IPv6 address
      _currentIpv6 = await findGlobalIpv6Address();

      // 2. Bind to any IPv6 interface (listen on [::])
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv6, preferredPort);
      } catch (e) {
        _log('Preferred port $preferredPort occupied or unavailable, falling back to ephemeral port: $e');
        _server = await HttpServer.bind(InternetAddress.anyIPv6, 0);
      }

      _boundPort = _server!.port;
      _isRunning = true;
      _log('IPv6 P2P Media Server listening on [::]:$_boundPort (Detected public IPv6: ${_currentIpv6 ?? "none"})');

      // 3. Process incoming HTTP requests
      _server!.listen(
        _handleRequest,
        onError: (err) => _log('P2P HTTP Server error: $err'),
      );
      return true;
    } catch (e) {
      _log('Failed to start IPv6 P2P Media Server: $e');
      _isRunning = false;
      return false;
    }
  }

  /// Stop and release the server
  Future<void> stop() async {
    _isRunning = false;
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _boundPort = null;
    _log('IPv6 P2P Media Server stopped');
  }

  /// Periodically or on-demand recheck public IPv6 address (handles ISP dynamic prefix changes)
  Future<String?> refreshIpv6Address() async {
    final updated = await findGlobalIpv6Address();
    if (updated != _currentIpv6) {
      _currentIpv6 = updated;
      _log('Updated P2P IPv6 address: $_currentIpv6');
    }
    return _currentIpv6;
  }

  /// Request handler supporting RFC 7233 Range requests and sub-second HEAD reachability probing
  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;

    // Standard CORS headers for cross-origin web/app streaming
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Range, Authorization, Content-Type');
    response.headers.set('Access-Control-Expose-Headers', 'Content-Range, Content-Length, Accept-Ranges');
    response.headers.set('Accept-Ranges', 'bytes');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    if (request.uri.path != '/p2p/stream' && request.uri.path != '/p2p/video') {
      response.statusCode = HttpStatus.notFound;
      response.write('Not Found');
      await response.close();
      return;
    }

    // 1. Authenticate request token
    final reqToken = request.uri.queryParameters['token'] ?? request.headers.value('x-p2p-token');
    if (authToken.isNotEmpty && reqToken != authToken) {
      response.statusCode = HttpStatus.forbidden;
      response.write('Invalid or missing P2P token');
      await response.close();
      return;
    }

    // 2. Validate file path
    final rawPath = request.uri.queryParameters['path'];
    if (rawPath == null || rawPath.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      response.write('Missing path parameter');
      await response.close();
      return;
    }

    var cleanPath = rawPath.replaceFirst(RegExp(r'^file://'), '');
    if (Platform.isWindows && cleanPath.startsWith('/') && cleanPath.length > 3 && cleanPath[2] == ':') {
      cleanPath = cleanPath.substring(1);
    }

    // Path traversal check
    if (cleanPath.split(RegExp(r'[/\\]')).contains('..')) {
      response.statusCode = HttpStatus.forbidden;
      response.write('Path traversal forbidden');
      await response.close();
      return;
    }

    final file = File(cleanPath);
    if (!await file.exists()) {
      response.statusCode = HttpStatus.notFound;
      response.write('File not found');
      await response.close();
      return;
    }

    final totalSize = await file.length();
    final ext = p.extension(cleanPath).toLowerCase();
    final mimeType = _resolveMimeType(ext);
    response.headers.contentType = ContentType.parse(mimeType);

    // 3. Process Range header (e.g. bytes=0-1048575 or bytes=1024-)
    final rangeHeader = request.headers.value('range');
    int start = 0;
    int end = totalSize > 0 ? totalSize - 1 : 0;
    bool isPartial = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeSpec = rangeHeader.replaceFirst('bytes=', '').trim();
      final parts = rangeSpec.split('-');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        start = int.tryParse(parts[0]) ?? 0;
      }
      if (parts.length > 1 && parts[1].isNotEmpty) {
        end = int.tryParse(parts[1]) ?? end;
      }
      if (end >= totalSize) {
        end = totalSize - 1;
      }
      isPartial = true;
    }

    if (start > end || (totalSize > 0 && start >= totalSize)) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set('Content-Range', 'bytes */$totalSize');
      await response.close();
      return;
    }

    final contentLength = totalSize > 0 ? (end - start + 1) : 0;
    response.headers.contentLength = contentLength;

    if (isPartial) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set('Content-Range', 'bytes $start-$end/$totalSize');
    } else {
      response.statusCode = HttpStatus.ok;
    }

    // 4. Handle HEAD request (fast connectivity check)
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }

    // 5. Stream byte slice to client
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      await raf.setPosition(start);

      const bufferSize = 64 * 1024; // 64 KB streaming chunks
      int bytesRemaining = contentLength;

      while (bytesRemaining > 0) {
        final toRead = bytesRemaining > bufferSize ? bufferSize : bytesRemaining;
        final buffer = await raf.read(toRead);
        if (buffer.isEmpty) break;
        response.add(buffer);
        await response.flush();
        bytesRemaining -= buffer.length;
      }
    } catch (e) {
      // Client disconnects or cancels stream
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
    }
  }

  static String _resolveMimeType(String ext) {
    switch (ext) {
      case '.mp4':
      case '.m4v':
        return 'video/mp4';
      case '.webm':
        return 'video/webm';
      case '.mov':
        return 'video/quicktime';
      case '.mkv':
        return 'video/x-matroska';
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.aac':
        return 'audio/mp4';
      case '.wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }

  /// Extract the first global unicast IPv6 address found on network interfaces
  static Future<String?> findGlobalIpv6Address() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv6,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address.toLowerCase();
          // Filter out link-local (fe80::), loopback (::1), unique local (fc00::/7, fd00::/8)
          if (ip.startsWith('fe8') ||
              ip.startsWith('fe9') ||
              ip.startsWith('fea') ||
              ip.startsWith('feb') ||
              ip.startsWith('fc') ||
              ip.startsWith('fd') ||
              ip == '::1' ||
              ip.isEmpty) {
            continue;
          }
          // Global unicast addresses start with 2xxx: or 3xxx:
          if (ip.startsWith('2') || ip.startsWith('3')) {
            return addr.address;
          }
        }
      }
      // Fallback: any non-link-local non-loopback IPv6
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address.toLowerCase();
          if (!ip.startsWith('fe8') &&
              !ip.startsWith('fe9') &&
              !ip.startsWith('fea') &&
              !ip.startsWith('feb') &&
              ip != '::1') {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  void _log(String msg) {
    if (onLog != null) {
      onLog!('[P2pMediaServer] $msg');
    } else {
      debugPrint('[P2pMediaServer] $msg');
    }
  }
}
