import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sandy_data.dart';
import 'data_cipher.dart';

/// Persistence for the ALK local dataset.
///
/// The dataset is stored as a dedicated JSON file inside the app's private
/// documents directory (a real, separate area of the phone's memory), rather
/// than a tiny SharedPreferences value. The file uses the SAME JSON schema as
/// the React Native app (`sandy-health-local-v1`) so backups stay
/// interchangeable and migration is lossless. Any data previously kept in
/// SharedPreferences is migrated to the file automatically on first load.
class SandyRepository {
  /// The historical SharedPreferences key — still read once during the
  /// StoragePrefs → file migration so existing users never lose data.
  static const mainKey = 'sandy-health-local-v1';
  static const voicePrefsKey = 'alk.voice-preferences.v1';
  static const localeOverrideKey = 'alk.locale-override';
  static const migrationDoneKey = 'alk.legacy-migration.done-v1';

  static const medicationImagesDirName = 'alk-medication-images';
  static const medicalAttachmentsDirName = 'alk-medical-attachments';

  /// The dedicated directory/file that holds the dataset on the phone.
  static const dataDirName = 'alk-data';
  static const dataFileName = 'alk-data.json';

  /// When true, the repository always uses the SharedPreferences fallback and
  /// never touches the file system. Widget tests set this in setUpAll because
  /// the path_provider platform channel is unavailable in the test host and
  /// would otherwise hang the test on first launch.
  static bool forcePrefsMode = false;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // File-system availability is resolved once: when the app's documents
  // directory cannot be reached (some test hosts / restricted environments),
  // storage transparently falls back to SharedPreferences so nothing breaks.
  bool _fileModeResolved = false;
  bool _fileMode = true;

  /// يصبح true عندما يوجد ملف بيانات **مشفَّر** لا يمكن فكّه (مفتاح مفقود أو
  /// تلف). عندها يتوقف الحفظ التلقائي حتى لا يُستبدل ملف المريض ببيانات فارغة
  /// — والشفاء يكون باستيراد نسخة احتياطية أو «حذف كل البيانات».
  bool _lastLoadFailed = false;

  /// هل فشل آخر تحميل (ملف مشفَّر غير قابل للفك)؟
  bool get lastLoadFailed => _lastLoadFailed;

  Future<bool> _fileStorageAvailable() async {
    if (forcePrefsMode) {
      _fileModeResolved = true;
      _fileMode = false;
      return false;
    }
    if (_fileModeResolved) return _fileMode;
    try {
      await getApplicationDocumentsDirectory();
      _fileMode = true;
    } catch (_) {
      _fileMode = false;
    }
    _fileModeResolved = true;
    return _fileMode;
  }

  /// Public flag helpers (used by the legacy migration bookkeeping).
  Future<bool> getFlag(String key) async {
    final prefs = await _prefs;
    return prefs.getBool(key) ?? false;
  }

  Future<void> setFlag(String key, bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(key, value);
  }

  Future<Directory> _ensureDirectory(String name) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$name');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// The dedicated JSON file holding the whole dataset.
  Future<File> _dataFile() async {
    final dir = await _ensureDirectory(dataDirName);
    return File('${dir.path}/$dataFileName');
  }

  /// Test-only accessor to verify the dedicated file's state on disk.
  /// Returns null when the file system is unavailable (unit-test hosts).
  @visibleForTesting
  Future<File?> debugDataFile() async {
    if (forcePrefsMode) {
      final file = File('${Directory.systemTemp.path}/$dataFileName');
      return file;
    }
    try {
      return await _dataFile();
    } catch (_) {
      return null;
    }
  }

