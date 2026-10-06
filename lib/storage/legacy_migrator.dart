import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/sandy_data.dart';
import 'sandy_repository.dart';

/// Result summary of the legacy migration, used for UI reporting.
class LegacyMigrationResult {
  final bool performed;
  final String source; // 'legacy-sqlite' | 'json-backup' | 'none'
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

  bool get hasContent =>
      medications + vitals + journals + attachments + doseEvents > 0;
}

/// One-time migration of data created by the React Native build of ALK.
///
/// The RN app persisted its whole dataset as a JSON string under the
/// AsyncStorage key `sandy-health-local-v1`, which on Android lives inside
/// the app's SQLite database `RKStorage` (table `catalystLocalStorage`,
/// created by react-native-sqlite-storage). Because the Flutter build keeps
/// the same applicationId, that database is still on the device when the
/// user installs this build as an upgrade, so we simply read it and adopt
/// the JSON blob as our initial state — nothing is lost.
class LegacyMigrator {
  LegacyMigrator(this._repository);

  final SandyRepository _repository;

  /// Runs the migration when needed. Safe to call on every startup:
  /// it is a no-op once completed or when no legacy data exists.
  Future<LegacyMigrationResult> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(SandyRepository.migrationDoneKey) == true) {
      return const LegacyMigrationResult(
        performed: false,
        source: 'none',
        medications: 0,
        vitals: 0,
        journals: 0,
        attachments: 0,
        doseEvents: 0,
        message: 'migration already completed previously',
      );
    }

    try {
      final json = await _readLegacyValue(SandyRepository.mainKey);
      if (json == null) {
        await _markDone(prefs);
        return const LegacyMigrationResult(
          performed: false,
          source: 'none',
          medications: 0,
          vitals: 0,
          journals: 0,
          attachments: 0,
          doseEvents: 0,
          message: 'no legacy data found',
        );
      }

      final legacy = SandyData.fromJson(json);
      final existing = await _repository.load();
      final merged = _merge(existing, legacy);
      await _repository.save(merged);

      // Adopt legacy voice preferences too (same key & schema).
      final legacyVoice =
          await _readLegacyValue(SandyRepository.voicePrefsKey);
      if (legacyVoice != null) {
        final current = await _repository.loadVoicePreferencesRaw();
        if (current == null) {
          await _repository.saveVoicePreferencesRaw(legacyVoice);
        }
      }

      await _markDone(prefs);
      return LegacyMigrationResult(
        performed: true,
        source: 'legacy-sqlite',
        medications: merged.medications.length,
        vitals: merged.vitals.length,
        journals: merged.journals.length,
        attachments: merged.medicalAttachments.length,
        doseEvents: merged.missedDoseEvents.length,
        message: 'legacy data imported successfully',
      );
    } catch (e) {
      // Never block startup; the user can still import a JSON backup.
      await _markDone(prefs);
      return LegacyMigrationResult(
        performed: false,
        source: 'none',
        medications: 0,
        vitals: 0,
        journals: 0,
        attachments: 0,
        doseEvents: 0,
        message: 'legacy migration skipped: $e',
      );
    }
  }

  /// Opens the legacy RN SQLite database (if present) and extracts the
  /// stored JSON value for [key] written by AsyncStorage.
  Future<Map<String, dynamic>?> _readLegacyValue(String key) async {
    final databasesPath = await getDatabasesPath();
    final candidates = [
      p.join(databasesPath, 'RKStorage'),
      p.join(databasesPath, 'RKStorage.db'),
    ];

    for (final path in candidates) {
      if (!File(path).existsSync()) continue;
      final db = await openDatabase(path, readOnly: true);
      try {
        final rows = await db.query(
          'catalystLocalStorage',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [key],
        );
        for (final row in rows) {
          final raw = row['value'];
          if (raw is! String || raw.isEmpty) continue;
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) return decoded;
        }
      } catch (_) {
        // Missing table or unreadable row — try the next candidate.
      } finally {
        await db.close();
      }
    }
    return null;
  }

  /// Merges legacy data over existing local data without ever discarding
  /// records: list fields are concatenated (legacy first, then existing) and
  /// scalar fields prefer whichever side carries actual content.
  SandyData _merge(SandyData? existing, SandyData legacy) {
    if (existing == null) return legacy;
    SandyData merged = SandyData.initial.copyWith(
      patient: _richer(existing.patient, legacy.patient),
      medications: [...legacy.medications, ...existing.medications],
      medicationHistory: [
        ...legacy.medicationHistory,
        ...existing.medicationHistory,
      ],
      missedDoseEvents: [
        ...legacy.missedDoseEvents,
        ...existing.missedDoseEvents,
      ],
      vitals: [...legacy.vitals, ...existing.vitals],
      journals: [...legacy.journals, ...existing.journals],
      medicalAttachments: [
        ...legacy.medicalAttachments,
        ...existing.medicalAttachments,
      ],
      foodEntries: [...legacy.foodEntries, ...existing.foodEntries],
      quietMode: legacy.quietMode || existing.quietMode,
      trustedContactUrl: existing.trustedContactUrl.isNotEmpty
          ? existing.trustedContactUrl
          : legacy.trustedContactUrl,
      trustedContactName: existing.trustedContactName.isNotEmpty
          ? existing.trustedContactName
          : legacy.trustedContactName,
      travelMode: legacy.travelMode || existing.travelMode,
      dataRetentionDays: legacy.dataRetentionDays,
      accessibility: existing.accessibility,
    );
    // De-duplicate by id (defensive; ids are unique in practice).
    final seenMeds = <String>{};
    merged = merged.copyWith(
      medications:
          merged.medications.where((m) => seenMeds.add(m.id)).toList(),
    );
    final seenVitals = <String>{};
    final deduped = merged.copyWith(
      vitals: merged.vitals.where((v) => seenVitals.add(v.id)).toList(),
    );
    final seenFood = <String>{};
    return deduped.copyWith(
      foodEntries:
          deduped.foodEntries.where((f) => seenFood.add(f.id)).toList(),
    );
  }

  /// Picks whichever patient profile carries more filled-in information.
  PatientProfile _richer(PatientProfile a, PatientProfile b) {
    final aScore = a.fullName.length + a.identityNumber.length;
    final bScore = b.fullName.length + b.identityNumber.length;
    return aScore >= bScore ? a : b;
  }

  Future<void> _markDone(SharedPreferences prefs) async {
    await prefs.setBool(SandyRepository.migrationDoneKey, true);
  }
}
