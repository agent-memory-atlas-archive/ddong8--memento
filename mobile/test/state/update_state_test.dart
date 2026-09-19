import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/core/services/update_service.dart';
import 'package:memento_mobile/state/update_state.dart';

void main() {
  group('AppUpdateState & AppUpdateNotifier Tests', () {
    test('Initial AppUpdateState has default idle values', () {
      const state = AppUpdateState();
      expect(state.status, equals(AppUpdateStatus.idle));
      expect(state.isDownloading, isFalse);
      expect(state.isReadyToInstall, isFalse);
      expect(state.isInstalling, isFalse);
      expect(state.isChecking, isFalse);
      expect(state.hasUpdate, isFalse);
      expect(state.progress, equals(0.0));
      expect(state.downloadedPath, isNull);
    });

    test('AppUpdateState status getters reflect state changes', () {
      final updateInfo = UpdateInfo(
        version: '1.0.21',
        currentVersion: '1.0.20',
        hasUpdate: true,
        title: 'New version',
        releaseNotes: 'Bug fixes',
        htmlUrl: 'https://github.com/ddong8/memento',
      );

      final downloadingState = const AppUpdateState().copyWith(
        status: AppUpdateStatus.downloading,
        info: updateInfo,
        progress: 0.5,
        sourceLabel: 'GitHub 官方源',
      );
      expect(downloadingState.isDownloading, isTrue);
      expect(downloadingState.isReadyToInstall, isFalse);
      expect(downloadingState.hasUpdate, isTrue);
      expect(downloadingState.progress, equals(0.5));
      expect(downloadingState.sourceLabel, equals('GitHub 官方源'));

      final readyState = downloadingState.copyWith(
        status: AppUpdateStatus.readyToInstall,
        downloadedPath: '/tmp/test_update.zip',
        progress: 1.0,
      );
      expect(readyState.isDownloading, isFalse);
      expect(readyState.isReadyToInstall, isTrue);
      expect(readyState.downloadedPath, equals('/tmp/test_update.zip'));

      final installingState = readyState.copyWith(
        status: AppUpdateStatus.installing,
      );
      expect(installingState.isInstalling, isTrue);
      expect(installingState.isReadyToInstall, isFalse);
    });

    test('Notifier dismissError resets status to idle and clears error', () {
      final notifier = AppUpdateNotifier();
      // Initially idle
      expect(notifier.state.status, equals(AppUpdateStatus.idle));

      // Dismiss error
      notifier.dismissError();
      expect(notifier.state.status, equals(AppUpdateStatus.idle));
      expect(notifier.state.errorMessage, isNull);
      notifier.dispose();
    });

    test('AppUpdateState retains info and hasUpdate even in error status', () {
      final info = UpdateInfo(
        version: '1.0.27',
        currentVersion: '1.0.26',
        hasUpdate: true,
        title: 'v1.0.27',
        releaseNotes: 'Fixes',
        htmlUrl: 'https://github.com/ddong8/memento',
      );
      final errorState = const AppUpdateState().copyWith(
        status: AppUpdateStatus.error,
        info: info,
        errorMessage: '下载失败',
      );
      expect(errorState.hasUpdate, isTrue);
      expect(errorState.info?.version, equals('1.0.27'));
      expect(errorState.status, equals(AppUpdateStatus.error));
    });
  });
}
