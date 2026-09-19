import 'package:flutter_test/flutter_test.dart';
import 'package:memento_mobile/core/services/update_service.dart';

void main() {
  group('UpdateService Version Comparison Tests', () {
    test('isNewerVersion correctly compares semver', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.99.99'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.2', '1.0.1'), isTrue);
    });

    test('isNewerVersion handles different lengths', () {
      expect(UpdateService.isNewerVersion('1.0.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('1.1', '1.0.5'), isTrue);
    });

    test('checkUpdate live query picks up newly published release', () async {
      final info = await UpdateService.checkUpdate(customServerUrl: 'https://mem.ihasy.com');
      expect(info, isNotNull);
      expect(info!.version, isNotEmpty);
      expect(info.downloadUrl, isNotNull);
    });

    test('getUpdateCacheDir returns non-empty valid directory', () {
      final dir = UpdateService.getUpdateCacheDir('1.0.19');
      expect(dir.existsSync(), isTrue);
      expect(dir.path, contains('memento_updates'));
      expect(dir.path, contains('1.0.19'));
    });

    test('getUpdateFileName resolves from assetName or downloadUrl', () {
      final infoWithAsset = UpdateInfo(
        version: '1.0.19',
        currentVersion: '1.0.18',
        hasUpdate: true,
        title: 'Update',
        releaseNotes: '',
        assetName: 'memento-macos-arm64.zip',
        htmlUrl: 'https://github.com/ddong8/memento',
      );
      expect(UpdateService.getUpdateFileName(infoWithAsset), equals('memento-macos-arm64.zip'));

      final infoWithUrl = UpdateInfo(
        version: '1.0.19',
        currentVersion: '1.0.18',
        hasUpdate: true,
        title: 'Update',
        releaseNotes: '',
        downloadUrl: 'https://example.com/downloads/memento-windows-x64-setup.exe',
        htmlUrl: 'https://github.com/ddong8/memento',
      );
      expect(UpdateService.getUpdateFileName(infoWithUrl), equals('memento-windows-x64-setup.exe'));
    });
  });
}
