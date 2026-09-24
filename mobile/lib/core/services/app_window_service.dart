import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel service for interacting with native desktop window lifecycle
/// (showing, focusing, hiding to system tray / dock).
class AppWindowService {
  static const MethodChannel _channel = MethodChannel('com.ihasy.memento/app_window');

  /// Brings the main desktop window to the foreground and focuses it.
  /// If the window was hidden or minimized, it will be restored and ordered front.
  static Future<void> showMainWindow() async {
    if (kIsWeb) return;
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;

    try {
      await _channel.invokeMethod('showMainWindow');
    } catch (e) {
      debugPrint('[AppWindowService] showMainWindow failed or not implemented: $e');
    }
  }

  /// Hides the main desktop window to the system tray or menu bar.
  static Future<void> hideMainWindow() async {
    if (kIsWeb) return;
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;

    try {
      await _channel.invokeMethod('hideMainWindow');
    } catch (e) {
      debugPrint('[AppWindowService] hideMainWindow failed: $e');
    }
  }
}