  /// Reads the dataset from the dedicated file.
  ///
  /// The file may be encrypted (`ALKENC1:` — AES-256-GCM) or a legacy plaintext
  /// JSON; both are accepted, and a plaintext file is transparently re-written
  /// encrypted the first time a key is available (lossless migration).
  Future<SandyData?> _loadFromFile() async {
    final file = await _dataFile();
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      final plain = await DataCipher.instance.decrypt(raw);
      if (plain == null) {
        // ملف مشفّر بلا مفتاح: لا نلمس الملف ولا نسمح بالكتابة فوقه.
        _lastLoadFailed = true;
        debugPrint('ALK: data file cannot be decrypted (key unavailable)');
        return null;
      }
      final decoded = jsonDecode(plain);
      if (decoded is! Map<String, dynamic>) return null;
      final data = SandyData.fromJson(decoded);
      _lastLoadFailed = false;
      if (!DataCipher.isEncrypted(raw) && DataCipher.instance.enabled) {
        // ترحيل هادئ: يُشفَّر الملف من الآن فصاعداً.
        await save(data);
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  /// Reads any dataset still living in SharedPreferences (legacy placement).
  Future<SandyData?> _loadFromPrefs() async {
    final prefs = await _prefs;
    final raw = prefs.getString(mainKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final plain = await DataCipher.instance.decrypt(raw);
      if (plain == null) {
        _lastLoadFailed = true;
        return null;
      }
      final decoded = jsonDecode(plain);
      if (decoded is! Map<String, dynamic>) return null;
      return SandyData.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Loads the saved dataset, or [SandyData.initial] when nothing is stored.
  /// When the dedicated file is available it is read first; data found only
  /// in the old SharedPreferences location is adopted into the file
  /// (lossless migration). Falls back to prefs when the file system is
  /// unavailable.
  Future<SandyData?> load() async {
    final fileMode = await _fileStorageAvailable();
    if (fileMode) {
      try {
        final fromFile = await _loadFromFile();
        if (fromFile != null) return fromFile;

        final fromPrefs = await _loadFromPrefs();
        if (fromPrefs != null) {
          await save(fromPrefs);
          // Clear the old prefs copy so it is never read again as stale.
          final prefs = await _prefs;
          await prefs.remove(mainKey);
          return fromPrefs;
        }
        return null;
      } catch (_) {
        // Fall through to prefs below on any unexpected file error.
      }
    }
    return _loadFromPrefs();
  }

  Future<void> save(SandyData data) async {
    final json = jsonEncode(data.toJson());
    // حماية من فقدان البيانات: إذا كان الملف الموجود مشفَّراً ولا يمكن فكّه،
    // لا نكتب فوقه بيانات فارغة/جزئية إطلاقاً (انظر lastLoadFailed).
    if (_lastLoadFailed) {
      debugPrint('ALK: save skipped — existing data file is unreadable');
      return;
    }
    final fileMode = await _fileStorageAvailable();
    if (!fileMode) {
      final prefs = await _prefs;
      // نفس الحماية في المسار البديل: يُخزَّن المشفَّر (أو النص عند تعطّل
      // التشفير) في SharedPreferences بدل JSON صريح.
      await prefs.setString(mainKey, await DataCipher.instance.encrypt(json));
      return;
    }
    // عند غياب التخزين الآمن يبقى الملف نصاً كما كان (لا نخاطر ببيانات المريض).
    final payload = await DataCipher.instance.encrypt(json);
    try {
      final file = await _dataFile();
      // كتابة ذرّية: ملف مؤقت ثم استبدال — لا يبقى ملف نصف مكتوب إذا أُغلق
      // التطبيق أو نفدت البطارية في منتصف الحفظ.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // Storage must never crash a UI action; fall back to prefs.
      final prefs = await _prefs;
      await prefs.setString(mainKey, payload);
    }
  }

  Future<void> clear() async {
    _lastLoadFailed = false;
    final fileMode = await _fileStorageAvailable();
    if (fileMode) {
      try {
        final file = await _dataFile();
        if (file.existsSync()) await file.delete();
      } catch (_) {
        // Best effort.
      }
    }
    final prefs = await _prefs;
    await prefs.remove(mainKey);
  }

  /// Approximate size (bytes) currently used by the dedicated data file
  /// (or the prefs fallback when the file system is unavailable).
  Future<int> dataFileSizeBytes() async {
    final fileMode = await _fileStorageAvailable();
    if (!fileMode) {
      final prefs = await _prefs;
      final raw = prefs.getString(mainKey);
      return raw == null ? 0 : raw.length;
    }
    try {
      final file = await _dataFile();
      if (!file.existsSync()) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  // ---- Voice preferences (same key/schema as RN) --------------------------

  Future<Map<String, dynamic>?> loadVoicePreferencesRaw() async {
    final prefs = await _prefs;
    final raw = prefs.getString(voicePrefsKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveVoicePreferencesRaw(Map<String, dynamic> json) async {
    final prefs = await _prefs;
    await prefs.setString(voicePrefsKey, jsonEncode(json));
  }

  // ---- Locale override -----------------------------------------------------

  Future<String?> loadLocaleOverride() async {
    final prefs = await _prefs;
    return prefs.getString(localeOverrideKey);
  }

  Future<void> saveLocaleOverride(String? tag) async {
    final prefs = await _prefs;
    if (tag == null || tag.isEmpty) {
      await prefs.remove(localeOverrideKey);
    } else {
      await prefs.setString(localeOverrideKey, tag);
    }
  }

  // ---- Private file directories (ported from medication-image.ts /
  //      medical-attachment.ts) ---------------------------------------------

  Future<Directory> medicationImagesDirectory() =>
      _ensureDirectory(medicationImagesDirName);

  Future<Directory> medicalAttachmentsDirectory() =>
      _ensureDirectory(medicalAttachmentsDirName);

  String _extensionFromUri(String uri) {
    final match = RegExp(r'\.([a-zA-Z0-9]{2,5})(?:\?.*)?$').firstMatch(uri);
    return match?.group(1)?.toLowerCase() ?? 'jpg';
  }

  /// Copies a picked image into ALK's private on-device directory and
  /// returns the persisted URI (falls back to the original URI on failure).
  Future<String?> persistMedicationImage(String? uri) async {
    if (uri == null || uri.isEmpty) return uri;
    if (uri.contains(medicationImagesDirName)) return uri;
    try {
      final dir = await medicationImagesDirectory();
      final filename =
          'medicine-${DateTime.now().millisecondsSinceEpoch}-${_rand()}.${_extensionFromUri(uri)}';
      final destination = '${dir.path}/$filename';
      final source = File(uri);
      if (source.existsSync()) {
        await source.copy(destination);
        return destination;
      }
      return uri;
    } catch (_) {
      return uri;
    }
  }

  /// Copies a picked photo into ALK's private attachments directory.
  Future<String> persistMedicalAttachment(String uri) async {
    if (uri.contains(medicalAttachmentsDirName)) return uri;
    try {
      final dir = await medicalAttachmentsDirectory();
      final filename =
          'medical-${DateTime.now().millisecondsSinceEpoch}-${_rand()}.${_extensionFromUri(uri)}';
      final destination = '${dir.path}/$filename';
      final source = File(uri);
      if (source.existsSync()) {
        await source.copy(destination);
        return destination;
      }
      return uri;
    } catch (_) {
      return uri;
    }
  }

  Future<void> removeMedicationImage(String? uri) =>
      _removeIfManaged(uri, medicationImagesDirName);

  Future<void> removeMedicalAttachment(String? uri) =>
      _removeIfManaged(uri, medicalAttachmentsDirName);

  Future<void> _removeIfManaged(String? uri, String marker) async {
    if (uri == null || !uri.contains(marker)) return;
    try {
      final file = File(uri);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Best effort: cleanup must never block record deletion.
    }
  }

  String _rand() =>
      (DateTime.now().microsecondsSinceEpoch % 1679616)
          .toRadixString(36)
          .padLeft(4, '0');
}
