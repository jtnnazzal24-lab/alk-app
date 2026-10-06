import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alk_flutter/services/update_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UpdateService versions', () {
    test('normalizeVersion strips v prefix and +build suffix', () {
      expect(UpdateService.normalizeVersion('v1.0.2+3'), '1.0.2');
      expect(UpdateService.normalizeVersion('  V2.1  '), '2.1');
      expect(UpdateService.normalizeVersion('1.0.0+1'), '1.0.0');
    });

    test('compareVersions orders semantically', () {
      expect(UpdateService.compareVersions('1.0.0', '1.0.2'), -1);
      expect(UpdateService.compareVersions('1.0.2', '1.0.2'), 0);
      expect(UpdateService.compareVersions('1.0.10', '1.0.2'), 1);
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('v1.0.0+1', '1.0.1'), -1);
    });

    test('isNewer detects a newer release only', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.2'), isTrue);
      expect(UpdateService.isNewer('1.0.2', '1.0.2'), isFalse);
      expect(UpdateService.isNewer('1.0.3', '1.0.2'), isFalse);
    });
  });

  group('UpdateService parsing', () {
    test('parseGithubRelease prefers the attached APK', () {
      final info = UpdateService.parseGithubRelease({
        'tag_name': 'v1.0.2',
        'html_url': 'https://github.com/o/r/releases/tag/v1.0.2',
        'body': 'notes',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url':
                'https://github.com/o/r/releases/download/v1.0.2/app.apk',
          },
          {
            'name': 'checksums.txt',
            'browser_download_url': 'https://github.com/o/r/x.txt',
          },
        ],
      });
      expect(info, isNotNull);
      expect(info!.latestVersion, '1.0.2');
      expect(info.downloadUrl, endsWith('app.apk'));
      expect(info.releaseNotes, 'notes');
    });

    test('parseGithubRelease falls back to the release page', () {
      final info = UpdateService.parseGithubRelease({
        'tag_name': 'v1.0.3',
        'html_url': 'https://github.com/o/r/releases/tag/v1.0.3',
        'assets': <dynamic>[],
      });
      expect(info, isNotNull);
      expect(info!.downloadUrl, contains('github.com'));
    });

    test('parseGithubRelease rejects a missing tag', () {
      expect(UpdateService.parseGithubRelease({}), isNull);
    });

    test('parseVersionJson reads the hosted version.json shape', () {
      final info = UpdateService.parseVersionJson({
        'latestVersion': '1.0.2',
        'downloadUrl': 'https://github.com/o/r/releases/download/x.apk',
        'releaseNotes': 'fix',
        'forceUpdate': true,
      });
      expect(info, isNotNull);
      expect(info!.forceUpdate, isTrue);
      expect(info.releaseNotes, 'fix');
    });

    test('parseVersionJson rejects empty fields', () {
      expect(UpdateService.parseVersionJson({}), isNull);
      expect(
        UpdateService.parseVersionJson(
            {'latestVersion': '1.0.2', 'downloadUrl': ''}),
        isNull,
      );
    });
  });

  group('UpdateService URL allow-list', () {
    test('accepts GitHub https links', () {
      expect(
        UpdateService.isAllowedUrl(
            'https://github.com/o/r/releases/download/v1.0.2/app.apk'),
        isTrue,
      );
      expect(
        UpdateService.isAllowedUrl(
            'https://release-assets.githubusercontent.com/x/app.apk'),
        isTrue,
      );
    });

    test('rejects http and foreign hosts', () {
      expect(
        UpdateService.isAllowedUrl('http://github.com/o/r/app.apk'),
        isFalse,
      );
      expect(
        UpdateService.isAllowedUrl('https://evil.example.com/app.apk'),
        isFalse,
      );
      expect(UpdateService.isAllowedUrl('not a url'), isFalse);
    });
  });

  group('UpdateService skip-version', () {
    test('round-trips the skipped version', () async {
      final svc = UpdateService();
      expect(await svc.isSkipped('1.0.2'), isFalse);
      await svc.setSkipped('v1.0.2+9');
      expect(await svc.isSkipped('1.0.2'), isTrue);
      await svc.clearSkipped();
      expect(await svc.isSkipped('1.0.2'), isFalse);
    });
  });
}
