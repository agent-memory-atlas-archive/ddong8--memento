import 'package:dio/dio.dart';
import '../models/ask_conversation.dart';
import 'storage.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Dynamic base URL from storage
          final serverUrl = await AppStorage.getServerUrl();
          options.baseUrl = serverUrl;

          // Inject token if available
          final token = await AppStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (e.response?.statusCode == 401) {
            // Token expired or invalid
            await AppStorage.clearSession();
          }
          return handler.next(e);
        },
      ),
    );
  }

  Dio get dio => _dio;

  // --- Auth Endpoints ---

  Future<Map<String, dynamic>> login(String usernameOrEmail, String password) async {
    final response = await _dio.post(
      '/api/auth/login',
      data: {
        'email': usernameOrEmail,
        'password': password,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final token = data['access_token'] ?? data['token'];
    if (token != null) {
      await AppStorage.setToken(token.toString());
      await AppStorage.setUsername(usernameOrEmail);
      try {
        final me = await getMe();
        final colToken = me['collector_token']?.toString();
        if (colToken != null && colToken.isNotEmpty) {
          await AppStorage.setCollectorToken(colToken);
        }
      } catch (_) {}
    }
    return data;
  }

  Future<Map<String, dynamic>> register(String email, String password) async {
    final response = await _dio.post(
      '/api/auth/register',
      data: {
        'email': email,
        'password': password,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _dio.get('/api/auth/me');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> refreshToken() async {
    final response = await _dio.post('/api/auth/refresh');
    final data = response.data as Map<String, dynamic>;
    final token = data['access_token'] ?? data['token'];
    if (token != null && token.toString().isNotEmpty) {
      await AppStorage.setToken(token.toString());
    }
    return data;
  }

  // --- Devices ---

  Future<List<Map<String, dynamic>>> getDevices() async {
    final response = await _dio.get('/api/devices');
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    if (data is Map && data['devices'] is List) {
      return (data['devices'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  // --- Memory Search & Timeline ---

  Future<Map<String, dynamic>> searchMemory(
    String query, {
    bool semantic = true,
    int limit = 30,
    int offset = 0,
    String? deviceId,
  }) async {
    final response = await _dio.get(
      '/api/search',
      queryParameters: {
        'q': query,
        'semantic': semantic ? '1' : '0',
        'limit': limit,
        'offset': offset,
        if (deviceId != null && deviceId != 'all') 'device_id': deviceId,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  // --- 3-Tier Memory & Dreaming Consolidation ---

  Future<Map<String, dynamic>> getMemoryTiers() async {
    final response = await _dio.get('/api/memory/tiers');
    return response.data as Map<String, dynamic>;
  }

  Future<List<dynamic>> getCoreMemories({String? category}) async {
    final response = await _dio.get(
      '/api/memory/core',
      queryParameters: {
        if (category != null) 'category': category,
      },
    );
    if (response.data is List) {
      return response.data as List<dynamic>;
    }
    return [];
  }

  Future<Map<String, dynamic>> getCoreMemoryTree() async {
    final response = await _dio.get('/api/memory/core/tree');
    return response.data as Map<String, dynamic>;
  }

  Future<String> getCoreMemoryMarkdown() async {
    final response = await _dio.get('/api/memory/core/markdown');
    return (response.data as Map<String, dynamic>)['markdown']?.toString() ?? '';
  }

  Future<Map<String, dynamic>> createCoreMemory(
    String category,
    String key,
    String content, {
    double confidence = 1.0,
    String? parentId,
    String? treePath,
    bool isFolder = false,
  }) async {
    final response = await _dio.post(
      '/api/memory/core',
      data: {
        'category': category,
        'key': key,
        'content': content,
        'confidence': confidence,
        if (parentId != null) 'parent_id': parentId,
        if (treePath != null) 'tree_path': treePath,
        'is_folder': isFolder,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCoreMemory(
    String id, {
    String? category,
    String? key,
    String? content,
    double? confidence,
    String? parentId,
    String? treePath,
    bool? isFolder,
  }) async {
    final response = await _dio.put(
      '/api/memory/core/$id',
      data: {
        if (category != null) 'category': category,
        if (key != null) 'key': key,
        if (content != null) 'content': content,
        if (confidence != null) 'confidence': confidence,
        if (parentId != null) 'parent_id': parentId,
        if (treePath != null) 'tree_path': treePath,
        if (isFolder != null) 'is_folder': isFolder,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteCoreMemory(String id) async {
    await _dio.delete('/api/memory/core/$id');
  }

  Future<Map<String, dynamic>> getDreamJournals({int limit = 20, int offset = 0}) async {
    final response = await _dio.get(
      '/api/memory/dreams',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDreamJournalDetail(String id) async {
    final response = await _dio.get('/api/memory/dreams/$id');
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> triggerDream({int daysBack = 1}) async {
    final response = await _dio.post(
      '/api/memory/dream',
      data: {'days_back': daysBack},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getDocument(String id) async {
    final response = await _dio.get('/api/documents/$id');
    return response.data as Map<String, dynamic>;
  }

  // --- Daily Summaries ---

  Future<List<Map<String, dynamic>>> getDailyDates() async {
    final response = await _dio.get('/api/daily');
    if (response.data is List) {
      return (response.data as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> getDailyDetail(String date) async {
    final response = await _dio.get('/api/daily/$date');
    return response.data as Map<String, dynamic>;
  }

  // --- Ask Conversations ---

  Future<List<AskConversationSummary>> getAskConversations({String? deviceId}) async {
    final response = await _dio.get(
      '/api/ask/conversations',
      queryParameters: {
        if (deviceId != null &&
            deviceId.isNotEmpty &&
            deviceId != 'auto' &&
            deviceId != 'ask_only' &&
            deviceId != 'all')
          'device_id': deviceId,
      },
    );
    final data = response.data;
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map((j) => AskConversationSummary.fromJson(j))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> getAskConversation(String id) async {
    final response = await _dio.get('/api/ask/conversations/$id');
    return response.data as Map<String, dynamic>;
  }

  Future<void> deleteAskConversation(String id) async {
    await _dio.delete('/api/ask/conversations/$id');
  }

  // --- Direct Command Dispatch ---

  Future<Map<String, dynamic>> dispatchCommand({
    required String deviceId,
    required String command,
    String? cwd,
  }) async {
    final response = await _dio.post(
      '/api/devices/$deviceId/commands',
      data: {
        'command': command,
        if (cwd != null && cwd.isNotEmpty) 'cwd': cwd,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  // --- Projects & Historical Sessions ---

  Future<List<Map<String, dynamic>>> getProjects({
    String? toolId,
    String? deviceId,
  }) async {
    final response = await _dio.get(
      '/api/projects',
      queryParameters: {
        if (toolId != null && toolId.isNotEmpty) 'tool_id': toolId,
        if (deviceId != null &&
            deviceId.isNotEmpty &&
            deviceId != 'auto' &&
            deviceId != 'ask_only' &&
            deviceId != 'all')
          'device_id': deviceId,
      },
    );
    final data = response.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<Map<String, dynamic>> getProjectConversations(
    String projectId, {
    int limit = 30,
    int maxMessagesPerSession = 5,
    String order = 'desc',
    String? deviceId,
  }) async {
    final response = await _dio.get(
      '/api/projects/$projectId/conversations',
      queryParameters: {
        'session_limit': limit,
        'max_messages_per_session': maxMessagesPerSession,
        'order': order,
        if (deviceId != null &&
            deviceId.isNotEmpty &&
            deviceId != 'auto' &&
            deviceId != 'ask_only' &&
            deviceId != 'all')
          'device_id': deviceId,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getConversationMessages(
    String id, {
    int offset = 0,
    int limit = 100,
  }) async {
    final response = await _dio.get(
      '/api/conversations/$id/messages',
      queryParameters: {
        'offset': offset,
        'limit': limit,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getAgentCapabilities(
    String tool, {
    String? deviceId,
  }) async {
    try {
      final response = await _dio.get(
        '/api/agent/capabilities',
        queryParameters: {
          'tool': tool,
          if (deviceId != null && deviceId.isNotEmpty && deviceId != 'auto' && deviceId != 'ask_only')
            'device_id': deviceId,
        },
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  Future<bool> sendTaskInput(String taskId, String input) async {
    try {
      final response = await _dio.post(
        '/api/tasks/$taskId/input',
        data: {'input': input},
      );
      return response.data?['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelTask(String taskId) async {
    try {
      final response = await _dio.post('/api/tasks/$taskId/cancel');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
