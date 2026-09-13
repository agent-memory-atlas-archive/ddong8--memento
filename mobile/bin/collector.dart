import 'dart:async';
import 'dart:io';

import 'package:memento_mobile/collector/collector_controller.dart';
import 'package:memento_mobile/collector/models/collector_config.dart';

/// Standalone CLI entrypoint for headless environments (Linux servers, NAS, or background daemons).
/// Can be compiled to a single native binary using:
///   dart compile exe bin/collector.dart -o memento-collector
void main(List<String> args) async {
  final command = args.isNotEmpty ? args.first.toLowerCase() : 'run';

  if (command == 'status') {
    final config = await CollectorConfig.load();
    stdout.writeln('=== Memento Collector Status ===');
    stdout.writeln('Device Name: ${config.deviceName}');
    stdout.writeln('Device ID:   ${config.deviceId}');
    stdout.writeln('Server URL:  ${config.serverUrl}');
    stdout.writeln('Platform:    ${config.platform}');
    stdout.writeln('Config Path: ${CollectorConfig.configFile.path}');
    return;
  }

  if (command == 'setup') {
    stdout.writeln('=== Memento Collector Setup ===\n');
    final config = await CollectorConfig.load();

    stdout.write('Server URL [${config.serverUrl}]: ');
    final urlInput = stdin.readLineSync()?.trim();
    final serverUrl = (urlInput != null && urlInput.isNotEmpty) ? urlInput : config.serverUrl;

    stdout.write('Collector Token: ');
    final tokenInput = stdin.readLineSync()?.trim();
    final token = (tokenInput != null && tokenInput.isNotEmpty) ? tokenInput : config.token;

    final updated = config.copyWith(serverUrl: serverUrl, token: token);
    await updated.save();
    stdout.writeln('\nConfiguration saved to ${CollectorConfig.configFile.path}');
    stdout.writeln("Run 'memento-collector' to start collecting.");
    return;
  }

  if (command == 'help' || command == '--help' || command == '-h') {
    stdout.writeln('Usage: memento-collector [command]');
    stdout.writeln('Commands:');
    stdout.writeln('  run (default)  Start the collector daemon in foreground');
    stdout.writeln('  status         Display current collector configuration');
    stdout.writeln('  setup          Configure server URL and token');
    return;
  }

  // Default: run daemon
  stdout.writeln('Starting Memento Collector Daemon...');
  final controller = CollectorController();

  controller.statusStream.listen((status) {
    if (status.isOnline) {
      stdout.writeln('[ONLINE 🟢] Connected to server: ${status.serverUrl}');
    }
  });

  await controller.start();

  // Handle SIGINT and SIGTERM
  final completer = Completer<void>();
  ProcessSignal.sigint.watch().listen((_) {
    stdout.writeln('\nReceived SIGINT, shutting down...');
    controller.stop();
    completer.complete();
  });

  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) {
      stdout.writeln('\nReceived SIGTERM, shutting down...');
      controller.stop();
      completer.complete();
    });
  }

  await completer.future;
  exit(0);
}
