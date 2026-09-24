import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'app_window_service.dart';

/// Service managing single-instance locking and inter-process activation for desktop platforms.
///
/// On macOS, Windows, and Linux:
/// - The first instance (primary) binds to a deterministic loopback TCP port.
/// - Any subsequent instance (secondary) attempts to bind the port, detects collision,
///   sends an activation signal ('focus') to the primary instance, and terminates cleanly.
/// - The primary instance receives the signal and restores/focuses its native window.
class SingleInstanceService {
  static ServerSocket? _serverSocket;

  /// Calculate a deterministic loopback port based on the operating system user account
  /// to prevent collision between multiple OS users on the same machine.
  static int get singleInstancePort {
    final user = Platform.environment['USER'] ??
        Platform.environment['USERNAME'] ??
        Platform.environment['LOGNAME'] ??
        'default';
    return 45380 + (user.hashCode.abs() % 100);
  }

  /// Ensure this process is the sole active desktop instance.
  /// Returns `true` if this is the primary instance (should proceed with runApp).
  /// Returns `false` if an existing instance is already running (secondary should exit immediately).
  static Future<bool> ensureSingleInstance() async {
    if (kIsWeb) return true;
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return true;

    final port = singleInstancePort;

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      _listenForSignals(_serverSocket!);
      debugPrint('[SingleInstance] Primary instance acquired lock on port $port');
      return true;
    } on SocketException catch (_) {
      // Port already in use: Another instance is running
      debugPrint('[SingleInstance] Port $port is occupied. Notifying existing instance...');
      final contacted = await _notifyRunningInstance(port);
      if (contacted) {
        return false;
      }

      // If contacting failed (e.g. previous process crashed right at exit), retry binding once
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        _serverSocket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
          shared: false,
        );
        _listenForSignals(_serverSocket!);
        debugPrint('[SingleInstance] Primary instance acquired lock on retry on port $port');
        return true;
      } catch (retryError) {
        debugPrint('[SingleInstance] Bind retry failed ($retryError), continuing as fallback.');
        return true;
      }
    } catch (e) {
      debugPrint('[SingleInstance] Unexpected error in single-instance check: $e');
      return true;
    }
  }

  static void _listenForSignals(ServerSocket server) {
    server.listen(
      (socket) {
        socket.listen(
          (data) {
            try {
              final message = String.fromCharCodes(data).trim();
              if (message.startsWith('focus')) {
                debugPrint('[SingleInstance] Received focus signal from secondary launch.');
                AppWindowService.showMainWindow();
              }
            } catch (e) {
              debugPrint('[SingleInstance] Error parsing signal: $e');
            }
          },
          onError: (_) {},
          cancelOnError: true,
        );
      },
      onError: (err) {
        debugPrint('[SingleInstance] ServerSocket error: $err');
      },
    );
  }

  static Future<bool> _notifyRunningInstance(int port) async {
    try {
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 1500),
      );
      client.write('focus\n');
      await client.flush();
      await client.close();
      return true;
    } catch (e) {
      debugPrint('[SingleInstance] Failed to notify running instance: $e');
      return false;
    }
  }

  /// Close the server socket cleanly upon application termination.
  static Future<void> close() async {
    try {
      await _serverSocket?.close();
      _serverSocket = null;
    } catch (_) {}
  }
}
