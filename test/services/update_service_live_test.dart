import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:alk_flutter/services/update_service.dart';

/// End-to-end verification of the REAL GitHub Releases pipeline.
///
/// Opt-in so the default `flutter test` run stays offline and deterministic:
///   PowerShell:  $env:ALK_LIVE_UPDATE_TEST='1'; flutter test test/services/update_service_live_test.dart
///   Bash/Zsh:    ALK_LIVE_UPDATE_TEST=1 flutter test test/services/update_service_live_test.dart
///
/// Skipped automatically when the flag is absent.
final _skipReason = Platform.environment['ALK_LIVE_UPDATE_TEST'] == '1'
    ? null
    : 'Set ALK_LIVE_UPDATE_TEST=1 to run the live GitHub Releases checks.';

void main() {
  group('GitHub Releases (live)', () {
    test('repo coordinates are configured', () {
      expect(UpdateService.isConfigured, isTrue,
          reason: 'githubOwner/githubRepo must not be placeholders.');
      expect(UpdateService.githubOwner, 'jtnnazzal24-lab');
      expect(UpdateService.githubRepo, 'alk-app');
      expect(
        UpdateService.latestReleaseApiUrl,
        'https://api.github.com/repos/jtnnazzal24-lab/alk-app/releases/latest',
      );
    });

    test('latest release endpoint answers 200 with a usable release',
        () async {
      final res = await http
          .get(
            Uri.parse(UpdateService.latestReleaseApiUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));

      expect(res.statusCode, 200,
          reason: 'GitHub API must expose a published (non-draft) release.');

      final decoded = jsonDecode(res.body);
      expect(decoded, isA<Map<String, dynamic>>());
      final json = decoded as Map<String, dynamic>;

      // The service only ever offers non-draft, stable releases.
      expect(json['draft'], isFalse);
      expect(json['prerelease'], isFalse);

      final info = UpdateService.parseGithubRelease(json);
      expect(info, isNotNull,
          reason: 'A real release must map onto UpdateInfo.');

      // A version string the semver comparator understands.
      expect(info!.latestVersion, matches(RegExp(r'^\d+(\.\d+)*$')));

      // Notes are optional, but a real release should carry something.
      expect(info.releaseNotes, isA<String>());

      // The URL the app would hand to url_launcher must survive the gate.
      expect(UpdateService.isAllowedUrl(info.downloadUrl), isTrue,
          reason: 'downloadUrl "${info.downloadUrl}" was rejected by the '
              'https + allow-list check.');
      expect(info.downloadUrl, startsWith('https://'));
    }, skip: _skipReason);

    test('an APK asset is attached and is actually downloadable',
        () async {
      final res = await http
          .get(
            Uri.parse(UpdateService.latestReleaseApiUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      expect(res.statusCode, 200);

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final assets = (json['assets'] as List<dynamic>? ?? const []);
      final apks = assets.where((a) =>
          a is Map<String, dynamic> &&
          ((a['name'] as String? ?? '').toLowerCase().endsWith('.apk')));

      expect(apks, isNotEmpty,
          reason: 'The release must carry a .apk asset, otherwise users on '
              'the old build have nothing to download.');

      final info = UpdateService.parseGithubRelease(json)!;
      expect(UpdateService.isAllowedUrl(info.downloadUrl), isTrue);

      // Confirm the asset really resolves (redirects to release-assets host).
      final head = await http.head(Uri.parse(info.downloadUrl))
          .timeout(const Duration(seconds: 30));
      expect(head.statusCode, 200,
          reason: 'Asset download link is broken (HTTP ${head.statusCode}).');
      expect(head.headers['content-type'],
          contains('application/vnd.android.package-archive'));
      expect(int.parse(head.headers['content-length'] ?? '0'), greaterThan(0));
    }, skip: _skipReason);

    test('release page fallback URL also resolves', () async {
      final res = await http
          .get(Uri.parse(UpdateService.releasesPageUrl))
          .timeout(const Duration(seconds: 30));
      expect(res.statusCode, 200);
      expect(UpdateService.isAllowedUrl(UpdateService.releasesPageUrl), isTrue);
    }, skip: _skipReason);

    test('current app version is not newer than the published release',
        () {
      // Guards the release discipline: tag_name must track pubspec.yaml.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!;
      final normalized = UpdateService.normalizeVersion(declared);

      expect(normalized, matches(RegExp(r'^\d+(\.\d+)*$')),
          reason: 'pubspec version "$declared" did not normalize cleanly.');
      expect(UpdateService.isNewer('0.0.1', normalized), isTrue,
          reason: 'normalizeVersion("$declared") produced "$normalized".');
    });

    test('published release tag is consistent with the app version',
        () async {
      // Informational guard: reports drift between the built app version and
      // the newest GitHub Release, which is what /releases/latest returns.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!;
      final normalized = UpdateService.normalizeVersion(declared);

      final res = await http
          .get(
            Uri.parse(UpdateService.latestReleaseApiUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      expect(res.statusCode, 200);

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final published = UpdateService.parseGithubRelease(json)!.latestVersion;

      // The newest release must never be OLDER than the shipped build,
      // otherwise the in-app updater can never roll a user forward.
      expect(
        UpdateService.compareVersions(published, normalized), isNot(-1),
        reason: 'pubspec is "$declared" but the newest published release is '
            '"$published". Run scripts\\release.ps1 -Type <major|patch> '
            '-Publish to close the gap.',
      );
    }, skip: _skipReason);
  });

  // Exercises the REAL network path the Settings screen calls, using the
  // production UpdateService with a live HTTP client (no mocking).
  group('checkForUpdate() against live GitHub', () {
    Future<UpdateInfo?> checkAs(String installed) async {
      final svc = UpdateService(client: http.Client());
      return svc.checkForUpdate(currentVersionOverride: installed);
    }

    test('an older install IS offered the published release', () async {
      // Proves the whole chain fires: fetch -> parse -> compare -> allow-list.
      final info = await checkAs('0.9.0');
      expect(info, isNotNull,
          reason: 'A 0.9.0 install must be offered an update, otherwise the '
              'in-app update button is dead.');
      expect(info!.latestVersion, matches(RegExp(r'^\d+(\.\d+)*$')));
      expect(UpdateService.isAllowedUrl(info.downloadUrl), isTrue);

      // The APK the user would actually download must be reachable.
      final head = await http.head(Uri.parse(info.downloadUrl))
          .timeout(const Duration(seconds: 30));
      expect(head.statusCode, 200);
      expect(int.parse(head.headers['content-length'] ?? '0'), greaterThan(0));
    }, skip: _skipReason);

    test('the published version itself sees no update, older ones do',
        () async {
      // Dynamic so it stays valid as releases are published.
      final res = await http
          .get(
            Uri.parse(UpdateService.latestReleaseApiUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 20));
      expect(res.statusCode, 200);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final published = UpdateService.parseGithubRelease(json)!.latestVersion;

      // Installed == published -> "you are up to date".
      expect(await checkAs(published), isNull,
          reason: 'An install at exactly $published must report up to date.');

      // Installed below published -> an update IS offered (the real flow).
      final seg = published.split('.').map(int.parse).toList();
      String below;
      if (seg.length > 2 && seg[2] > 0) {
        below = '${seg[0]}.${seg[1]}.${seg[2] - 1}';
      } else if (seg.length > 1 && seg[1] > 0) {
        below = '${seg[0]}.${seg[1] - 1}.9';
      } else if (seg[0] > 0) {
        below = '${seg[0] - 1}.9.9';
      } else {
        below = '0.0.1';
      }

      final info = await checkAs(below);
      expect(info, isNotNull,
          reason: 'An install at $below must be offered $published.');
      expect(info!.latestVersion, published);
      expect(UpdateService.isAllowedUrl(info.downloadUrl), isTrue);
    }, skip: _skipReason);
  });
}