import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';

/// معلومات تحديث متاح من GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes = '',
    this.forceUpdate = false,
  });

  /// رقم النسخة الأحدث، مثال: `1.0.2` (بلا بادئة `v` وبلا `+build`).
  final String latestVersion;

  /// رابط التحميل: APK المباشر من الـ Release، أو صفحة الـ Release.
  final String downloadUrl;

  /// ملاحظات الإصدار (حقل `body` في GitHub).
  final String releaseNotes;

  /// تحديث إجباري (من `version.json` فقط حالياً).
  final bool forceUpdate;

  @override
  String toString() =>
      'UpdateInfo(latestVersion: $latestVersion, '
      'downloadUrl: $downloadUrl, forceUpdate: $forceUpdate)';
}

/// فحص تحديثات التطبيق من GitHub Releases وفتح رابط التحميل.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client;

  // -- ⚙️ مستودع GitHub الرسمي للتحديثات --
  static const String githubOwner = 'jtnnazzal24-lab';
  static const String githubRepo = 'alk-app';

  static bool get isConfigured =>
      githubOwner != 'YOUR-ACCOUNT' && githubRepo != 'YOUR-REPO';

  static String get latestReleaseApiUrl =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  static String get releasesPageUrl =>
      'https://github.com/$githubOwner/$githubRepo/releases/latest';

  final http.Client? _client;
  static const _skippedKey = 'alk.update.skipped-version';

  static const _allowedHosts = <String>{
    'github.com',
    'objects.githubusercontent.com',
    'codeload.github.com',
    'release-assets.githubusercontent.com',
    'alk-app.web.app',
    'firebasestorage.googleapis.com',
  };

  static String normalizeVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    return v.trim();
  }

  static int compareVersions(String a, String b) {
    final pa = normalizeVersion(a).split('.');
    final pb = normalizeVersion(b).split('.');
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final na = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final nb = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (na != nb) return na < nb ? -1 : 1;
    }
    return 0;
  }

  static bool isNewer(String current, String latest) =>
      compareVersions(current, latest) < 0;

  /// يعرض حوار التحديث (يتوفر تحديث جديد / أنت على أحدث إصدار).
  ///
  /// [checkFuture] تُحقن في الاختبارات لتفادي الشبكة.
  /// يرجع `true` عندما فُتح رابط التحميل بنجاح.
  static Future<bool> showUpdateDialog(
    BuildContext context, {
    Future<UpdateInfo?>? checkFuture,
    UpdateService? service,
  }) async {
    final svc = service ?? UpdateService();
    UpdateInfo? info;
    try {
      info = await (checkFuture ?? svc.checkForUpdate());
    } catch (_) {
      info = null;
    }
    if (!context.mounted) return false;
    if (info == null) {
      if (!UpdateService.isConfigured) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أنت على أحدث إصدار'.tr)),
      );
      return false;
    }
    final skipped = await svc.isSkipped(info.latestVersion);
    if (!context.mounted) return false;
    if (skipped && !info.forceUpdate) return false;

    final chosen = await showDialog<String>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (dialogContext) => AlertDialog(
        title: Text('يتوفر تحديث جديد'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${'الإصدار الجديد:'.tr} ${info!.latestVersion}'),
            if (info.releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                info.releaseNotes.trim().split('\n').take(6).join('\n'),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        actions: [
          if (!info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('skip'),
              child: Text('تخطي هذا الإصدار'.tr),
            ),
          if (!info.forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('later'),
              child: Text('لاحقًا'.tr),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('now'),
            child: Text('تحديث الآن'.tr),
          ),
        ],
      ),
    );
    if (!context.mounted) return false;
    if (chosen == 'skip') {
      await svc.setSkipped(info.latestVersion);
      return false;
    }
    if (chosen != 'now') return false;
    final ok = await svc.openDownload(info);
    if (!context.mounted) return ok;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح رابط التحميل'.tr)),
      );
    }
    return ok;
  }


  static UpdateInfo? parseGithubRelease(Map<String, dynamic> json) {
    final rawTag =
        (json['tag_name'] as String?) ?? (json['name'] as String?) ?? '';
    final version = normalizeVersion(rawTag);
    if (version.isEmpty) return null;
    String url = '';
    final assets = json['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final item in assets) {
        if (item is! Map<String, dynamic>) continue;
        final name = (item['name'] as String? ?? '').toLowerCase();
        final dl = item['browser_download_url'] as String? ?? '';
        if (name.endsWith('.apk') && dl.isNotEmpty) {
          url = dl;
          break;
        }
      }
    }
    if (url.isEmpty) url = (json['html_url'] as String? ?? releasesPageUrl);
    if (url.isEmpty) return null;
    return UpdateInfo(
      latestVersion: version,
      downloadUrl: url,
      releaseNotes: (json['body'] as String?) ?? '',
    );
  }

  static UpdateInfo? parseVersionJson(Map<String, dynamic> json) {
    final v = normalizeVersion(json['latestVersion'] as String? ?? '');
    final url = (json['downloadUrl'] as String? ?? '').trim();
    if (v.isEmpty || url.isEmpty) return null;
    return UpdateInfo(
      latestVersion: v,
      downloadUrl: url,
      releaseNotes: (json['releaseNotes'] as String? ?? '').trim(),
      forceUpdate: json['forceUpdate'] == true,
    );
  }

  static bool isAllowedUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;
    return _allowedHosts.contains(uri.host.toLowerCase());
  }

  Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return normalizeVersion(info.version);
    } catch (_) {
      return '1.0.0';
    }
  }

  Future<UpdateInfo?> checkForUpdate({String? currentVersionOverride}) async {
    if (!isConfigured) return null;
    final client = _client ?? http.Client();
    final shouldClose = _client == null;
    try {
      final current = currentVersionOverride ?? await currentVersion();
      final res = await client
          .get(
            Uri.parse(latestReleaseApiUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final info = parseGithubRelease(decoded);
      if (info == null) return null;
      if (!isNewer(normalizeVersion(current), info.latestVersion)) return null;
      if (!isAllowedUrl(info.downloadUrl)) return null;
      return info;
    } catch (_) {
      return null;
    } finally {
      if (shouldClose) client.close();
    }
  }

  Future<bool> isSkipped(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_skippedKey) == normalizeVersion(version);
    } catch (_) {
      return false;
    }
  }

  Future<void> setSkipped(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_skippedKey, normalizeVersion(version));
    } catch (_) {}
  }

  Future<void> clearSkipped() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_skippedKey);
    } catch (_) {}
  }

  Future<bool> openDownload(UpdateInfo info) async {
    if (!isAllowedUrl(info.downloadUrl)) return false;
    try {
      final uri = Uri.parse(info.downloadUrl.trim());
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}



