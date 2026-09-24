import 'package:shared_preferences/shared_preferences.dart';

/// Storage helper to persist tokens and server connection configuration
class AppStorage {
  static const String _keyServerUrl = 'server_url';
  static const String _keyToken = 'auth_token';
  static const String _keyCollectorToken = 'collector_token';
  static const String _keyUsername = 'auth_username';
  static const String _keyLastDeviceId = 'last_device_id';
  static const String _keyLastExecutionMode = 'last_execution_mode';
  static const String _keyLastProjectId = 'last_project_id';
  static const String _keyLastSessionId = 'last_session_id';
  static const String _keyLastModel = 'last_model';
  static const String _keyLastIsCustomModel = 'last_is_custom_model';
  static const String _keyLastEffort = 'last_effort';
  static const String _keyLastTimeoutSeconds = 'last_timeout_seconds';
  static const String _keyLastCwd = 'last_cwd';
  static const String _keyLastAskConversationId = 'last_ask_conversation_id';

  static const String defaultServerUrl = 'https://mem.ihasy.com';

  static SharedPreferences? _prefs;
  static String? _cachedServerUrl;
  static String? _cachedToken;
  static String? _cachedCollectorToken;
  static String? _cachedUsername;
  static String? _cachedLastDeviceId;
  static String? _cachedLastExecutionMode;
  static String? _cachedLastProjectId;
  static String? _cachedLastSessionId;
  static String? _cachedLastModel;
  static bool? _cachedLastIsCustomModel;
  static String? _cachedLastEffort;
  static int? _cachedLastTimeoutSeconds;
  static String? _cachedLastCwd;
  static String? _cachedLastAskConversationId;

