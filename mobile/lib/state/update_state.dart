import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/update_service.dart';

enum AppUpdateStatus {
  idle,
  checking,
  downloading,
  readyToInstall,
  installing,
  error,
}

class AppUpdateState {
  final AppUpdateStatus status;
  final UpdateInfo? info;
  final double progress; // 0.0 to 1.0
  final int receivedBytes;
  final int totalBytes;
  final String sourceLabel;
  final String? downloadedPath;
  final String? errorMessage;
  final DateTime? lastCheckedAt;

  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.info,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.sourceLabel = '',
    this.downloadedPath,
    this.errorMessage,
    this.lastCheckedAt,
  });

  bool get isDownloading => status == AppUpdateStatus.downloading;
  bool get isReadyToInstall => status == AppUpdateStatus.readyToInstall && downloadedPath != null;
  bool get isInstalling => status == AppUpdateStatus.installing;
  bool get isChecking => status == AppUpdateStatus.checking;
  bool get hasUpdate => info != null && info!.hasUpdate;

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    UpdateInfo? info,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? sourceLabel,
    String? downloadedPath,
    String? errorMessage,
    DateTime? lastCheckedAt,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      info: info ?? this.info,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      downloadedPath: downloadedPath ?? this.downloadedPath,
      errorMessage: errorMessage ?? this.errorMessage,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

class AppUpdateNotifier extends StateNotifier<AppUpdateState> {
  Timer? _periodicTimer;

  AppUpdateNotifier() : super(const AppUpdateState()) {
    // Only desktop platforms (macOS, Windows, Linux) support in-app silent downloads & self replacement
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // Check periodically every 15 minutes
      _periodicTimer = Timer.periodic(const Duration(minutes: 15), (_) {
        checkAndDownloadInBackground(silent: true);
      });
    }
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  /// Manually retry checking and downloading update
  Future<void> retry() async {
    await checkAndDownloadInBackground(silent: false);
  }

  /// Perform background check and silent download
  Future<void> checkAndDownloadInBackground({bool silent = true}) async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return;
    }

    // Do not interrupt ongoing downloads or installation
    if (state.isDownloading || state.isInstalling) {
      return;
    }

    // If update is already downloaded and verified, keep readyToInstall
    if (state.isReadyToInstall && state.downloadedPath != null) {
      final f = File(state.downloadedPath!);
      if (await f.exists() && await f.length() > 1024) {
        return;
      }
    }

    state = state.copyWith(status: AppUpdateStatus.checking, errorMessage: null);

    UpdateInfo? discoveredInfo;
    try {
      final info = await UpdateService.checkUpdate();
      discoveredInfo = info;
      final now = DateTime.now();

      if (info == null || !info.hasUpdate) {
        state = state.copyWith(
          status: AppUpdateStatus.idle,
          info: info,
          lastCheckedAt: now,
        );
        return;
      }

      // Check if this version has already been fully downloaded and cached locally
      final cachedPath = await UpdateService.checkCachedPackage(info);
      if (cachedPath != null) {
        debugPrint('[AppUpdateNotifier] Found complete cached package at $cachedPath for v${info.version}');
        state = state.copyWith(
          status: AppUpdateStatus.readyToInstall,
          info: info,
          downloadedPath: cachedPath,
          progress: 1.0,
          lastCheckedAt: now,
        );
        return;
      }

      // Start silent background download
      state = state.copyWith(
        status: AppUpdateStatus.downloading,
        info: info,
        progress: 0.0,
        receivedBytes: 0,
        totalBytes: info.assetSize ?? 0,
        sourceLabel: '',
        lastCheckedAt: now,
      );

      final savePath = await UpdateService.downloadUpdate(
        info: info,
        onSourceChanged: (source) {
          state = state.copyWith(sourceLabel: source);
        },
        onProgress: (received, total) {
          final p = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          state = state.copyWith(
            progress: p,
            receivedBytes: received,
            totalBytes: total,
          );
        },
        onError: (err) {
          state = state.copyWith(
            status: AppUpdateStatus.error,
            info: info,
            errorMessage: err,
          );
        },
      );

      state = state.copyWith(
        status: AppUpdateStatus.readyToInstall,
        info: info,
        downloadedPath: savePath,
        progress: 1.0,
      );
      debugPrint('[AppUpdateNotifier] Update package successfully ready to install: $savePath');
    } catch (e) {
      debugPrint('[AppUpdateNotifier] checkAndDownloadInBackground error: $e');
      state = state.copyWith(
        status: AppUpdateStatus.error,
        info: discoveredInfo ?? state.info,
        errorMessage: '$e',
      );
    }
  }

  /// User clicked the "Restart to Update" button
  Future<bool> applyUpdateAndRestart() async {
    final path = state.downloadedPath;
    if (path == null) {
      state = state.copyWith(
        status: AppUpdateStatus.error,
        errorMessage: '未找到已下载的更新包',
      );
      return false;
    }

    final file = File(path);
    if (!await file.exists()) {
      state = state.copyWith(
        status: AppUpdateStatus.idle,
        downloadedPath: null,
        errorMessage: '更新包文件已不存在，请重新下载',
      );
      checkAndDownloadInBackground(silent: false);
      return false;
    }

    state = state.copyWith(status: AppUpdateStatus.installing);

    final ok = await UpdateService.installPackage(path);
    if (!ok) {
      state = state.copyWith(
        status: AppUpdateStatus.readyToInstall,
        errorMessage: '重启更新失败，请手动解压安装或稍后重试',
      );
      return false;
    }

    return true;
  }

  /// Dismiss error badge
  void dismissError() {
    state = state.copyWith(status: AppUpdateStatus.idle, errorMessage: null);
  }
}

final appUpdateProvider = StateNotifierProvider<AppUpdateNotifier, AppUpdateState>((ref) {
  return AppUpdateNotifier();
});
