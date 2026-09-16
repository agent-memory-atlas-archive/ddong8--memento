import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/collector/discovery/tool_discovery_service.dart';

void main() {
  group('ToolDiscoveryService Tests', () {
    test('isInvalidProjectName rejects dashes, symbols, and empty names', () {
      expect(ToolDiscoveryService.isInvalidProjectName('-'), isTrue);
      expect(ToolDiscoveryService.isInvalidProjectName('--'), isTrue);
      expect(ToolDiscoveryService.isInvalidProjectName('...'), isTrue);
      expect(ToolDiscoveryService.isInvalidProjectName('  -  '), isTrue);
      expect(ToolDiscoveryService.isInvalidProjectName('""'), isTrue);
      expect(ToolDiscoveryService.isInvalidProjectName('none'), isTrue);
      expect(ToolDiscoveryService.isInvalidProjectName('null'), isTrue);
      expect(ToolDiscoveryService.isInvalidProjectName('memento'), isFalse);
      expect(ToolDiscoveryService.isInvalidProjectName('quant_future'), isFalse);
    });

    test('decodeClaudeDir handles root slash and normal paths', () {
      // When Claude Code cwd is '/', dirName is '-'
      final (invalidName, invalidPath) = ToolDiscoveryService.decodeClaudeDir('-');
      expect(invalidName, isEmpty);
      expect(invalidPath, isEmpty);

      // Normal macOS path: -Users-haixingdong-Desktop-dev-memento
      final (name, path) = ToolDiscoveryService.decodeClaudeDir('-Users-haixingdong-Desktop-dev-memento');
      expect(name, 'memento');
      expect(path, '/Users/haixingdong/Desktop/dev/memento');
    });
  });
}
