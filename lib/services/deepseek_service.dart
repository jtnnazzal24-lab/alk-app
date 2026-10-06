import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_store.dart';

/// Optional DeepSeek AI chat integration.
///
/// After the user signs up for a DeepSeek account (with their email) they
/// receive an API key from the DeepSeek platform; that key is stored locally
/// here and used to chat through the app via DeepSeek's OpenAI-compatible
/// chat-completions endpoint.
///
/// When no key is configured, or the network/request fails, the caller should
/// fall back to the local rule-based replies so the app never breaks.
class DeepSeekService {
  DeepSeekService._();

  static final DeepSeekService instance = DeepSeekService._();

  static const _apiKeyPrefsKey = 'alk.deepseek.api-key';

  /// مفتاح التخزين الآمن (Keystore/Keychain) — المكان الصحيح للسرّ.
  static const _apiKeySecureKey = 'alk.deepseek.api-key';
  static const _endpoint = 'https://api.deepseek.com/chat/completions';
  static const _model = 'deepseek-chat';

  /// تُضبط في الاختبارات (بلا قنوات منصّة) لاستخدام التخزين العادي فقط.
  static bool forcePrefsMode = false;

  String? _apiKey;
  bool _keyLoaded = false;

  /// Current API key (last 4 chars shown to the user), or null.
  String? get apiKey => _apiKey;
  bool get hasKey => (_apiKey ?? '').isNotEmpty;

  /// اختبارات الوحدة: إعادة حالة الذاكرة ليُعاد قراءة المفتاح من التخزين.
  @visibleForTesting
  void resetForTesting() {
    _apiKey = null;
    _keyLoaded = false;
  }

  /// A masked representation for display ("••••1234").
  String? get maskedKey {
    if (_apiKey == null || _apiKey!.isEmpty) return null;
    final tail = _apiKey!.length > 4
        ? _apiKey!.substring(_apiKey!.length - 4)
        : _apiKey!;
    return '••••$tail';
  }

  /// يحمّل المفتاح: من التخزين الآمن أولاً، ثم يهاجر مفتاحاً قديماً كان
  /// محفوظاً كنص صريح في SharedPreferences (ويحذف النسخة غير المشفّرة).
  Future<void> load() async {
    if (_keyLoaded) return;
    if (!forcePrefsMode) {
      final secure = await SecureStore.instance.read(_apiKeySecureKey);
      if (secure != null && secure.isNotEmpty) {
        _apiKey = secure;
        _keyLoaded = true;
        return;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_apiKeyPrefsKey);
    if (legacy != null && legacy.isNotEmpty) {
      _apiKey = legacy;
      _keyLoaded = true;
      if (!forcePrefsMode &&
          await SecureStore.instance.write(_apiKeySecureKey, legacy)) {
        // نُزيل النسخة غير المشفّرة بعد نجاح النقل.
        await prefs.remove(_apiKeyPrefsKey);
      }
      return;
    }
    _apiKey = null;
    _keyLoaded = true;
  }

  /// Saves (or clears, when [key] is null/empty) the DeepSeek API key.
  ///
  /// يُحفظ المفتاح في التخزين الآمن (Android Keystore / iOS Keychain)، ولا
  /// يبقى أي نص صريح في SharedPreferences عند نجاح ذلك.
  Future<void> saveKey(String? key) async {
    final trimmed = (key ?? '').trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await prefs.remove(_apiKeyPrefsKey);
      if (!forcePrefsMode) await SecureStore.instance.delete(_apiKeySecureKey);
      _apiKey = null;
      _keyLoaded = true;
      return;
    }
    var storedSecurely = false;
    if (!forcePrefsMode) {
      storedSecurely =
          await SecureStore.instance.write(_apiKeySecureKey, trimmed);
    }
    if (storedSecurely) {
      await prefs.remove(_apiKeyPrefsKey);
    } else {
      await prefs.setString(_apiKeyPrefsKey, trimmed);
    }
    _apiKey = trimmed;
    _keyLoaded = true;
  }

  /// Sends a chat message to DeepSeek.
  ///
  /// Returns [DeepSeekResult] with either the reply text or a status; the
  /// caller decides how to present it.
  Future<DeepSeekResult> chat({required String message}) async {
    if (!hasKey) {
      return const DeepSeekResult.offline('لم يُضبط مفتاح DeepSeek بعد');
    }
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      // ردّ الذكاء الآلي يكون بلغة الواجهة (لغة جهاز المستخدم) —
                      // على هاتف فرنسي يُرد بالفرنسية، لا بالعربية.
                      'أنت مساعد ALK الصحي داخل تطبيق أندرويد. ردّ بلغة رسالة المستخدم نفسها '
                          'بإيجاز ووضوح، وبأسلوب ودود ومطمئن. لا تقدّم تشخيصاً طبياً نهائياً؛ '
                          'شجّع على مراجعة مختص عند الأعراض الشديدة. عند ذكر الوجبات أعطِ نصيحة '
                          'مختصرة واقترح تمريناً خفيفاً آمناً لكبار السن.',
                },
                {'role': 'user', 'content': message},
              ],
              'temperature': 0.7,
              'max_tokens': 700,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        return DeepSeekResult.error(
          'فشل الاتصال بـ DeepSeek (رمز ${response.statusCode})',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>?;
      final first = choices == null || choices.isEmpty
          ? null
          : choices.first as Map<String, dynamic>;
      final text = first?['message']?['content'] as String?;
      if (text == null || text.trim().isEmpty) {
        return const DeepSeekResult.error('لم يحصل التطبيق على ردّ صالح');
      }
      return DeepSeekResult(text.trim());
    } catch (_) {
      return const DeepSeekResult.offline(
        'تعذّر الوصول إلى DeepSeek (تأكد من اتصالك بالإنترنت)',
      );
    }
  }
}

/// Result of a DeepSeek call.
class DeepSeekResult {
  final String? text;
  final String? offlineMessage;
  final String? errorMessage;

  const DeepSeekResult(this.text)
      : offlineMessage = null,
        errorMessage = null;

  const DeepSeekResult.offline(this.offlineMessage)
      : text = null,
        errorMessage = null;

  const DeepSeekResult.error(this.errorMessage)
      : text = null,
        offlineMessage = null;

  /// True when the model returned usable text.
  bool get hasText => text != null && text!.trim().isNotEmpty;

  /// True when the request could not reach the model (no key / no network).
  bool get isOffline => offlineMessage != null;

  /// True when the server answered with an error.
  bool get isError => errorMessage != null;
}