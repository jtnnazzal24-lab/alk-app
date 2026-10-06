import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Export/import of the full dataset as JSON — the exact same interchange
/// format (`alk-backup-*.json`) as the RN build.
class BackupService {
  const BackupService();

  /// Shares a JSON backup via the system share sheet and returns the file
  /// path that was written (null on failure).
  ///
  /// The copy is written to the app's private cache directory and every
  /// previous backup file is deleted first, so full copies of the patient's
  /// health data never pile up on the device after sharing.
  Future<String?> exportBackup(String json) async {
    try {
      final dir = await _backupDirectory();
      await _removePreviousBackups(dir);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final path = '${dir.path}/alk-backup-$stamp.json';
      final file = File(path);
      await file.writeAsString(json, flush: true);
      await Share.shareXFiles(
        [XFile(path)],
        subject: 'ALK backup',
        text: 'ALK data backup (JSON)',
      );
      return path;
    } catch (_) {
      return null;
    }
  }

  /// App-private cache directory (falls back to the OS temp dir on hosts
  /// without path_provider).
  Future<Directory> _backupDirectory() async {
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  /// يحذف نسخاً سابقة (`alk-backup-*.json`) فلا تتراكم بيانات المريض على الجهاز.
  Future<void> _removePreviousBackups(Directory dir) async {
    try {
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('alk-backup-') && name.endsWith('.json')) {
          try {
            await entity.delete();
          } catch (_) {
            // حذف قديم أفضل جهد.
          }
        }
      }
    } catch (_) {
      // لا يُسقط التنظيف عملية التصدير.
    }
  }

  /// Opens a JSON backup file chosen by the user and returns its raw text.
  Future<String?> pickAndReadBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      final file = result?.files.single;
      if (file == null) return null;
      if (file.bytes != null) {
        return utf8.decode(file.bytes!, allowMalformed: true);
      }
      final path = file.path;
      if (path != null && File(path).existsSync()) {
        return await File(path).readAsString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
