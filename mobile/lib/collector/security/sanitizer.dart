/// Sensitive data sanitizer — filters secrets, tokens and massive base64 payloads before sync.
class SanitizeResult {
  final String content;
  final int redactionCount;
  final bool hasSensitiveContent;

  const SanitizeResult({
    required this.content,
    required this.redactionCount,
    required this.hasSensitiveContent,
  });
}

class Sanitizer {
  static final List<MapEntry<RegExp, String>> _patterns = [
    // OpenAI / general API keys
    MapEntry(RegExp(r'sk-[a-zA-Z0-9]{20,}'), '[API_KEY_REDACTED]'),
    MapEntry(RegExp(r'sk-ant-[a-zA-Z0-9\-]{20,}'), '[ANTHROPIC_KEY_REDACTED]'),
    MapEntry(RegExp(r'sk-proj-[a-zA-Z0-9\-]{20,}'), '[OPENAI_KEY_REDACTED]'),

    // GitHub tokens
    MapEntry(RegExp(r'ghp_[a-zA-Z0-9]{36}'), '[GITHUB_TOKEN_REDACTED]'),
    MapEntry(RegExp(r'gho_[a-zA-Z0-9]{36}'), '[GITHUB_OAUTH_REDACTED]'),
    MapEntry(RegExp(r'github_pat_[a-zA-Z0-9_]{22,}'), '[GITHUB_PAT_REDACTED]'),

    // Slack / Telegram tokens
    MapEntry(RegExp(r'xox[baprs]-[a-zA-Z0-9\-]+'), '[SLACK_TOKEN_REDACTED]'),
    MapEntry(RegExp(r'bot\d+:[A-Za-z0-9_-]{35}'), '[TELEGRAM_BOT_TOKEN_REDACTED]'),
    MapEntry(RegExp(r'\d{8,}:[A-Za-z0-9_-]{35}'), '[TELEGRAM_TOKEN_REDACTED]'),

    // AWS keys
    MapEntry(RegExp(r'AKIA[0-9A-Z]{16}'), '[AWS_ACCESS_KEY_REDACTED]'),

    // Private keys
    MapEntry(
      RegExp(
        r'-----BEGIN\s+(RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END\s+(RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----',
        multiLine: true,
      ),
      '[PRIVATE_KEY_REDACTED]',
    ),

    // Generic key=value or key: value
    MapEntry(
      RegExp(
        r'(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)\s*[:=]\s*["\x27]?([^\s"\x27]{8,})["\x27]?',
        caseSensitive: false,
      ),
      r'$1=[REDACTED]',
    ),

    // Bearer tokens in headers
    MapEntry(RegExp(r'Bearer\s+[a-zA-Z0-9\-_.]+'), 'Bearer [TOKEN_REDACTED]'),

    // Embedded URL credentials (e.g. https://user:pass@host)
    MapEntry(RegExp(r'(https?://)[^\s:]{1,100}:[^\s@]{1,100}@'), r'$1[CREDS_REDACTED]@'),

    // Base64 oversized image replacement to keep memory small (< 200 bytes)
    MapEntry(
      RegExp(r'data:image/[a-zA-Z0-9\+\-]+;base64,[A-Za-z0-9+/=]{200,}'),
      '[IMAGE_DATA_OMITTED]',
    ),
  ];

  static const Set<String> _sensitiveKeys = {
    'token',
    'secret',
    'password',
    'apikey',
    'api_key',
    'accesstoken',
    'access_token',
    'refreshtoken',
    'refresh_token',
    'bottoken',
    'bot_token',
    'authtoken',
    'auth_token',
    'privatekey',
    'private_key',
    'credentials',
  };

  /// Sanitize plain text or markdown string
  static SanitizeResult sanitizeText(String text) {
    if (text.isEmpty) {
      return const SanitizeResult(content: '', redactionCount: 0, hasSensitiveContent: false);
    }

    int count = 0;
    String current = text;

    for (final entry in _patterns) {
      final matches = entry.key.allMatches(current);
      if (matches.isNotEmpty) {
        count += matches.length;
        if (entry.value.contains(r'$1')) {
          current = current.replaceAllMapped(entry.key, (m) {
            return entry.value.replaceAll(r'$1', m.group(1) ?? '');
          });
        } else {
          current = current.replaceAll(entry.key, entry.value);
        }
      }
    }

    return SanitizeResult(
      content: current,
      redactionCount: count,
      hasSensitiveContent: count > 0,
    );
  }

  /// Sanitize dynamic JSON object or list recursively
  static dynamic sanitizeJson(dynamic data) {
    if (data is Map) {
      final Map<String, dynamic> clean = {};
      for (final entry in data.entries) {
        final keyStr = entry.key.toString();
        if (_sensitiveKeys.contains(keyStr.toLowerCase())) {
          clean[keyStr] = '[REDACTED]';
        } else {
          clean[keyStr] = sanitizeJson(entry.value);
        }
      }
      return clean;
    } else if (data is List) {
      return data.map((item) => sanitizeJson(item)).toList();
    } else if (data is String) {
      return sanitizeText(data).content;
    }
    return data;
  }
}
