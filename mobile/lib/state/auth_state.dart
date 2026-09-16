import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/storage.dart';

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? username;
  final String serverUrl;
  final String? errorMessage;

  AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.username,
    required this.serverUrl,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? username,
    String? serverUrl,
    String? errorMessage,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      username: username ?? this.username,
      serverUrl: serverUrl ?? this.serverUrl,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier()
      : super(AuthState(serverUrl: AppStorage.defaultServerUrl, isLoading: true)) {
    checkInitialAuth();
  }

  Future<void> checkInitialAuth() async {
    final serverUrl = await AppStorage.getServerUrl();
    final token = await AppStorage.getToken();
    final username = await AppStorage.getUsername();

    if (token != null && token.isNotEmpty) {
      try {
        await ApiClient().getMe();
        // Slide token forward silently
        ApiClient().refreshToken().catchError((_) => {});
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          username: username,
          serverUrl: serverUrl,
        );
        return;
      } on DioException catch (e) {
        // ONLY clear session if server explicitly returned HTTP 401 Unauthorized
        if (e.response?.statusCode == 401) {
          await AppStorage.clearSession();
          state = state.copyWith(
            isLoading: false,
            isAuthenticated: false,
            serverUrl: serverUrl,
          );
          return;
        } else {
          // Network error, DNS resolution after reboot, server starting up, or offline:
          // NEVER clear session! Stay logged in with saved token and username.
          state = state.copyWith(
            isLoading: false,
            isAuthenticated: true,
            username: username,
            serverUrl: serverUrl,
          );
          return;
        }
      } catch (_) {
        // Any non-auth error -> stay logged in!
        state = state.copyWith(
          isLoading: false,
          isAuthenticated: true,
          username: username,
          serverUrl: serverUrl,
        );
        return;
      }
    }

    state = state.copyWith(
      isLoading: false,
      isAuthenticated: false,
      serverUrl: serverUrl,
    );
  }

  Future<bool> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await ApiClient().login(username, password);
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        username: username,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '登录失败: 请检查账号密码或服务器连接',
      );
      return false;
    }
  }

  Future<void> updateServerUrl(String newUrl) async {
    await AppStorage.setServerUrl(newUrl);
    final savedUrl = await AppStorage.getServerUrl();
    state = state.copyWith(serverUrl: savedUrl);
  }

  Future<void> logout() async {
    await AppStorage.clearSession();
    state = state.copyWith(
      isAuthenticated: false,
      username: null,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
