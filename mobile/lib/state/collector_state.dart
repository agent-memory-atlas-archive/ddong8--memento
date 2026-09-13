import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../collector/collector_controller.dart';

final collectorControllerProvider = Provider<CollectorController>((ref) {
  final controller = CollectorController();
  ref.onDispose(() => controller.dispose());
  return controller;
});

final collectorStatusProvider = StreamProvider<CollectorStatus>((ref) {
  final controller = ref.watch(collectorControllerProvider);
  return controller.statusStream;
});
