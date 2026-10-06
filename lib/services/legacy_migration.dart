import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/sandy_data.dart';

/// Result summary of a legacy-data migration attempt.
class LegacyMigrationResult {
  final bool performed;
  final String source; // 'legacy-rn-database' | 'json-backup' | 'none'
  final int medications;
  final int vitals;
  final int journals;
  final int attachments;
  final int doseEvents;
  final String message;

  const LegacyMigrationResult({
    required this.performed,
    required this.source,
    required this.medications,
    required this.vitals,
    required this.journals,
    required this.attachments,
    required this.doseEvents,
    required this.message,
  });

  bool get isEmpty =>
      medications == 0 &&
      vitals == 0 &&
      journals == 0 &&
      attachments == 0 &&
      doseEvents == 0;
}

/// Migrates data from the legacy React Native build.
///
/// The RN app persisted its whole dataset as a JSON string under the
/// AsyncStorage key `sandy-health-local-v1`, which on Android lives in the
/// SQLite database `RKStorage` of the OLD application id
/// (`com.app.fixedflutterapp`). When this Flutter build is installed with the
/// SAME application id as an upgrade, that database is still readable, so we
/// copy the JSON blob across — no data loss.
class LegacyMigrationService {
  static const rnStorageKey = 'sandy-health-local-v1';
  static const _rnDatabaseName = 'RKStorage';

  /// True when the legacy RN database exists and contains the dataset.
  Future<bool> legacyDataExists() async {
    try {
      final raw = await _readLegacyJson();
      return raw != null;
    } catch (_) {
      return false;
    }
  }

  /// Reads the legacy JSON blob from RKStorage, or null when unavailable.
  Future<String?> _readLegacyJson() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, _rnDatabaseName);
    if (!File(dbPath).existsSync()) return null;
    final db = await openDatabase(dbPath, readOnly: true);
    try {
      final rows = await db.query(
        'catalystLocalStorage',
        where: 'key = ?',
        whereArgs: [rnStorageKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final value = rows.first['value'];
      if (value is String && value.isNotEmpty) return value;
      return null;
    } finally {
      await db.close();
    }
  }

  /// Loads the legacy dataset from the RN database (tolerant parse).
  Future<SandyData?> loadLegacyData() async {
    try {
      final raw = await _readLegacyJson();
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SandyData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Full auto-migration: loads the RN dataset and returns the parsed result.
  /// (The caller decides whether to merge over current data and persist.)
  Future<LegacyMigrationResult?> migrateIfAvailable() async {
    final data = await loadLegacyData();
    if (data == null) return null;
    return LegacyMigrationResult(
      performed: true,
      source: 'legacy-rn-database',
      medications: data.medications.length,
      vitals: data.vitals.length,
      journals: data.journals.length,
      attachments: data.medicalAttachments.length,
      doseEvents: data.missedDoseEvents.length,
      message: 'legacy data found',
    );
  }
}