  static Future<SharedPreferences?> _getPrefs() async {
    if (_prefs != null) return _prefs;
    try {
      return _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<String> getServerUrl() async {
    if (_cachedServerUrl != null) return _cachedServerUrl!;
    final prefs = await _getPrefs();
    _cachedServerUrl = prefs?.getString(_keyServerUrl) ?? defaultServerUrl;
    return _cachedServerUrl!;
  }

  static Future<void> setServerUrl(String url) async {
    var cleanUrl = url.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    _cachedServerUrl = cleanUrl;
    final prefs = await _getPrefs();
    await prefs?.setString(_keyServerUrl, cleanUrl);
  }

  static String get currentServerUrl => _cachedServerUrl ?? defaultServerUrl;
  static String? get currentToken => _cachedToken;

  static Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    final prefs = await _getPrefs();
    _cachedToken = prefs?.getString(_keyToken);
    return _cachedToken;
  }

  static Future<void> setToken(String? token) async {
    _cachedToken = token;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (token == null || token.isEmpty) {
      await prefs.remove(_keyToken);
    } else {
      await prefs.setString(_keyToken, token);
    }
  }

  static Future<String?> getCollectorToken() async {
    if (_cachedCollectorToken != null) return _cachedCollectorToken;
    final prefs = await _getPrefs();
    _cachedCollectorToken = prefs?.getString(_keyCollectorToken);
    return _cachedCollectorToken;
  }

  static Future<void> setCollectorToken(String? token) async {
    _cachedCollectorToken = token;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (token == null || token.isEmpty) {
      await prefs.remove(_keyCollectorToken);
    } else {
      await prefs.setString(_keyCollectorToken, token);
    }
  }

  static Future<String?> getUsername() async {
    if (_cachedUsername != null) return _cachedUsername;
    final prefs = await _getPrefs();
    _cachedUsername = prefs?.getString(_keyUsername);
    return _cachedUsername;
  }

  static Future<void> setUsername(String? username) async {
    _cachedUsername = username;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (username == null) {
      await prefs.remove(_keyUsername);
    } else {
      await prefs.setString(_keyUsername, username);
    }
  }

  static Future<String?> getLastDeviceId() async {
    if (_cachedLastDeviceId != null) return _cachedLastDeviceId;
    final prefs = await _getPrefs();
    _cachedLastDeviceId = prefs?.getString(_keyLastDeviceId);
    return _cachedLastDeviceId;
  }

  static Future<void> setLastDeviceId(String? deviceId) async {
    _cachedLastDeviceId = deviceId;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (deviceId == null) {
      await prefs.remove(_keyLastDeviceId);
    } else {
      await prefs.setString(_keyLastDeviceId, deviceId);
    }
  }

  // Workspace & Chat Context Persistence

  static Future<String?> getLastExecutionMode() async {
    if (_cachedLastExecutionMode != null) return _cachedLastExecutionMode;
    final prefs = await _getPrefs();
    _cachedLastExecutionMode = prefs?.getString(_keyLastExecutionMode);
    return _cachedLastExecutionMode;
  }

  static Future<void> setLastExecutionMode(String? mode) async {
    _cachedLastExecutionMode = mode;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (mode == null) {
      await prefs.remove(_keyLastExecutionMode);
    } else {
      await prefs.setString(_keyLastExecutionMode, mode);
    }
  }

  static Future<String?> getLastProjectId() async {
    if (_cachedLastProjectId != null) return _cachedLastProjectId;
    final prefs = await _getPrefs();
    _cachedLastProjectId = prefs?.getString(_keyLastProjectId);
    return _cachedLastProjectId;
  }

  static Future<void> setLastProjectId(String? projId) async {
    _cachedLastProjectId = projId;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (projId == null) {
      await prefs.remove(_keyLastProjectId);
    } else {
      await prefs.setString(_keyLastProjectId, projId);
    }
  }

  static Future<String?> getLastSessionId() async {
    if (_cachedLastSessionId != null) return _cachedLastSessionId;
    final prefs = await _getPrefs();
    _cachedLastSessionId = prefs?.getString(_keyLastSessionId);
    return _cachedLastSessionId;
  }

  static Future<void> setLastSessionId(String? sid) async {
    _cachedLastSessionId = sid;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (sid == null) {
      await prefs.remove(_keyLastSessionId);
    } else {
      await prefs.setString(_keyLastSessionId, sid);
    }
  }

  static Future<String?> getLastModel() async {
    if (_cachedLastModel != null) return _cachedLastModel;
    final prefs = await _getPrefs();
    _cachedLastModel = prefs?.getString(_keyLastModel);
    return _cachedLastModel;
  }

  static Future<void> setLastModel(String? model) async {
    _cachedLastModel = model;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (model == null) {
      await prefs.remove(_keyLastModel);
    } else {
      await prefs.setString(_keyLastModel, model);
    }
  }

  static Future<bool?> getLastIsCustomModel() async {
    if (_cachedLastIsCustomModel != null) return _cachedLastIsCustomModel;
    final prefs = await _getPrefs();
    _cachedLastIsCustomModel = prefs?.getBool(_keyLastIsCustomModel);
    return _cachedLastIsCustomModel;
  }

  static Future<void> setLastIsCustomModel(bool isCustom) async {
    _cachedLastIsCustomModel = isCustom;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.setBool(_keyLastIsCustomModel, isCustom);
  }

  static Future<String?> getLastEffort() async {
    if (_cachedLastEffort != null) return _cachedLastEffort;
    final prefs = await _getPrefs();
    _cachedLastEffort = prefs?.getString(_keyLastEffort);
    return _cachedLastEffort;
  }

  static Future<void> setLastEffort(String? effort) async {
    _cachedLastEffort = effort;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (effort == null) {
      await prefs.remove(_keyLastEffort);
    } else {
      await prefs.setString(_keyLastEffort, effort);
    }
  }

  static Future<int?> getLastTimeoutSeconds() async {
    if (_cachedLastTimeoutSeconds != null) return _cachedLastTimeoutSeconds;
    final prefs = await _getPrefs();
    _cachedLastTimeoutSeconds = prefs?.getInt(_keyLastTimeoutSeconds);
    return _cachedLastTimeoutSeconds;
  }

  static Future<void> setLastTimeoutSeconds(int? timeout) async {
    _cachedLastTimeoutSeconds = timeout;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (timeout == null) {
      await prefs.remove(_keyLastTimeoutSeconds);
    } else {
      await prefs.setInt(_keyLastTimeoutSeconds, timeout);
    }
  }

  static Future<String?> getLastCwd() async {
    if (_cachedLastCwd != null) return _cachedLastCwd;
    final prefs = await _getPrefs();
    _cachedLastCwd = prefs?.getString(_keyLastCwd);
    return _cachedLastCwd;
  }

  static Future<void> setLastCwd(String? cwd) async {
    _cachedLastCwd = cwd;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (cwd == null) {
      await prefs.remove(_keyLastCwd);
    } else {
      await prefs.setString(_keyLastCwd, cwd);
    }
  }

  static Future<String?> getLastAskConversationId() async {
    if (_cachedLastAskConversationId != null) return _cachedLastAskConversationId;
    final prefs = await _getPrefs();
    _cachedLastAskConversationId = prefs?.getString(_keyLastAskConversationId);
    return _cachedLastAskConversationId;
  }

  static Future<void> setLastAskConversationId(String? convId) async {
    _cachedLastAskConversationId = convId;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    if (convId == null) {
      await prefs.remove(_keyLastAskConversationId);
    } else {
      await prefs.setString(_keyLastAskConversationId, convId);
    }
  }

  static Future<void> clearSession() async {
    _cachedToken = null;
    _cachedUsername = null;
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUsername);
  }
}
