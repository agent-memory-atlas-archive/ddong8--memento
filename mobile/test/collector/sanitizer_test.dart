import 'package:flutter_test/flutter_test.dart';
import '../../lib/collector/security/sanitizer.dart';

void main() {
  group('Sanitizer Tests', () {
    test('redacts OpenAI and Anthropic API keys', () {
      const input = 'My key is sk-12345678901234567890abcdef and sk-ant-api03-abcdefghijklmn-1234567';
      final res = Sanitizer.sanitizeText(input);

      expect(res.hasSensitiveContent, isTrue);
      expect(res.content, contains('[API_KEY_REDACTED]'));
      expect(res.content, contains('[ANTHROPIC_KEY_REDACTED]'));
      expect(res.content, isNot(contains('sk-12345678901234567890abcdef')));
    });

    test('redacts GitHub and Slack tokens', () {
      const input = 'Token ghp_123456789012345678901234567890123456 and bot xoxb-12345678-abcdef';
      final res = Sanitizer.sanitizeText(input);

      expect(res.hasSensitiveContent, isTrue);
      expect(res.content, contains('[GITHUB_TOKEN_REDACTED]'));
      expect(res.content, contains('[SLACK_TOKEN_REDACTED]'));
    });

    test('redacts generic password and secret patterns', () {
      const input = 'DB_PASSWORD="SuperSecretPassword123" and api_key: "secretkey888"';
      final res = Sanitizer.sanitizeText(input);

      expect(res.hasSensitiveContent, isTrue);
      expect(res.content, contains('DB_PASSWORD=[REDACTED]'));
      expect(res.content, contains('api_key=[REDACTED]'));
      expect(res.content, isNot(contains('SuperSecretPassword123')));
    });

    test('omits large base64 image strings', () {
      final fakeBase64 = 'A' * 300;
      final input = 'Embedded screenshot: data:image/png;base64,$fakeBase64 in document';
      final res = Sanitizer.sanitizeText(input);

      expect(res.hasSensitiveContent, isTrue);
      expect(res.content, contains('[IMAGE_DATA_OMITTED]'));
      expect(res.content, isNot(contains(fakeBase64)));
    });

    test('sanitizes JSON map recursively', () {
      final jsonMap = {
        'name': 'test-project',
        'api_key': 'sensitive-value',
        'nested': {
          'password': 'my-db-pass',
          'normal': 'safe-text',
        }
      };

      final clean = Sanitizer.sanitizeJson(jsonMap) as Map<String, dynamic>;
      expect(clean['name'], equals('test-project'));
      expect(clean['api_key'], equals('[REDACTED]'));
      expect((clean['nested'] as Map)['password'], equals('[REDACTED]'));
      expect((clean['nested'] as Map)['normal'], equals('safe-text'));
    });
  });
}
