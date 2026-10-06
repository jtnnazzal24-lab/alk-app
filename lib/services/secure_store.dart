import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// واجهة موحّدة للتخزين الآمن (Android Keystore / iOS Keychain).
///
/// تُستخدم لمفتاح DeepSeek ولمفتاح تشفير ملف بيانات المريض. عند غياب
/// التخزين الآمن — بيئة اختبارات الوحدة، منصّة لا تدعمه، أو فشل في الـ
/// Keystore — تُعيد الدوال `null`/`false` بدل أن ترمي استثناءً، فيتحوّل
/// المتصل إلى السلوك البديل (بلا تشفير مثلاً) ولا تتوقف وظائف التطبيق.
class SecureStore {
  SecureStore._();

  static final SecureStore instance = SecureStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const _probeKey = 'alk.secure-store.probe';

  /// تُضبط في الاختبارات (قناة المنصّة غير متوفرة) لتفادي أي انتظار.
  static bool forceUnavailable = false;

  /// خلفية في الذاكرة للاختبارات: تحلّ محلّ قنوات Keystore/Keychain.
  @visibleForTesting
  static Map<String, String>? debugMemory;

  bool? _available;

  /// هل التخزين الآمن متاح فعلاً على هذا الجهاز؟
  Future<bool> get available async {
    if (forceUnavailable) return false;
    if (debugMemory != null) return true;
    final cached = _available;
    if (cached != null) return cached;
    var value = false;
    try {
      await _storage.read(key: _probeKey);
      value = true;
    } catch (_) {
      value = false;
    }
    _available = value;
    return value;
  }

  Future<String?> read(String key) async {
    final memory = debugMemory;
    if (memory != null) return memory[key];
    if (!await available) return null;
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<bool> write(String key, String value) async {
    final memory = debugMemory;
    if (memory != null) {
      memory[key] = value;
      return true;
    }
    if (!await available) return false;
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> delete(String key) async {
    final memory = debugMemory;
    if (memory != null) {
      memory.remove(key);
      return;
    }
    if (!await available) return;
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // الحذف أفضل جهد — لا يُسقط أي عملية.
    }
  }

  /// اختبارات الوحدة: إعادة قراءة توفّر التخزين الآمن.
  @visibleForTesting
  void resetAvailabilityForTesting() {
    _available = null;
  }
}
