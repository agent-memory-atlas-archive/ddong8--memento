import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service managing iOS short-term background execution tasks (beginBackgroundTask).
///
/// On iOS, when an app enters the background, threads are suspended within seconds.
/// Calling [begin] requests an extra execution window (up to ~30 seconds) from iOS,
/// allowing in-flight SSE streams or network requests to complete cleanly in the background.
///
/// On non-iOS platforms, all methods are safe no-ops.
class BackgroundTaskService {
  static const MethodChannel _channel = MethodChannel('com.ihasy.memento/background_task');
  static int _activeCount = 0;

  /// Begin a background task execution lock.
  /// Safe to call multiple times; internally ref-counted.
  static Future<void> begin({String name = 'memento_ask_stream'}) async {
    if (!kIsWeb && Platform.isIOS) {
      try {
        _activeCount++;
        if (_activeCount == 1) {
          await _channel.invokeMethod('beginBackgroundTask', {'name': name});
        }
      } catch (e) {
        debugPrint('[BackgroundTaskService] Failed to begin background task: $e');
      }
    }
  }

  /// End the background task execution lock.
  static Future<void> end() async {
    if (!kIsWeb && Platform.isIOS) {
      try {
        if (_activeCount > 0) {
          _activeCount--;
          if (_activeCount == 0) {
            await _channel.invokeMethod('endBackgroundTask');
          }
        }
      } catch (e) {
        debugPrint('[BackgroundTaskService] Failed to end background task: $e');
      }
    }
  }
}
