import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../services/secure_store.dart';

/// تشفير ملف بيانات المريض على الجهاز (AES-256-GCM).
///
/// المفتاح عشوائي 32 بايت يُولَّد مرة واحدة ويُحفظ في التخزين الآمن
/// (Android Keystore / iOS Keychain) — لا يُكتب في أي ملف عادي.
///
/// قواعد الأمان (مهمّة لبيانات طبية):
///  * عند غياب التخزين الآمن أو فشل المفتاح: **لا تشفير** ويُكتب الملف كما
///    كان (نص JSON) — لا نخاطر بضياع بيانات المريض أبداً.
///  * أي ملف مشفّر لا يمكن فكّه (مفتاح مفقود/تلف) يُعيد `null` صراحةً
///    فيتوقف الحفظ التلقائي (انظر `SandyRepository.lastLoadFailed`) ولا
///    يُستبدل الملف الموجود على الجهاز.
///  * الصيغة: `ALKENC1:` + base64(nonce ‖ ciphertext ‖ MAC).
class DataCipher {
  DataCipher._();

  static final DataCipher instance = DataCipher._();

  /// بادئة تميّز الملف المشفَّر عن ملف JSON القديم (ترحيل شفاف).
  static const header = 'ALKENC1:';

  static const _keyStorageKey = 'alk.data-encryption-key';

  /// طول الـ nonce ووسم التحقق في AES-GCM.
  static const _nonceLength = 12;
  static const _macLength = 16;

  /// تُضبط في الاختبارات لتعطيل التشفير كلياً (بلا قنوات منصّة).
  static bool forceDisabled = false;

  final AesGcm _algorithm = AesGcm.with256bits();

  SecretKey? _key;
  bool _resolved = false;

  /// هل التشفير مفعّل فعلاً على هذا الجهاز؟
  bool get enabled => _key != null;

  static bool isEncrypted(String raw) => raw.startsWith(header);

  /// يجلب مفتاح التشفير من التخزين الآمن، ويولّده أول مرة.
  Future<void> _resolveKey() async {
    if (_resolved) return;
    _resolved = true;
    if (forceDisabled) return;
    try {
      final store = SecureStore.instance;
      if (!await store.available) return;
      final stored = await store.read(_keyStorageKey);
      if (stored != null && stored.isNotEmpty) {
        final bytes = base64Decode(stored);
        if (bytes.length == 32) {
          _key = SecretKey(bytes);
          return;
        }
      }
      final fresh = await _algorithm.newSecretKey();
      final bytes = await fresh.extractBytes();
      if (await store.write(_keyStorageKey, base64Encode(bytes))) {
        _key = SecretKey(bytes);
      }
    } catch (_) {
      // أي فشل ⇒ بلا تشفير، والبيانات تبقى قابلة للقراءة.
      _key = null;
    }
  }

  /// يشفّر نصاً. يعيد النص كما هو عندما يكون التشفير غير متاح.
  Future<String> encrypt(String plain) async {
    await _resolveKey();
    final key = _key;
    if (key == null) return plain;
    try {
      final box = await _algorithm.encrypt(
        utf8.encode(plain),
        secretKey: key,
      );
      return '$header${base64Encode(box.concatenation())}';
    } catch (_) {
      return plain;
    }
  }

  /// يفكّ التشفير عند وجود البادئة، وإلا يعيد النص كما هو.
  ///
  /// يعيد `null` فقط إذا كان الملف مشفَّراً ولا يمكن فكّه (مفتاح مفقود أو
  /// تلف) — والمتصل يمنع عندها الكتابة فوق الملف.
  Future<String?> decrypt(String raw) async {
    if (!isEncrypted(raw)) return raw;
    await _resolveKey();
    final key = _key;
    if (key == null) return null;
    try {
      final bytes = base64Decode(raw.substring(header.length).trim());
      final box = SecretBox.fromConcatenation(
        bytes,
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final clear = await _algorithm.decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  /// اختبارات الوحدة: استخدام مفتاح معروف بلا تخزين آمن.
  @visibleForTesting
  Future<void> useKeyForTesting(List<int> keyBytes) async {
    _resolved = true;
    _key = SecretKey(keyBytes);
  }

  /// اختبارات الوحدة: إعادة الحالة لتعطيل التشفير.
  @visibleForTesting
  void resetForTesting() {
    _resolved = false;
    _key = null;
  }
}
