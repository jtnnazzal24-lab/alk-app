import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';

import '../l10n/app_strings.dart';
import 'deepseek_service.dart';

/// ترجمة قاموس مفردات التطبيق مرة واحدة وتخزينها على الجهاز.
///
/// العربية هي لغة المصدر داخل الشيفرة، ومفرداتها مجموعة في
/// `assets/source_dictionary.json`. عند تشغيل التطبيق على هاتف لغته غير العربية
/// (فرنسية مثلاً):
///
/// 1. يُقرأ القاموس العربي من حزمة التطبيق.
/// 2. يُبحث عن ترجمة مخزَّنة على الجهاز لنفس اللغة ونفس نسخة القاموس، فإن وُجدت
///    عُرضت فوراً بلا أي اتصال بالإنترنت — وهذا هو المقصود: لا ترجمة في كل تشغيل.
/// 3. إن لم توجد، تُترجم المفردات مرة واحدة في الخلفية مع حفظ تدريجي (checkpoint)
///    حتى يكمل من حيث توقّف لو أُغلق التطبيق في منتصف الطريق.
/// 4. تُحفظ الترجمة في ملف داخل مجلد التطبيق الخاص على الجهاز، ويُحذف تخزين أي
///    لغة أخرى (لغة واحدة فقط في كل هاتف).
///
/// نطاق الترجمة: تُترجم **كل فئات القاموس ما عدا `voice_commands`**. هذه الفئة
/// هي أنماط تعبيرات عادية عربية مكتوبة للمطابقة الحرفية في
/// `lib/logic/voice_intent.dart`، ومحرّك التعرّف على الكلام في الهاتف ديناميكي
/// يرجّع النص بلغة الجهاز، لذلك تُرجَع الجملة المسموعة إلى العربية عبر
/// [toSourceLanguage] قبل تحليل نية الأمر، وتُترجم الردود والقوائم المنطوقة
/// (فئة `voice`) وتُنطق بلغة الواجهة. لا تُترجم أنماط المطابقة نفسها لأن ترجمتها
/// تُبطل عمل القواعد.
class DictionaryTranslationService {
  DictionaryTranslationService._();

  static final DictionaryTranslationService instance =
      DictionaryTranslationService._();

  /// القاموس العربي المستخرج من مفردات التطبيق (مرآة `source_dictionary.json`).
  static const String dictionaryAsset = 'assets/source_dictionary.json';

  static const String _dirName = 'alk-dictionary';
  static const String _filePrefix = 'ui-dictionary-';
  static const String _langPrefsKey = 'alk.dictionary.target-language';
  static const String _versionPrefsKey = 'alk.dictionary.source-version';
  static const String _payloadPrefsKey = 'alk.dictionary.payload';

  /// عدد الطلبات المتوازية أثناء الترجمة.
  static const int _maxConcurrent = 4;

  /// بعد هذا العدد من النصوص تُحفظ نسخة مؤقتة وتُحدَّث الواجهة.
  static const int _checkpointEvery = 20;

  /// عند هذا العدد من الإخفاقات المتتالية نتوقف (لا إنترنت غالباً).
  static const int _maxConsecutiveFailures = 8;

  static const Duration _requestTimeout = Duration(seconds: 20);

  /// مهلة قصيرة بين طلب وآخر لكل عامل، لتقليل احتمال تجاوز الحد المسموح.
  static const Duration _requestSpacing = Duration(milliseconds: 250);

  /// انتظار أوّلي عند تجاوز الحد المسموح (429)، يتضاعف مع كل محاولة.
  static const Duration _throttleBaseDelay = Duration(seconds: 3);

  /// عدد مرات إعادة المحاولة عند تجاوز الحد قبل اعتبار النص متعذّراً.
  static const int _maxThrottleRounds = 3;

  bool _running = false;
  String? _language;
  String? _engine;
  String? _lastError;
  int _done = 0;
  int _total = 0;
  GoogleTranslator? _packageTranslator;
  _SourceDictionary? _sourceCache;

  /// ذاكرة مؤقتة لآخر الجمل المسموعة بعد إرجاعها إلى العربية.
  final Map<String, String> _reverseCache = <String, String>{};
  static const int _reverseCacheLimit = 40;

  /// الترجمة قيد التنفيذ الآن.
  bool get running => _running;

  /// اللغة الجارية (أو التي جُرّبت آخر مرة).
  String? get language => _language;

  /// المحرك الذي نجح في الترجمة (google / google-package / deepseek / cache).
  String? get engine => _engine;

  /// عدد النصوص التي فُصل فيها (مترجمة أو مؤكَّد أنها لا تحتاج ترجمة).
  int get translatedCount => _done;

  /// عدد مفردات القاموس العربي.
  int get sourceCount => _total;

  /// نسبة التقدّم (0..1).
  double get progress => _total == 0 ? 0 : (_done / _total).clamp(0.0, 1.0);

  /// هل اكتملت الترجمة؟
  bool get isComplete => _total > 0 && _done >= _total;

  /// رسالة آخر خطأ (تُعرض في الإعدادات عند الحاجة).
  String? get lastError => _lastError;

  /// هل هذا النص من مفردات العرض القابلة للترجمة؟
  ///
  /// تُستثنى فئة `voice_commands` (أنماط مطابقة عربية في `voice_intent.dart`):
  /// نُسخت في القاموس للتوثيق فقط، وترجمتها تُبطل القواعد. كل الفئات الأخرى
  /// (ui بما فيها الإعدادات، voice، notifications، errors، medical) تُترجم.
  /// للاختبارات: تعمل بعد تحميل القاموس من الحزمة (عبر `restoreCache` مثلاً).
  static bool translates(String text) {
    final source = DictionaryTranslationService.instance._sourceCache;
    if (source == null) return false;
    return source.texts.contains(text);
  }

  /// لغة الهاتف الحالية ('ar' لهاتف عربي، 'fr' لهاتف فرنسي...).
  static String deviceLanguageTag() {
    try {
      final code = PlatformDispatcher.instance.locale.languageCode.trim();
      return code.isEmpty ? 'ar' : code.toLowerCase();
    } catch (_) {
      return 'ar';
    }
  }

  /// يُحمّل الترجمة المخزَّنة إن كانت جاهزة (سريع: بلا شبكة).
  ///
  /// يُستدعى قبل `runApp` حتى يظهر التطبيق بلغة الهاتف من الإطار الأول.
  /// يعيد true إذا عُرضت ترجمة مخزَّنة (كاملة أو جزئية).
  Future<bool> restoreCache(String targetLanguage) async {
    final lang = _normalize(targetLanguage);
    _language = lang;
    if (lang == 'ar') {
      AppStrings.current = 'ar';
      AppStrings.table.clear();
      return false;
    }
    AppStrings.current = lang;
    try {
      final source = await _loadSource();
      _total = source.texts.length;
      final cached = await _readCache(lang, source.version);
      if (cached == null || cached.isEmpty) {
        AppStrings.table.clear();
        return false;
      }
      final textSet = source.texts.toSet();
      final valid = <String, String>{};
      for (final entry in cached.entries) {
        if (textSet.contains(entry.key) && entry.value.trim().isNotEmpty) {
          valid[entry.key] = entry.value;
        }
      }
      final complete = valid.length >= _total &&
          source.texts.every((text) => valid.containsKey(text));
      if (!complete) {
        AppStrings.table.clear();
        _done = 0;
        _engine = null;
        return false;
      }
      final displayable = _displayable(valid);
      AppStrings.table.clear();
      AppStrings.table.load(displayable);
      AppStrings.table.generation = 2;
      _done = valid.length;
      _engine = 'cache';
      return AppStrings.table.size > 0;
    } catch (e) {
      _lastError = 'dictionary-restore-failed: $e';
      AppStrings.table.clear();
      return false;
    }
  }

  /// يُعيد النص العربي (لغة المصدر) لما سمعه التطبيق بلغة الهاتف.
  ///
  /// محرّك التعرّف على الكلام في الهاتف ديناميكي ويرجّع النص بلغة الجهاز، بينما
  /// قواعد فهم الأوامر مكتوبة بالعربية؛ لذلك تُترجم الجملة المسموعة إلى العربية
  /// قبل تحليلها. النتائج تُحفظ مؤقتاً في الذاكرة فقط.
  Future<String> toSourceLanguage(String text) async {
    final trimmed = text.trim();
    final from = AppStrings.current;
    if (trimmed.isEmpty || from == 'ar') return text;
    final cached = _reverseCache[trimmed];
    if (cached != null) return cached;
    try {
      final out = await _googleRequest(trimmed, from: from, to: 'ar');
      if (out == null || out.trim().isEmpty) return text;
      if (_reverseCache.length >= _reverseCacheLimit) _reverseCache.clear();
      return _reverseCache[trimmed] = out.trim();
    } catch (_) {
      // تعذّر الوصول للمترجم → تُجرَّب القواعد العربية على النص كما هو.
      return text;
    }
  }

  /// يجهّز الترجمة للغة الواجهة (يُستدعى من `main` بعد أول إطار).
  ///
  /// آمن للاستدعاء أكثر من مرة: إن كانت الترجمة جاهزة أو جارية فلا شيء يحدث.
  Future<void> start({
    String? targetLanguage,
    VoidCallback? onChanged,
  }) async {
    final lang = _normalize(targetLanguage ?? deviceLanguageTag());
    if (_running) return; // ترجمة واحدة في كل مرة
    _language = lang;
    if (lang == 'ar') {
      // العربية لغة المصدر — لا ترجمة ولا تخزين.
      AppStrings.current = 'ar';
      _done = 0;
      _total = 0;
      onChanged?.call();
      return;
    }
    _running = true;
    _lastError = null;
    try {
      await _ensure(lang, onChanged);
    } catch (e) {
      _lastError = 'dictionary-translation-failed: $e';
    } finally {
      _running = false;
      onChanged?.call();
    }
  }

  /// يعيد محاولة تجهيز الترجمة (من زر في الإعدادات عند تعذّرها).
  Future<void> retry({VoidCallback? onChanged}) {
    _lastError = null;
    return start(
      targetLanguage: _language ?? deviceLanguageTag(),
      onChanged: onChanged,
    );
  }

  /// يحذف الترجمة المخزَّنة (تعود الواجهة للعربية في التشغيل التالي).
  Future<void> clearStoredTranslations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_langPrefsKey);
      await prefs.remove(_versionPrefsKey);
      await prefs.remove(_payloadPrefsKey);
    } catch (_) {}
    final dir = await _cacheDirectory();
    if (dir != null) {
      try {
        for (final entity in dir.listSync()) {
          if (entity is File && entity.path.contains(_filePrefix)) {
            await entity.delete();
          }
        }
      } catch (_) {}
    }
    _done = 0;
    _total = 0;
    _engine = null;
    AppStrings.table.clear();
  }

  // ---- الخطوات الفعلية ------------------------------------------------------

  Future<void> _ensure(String lang, VoidCallback? onChanged) async {
    AppStrings.current = lang;
    final source = await _loadSource();
    final texts = source.texts;
    _total = texts.length;
    if (texts.isEmpty) {
      _lastError = 'dictionary-empty';
      return;
    }

    final translations =
        await _readCache(lang, source.version) ?? <String, String>{};
    if (translations.isNotEmpty) {
      // لا تُقبل ترجمة جزئية: إذا كان التخزين غير كامل نرفضه ونطلب الترجمة كاملة
      // حتى لا تظهر نصوص عربية ناقصة في واجهة اللغة الأخرى.
      final textSet = texts.toSet();
      final valid = <String, String>{};
      for (final entry in translations.entries) {
        if (textSet.contains(entry.key) && entry.value.trim().isNotEmpty) {
          valid[entry.key] = entry.value;
        }
      }
      if (valid.length < _total ||
          texts.any((text) => !valid.containsKey(text))) {
        AppStrings.table.clear();
        _done = 0;
        _engine = null;
      } else {
        AppStrings.table.load(_displayable(valid));
        AppStrings.table.generation = 2;
        _done = valid.length;
        _engine = 'cache';
        onChanged?.call();
        return;
      }
    }
    if (translations.length >= _total) return; // الترجمة جاهزة ومخزَّنة مسبقاً

    final missing =
        texts.where((text) => !translations.containsKey(text)).toList();
    if (missing.isEmpty) {
      _done = _total;
      AppStrings.table.generation = 2;
      return;
    }

    // ترجمة الناقص فقط (يكمل من حيث توقّف التشغيل السابق).
    _engine = null;
    var failures = 0;
    var sinceCheckpoint = 0;
    var index = 0;
    final fresh = <String, String>{};

    Future<void> worker() async {
      while (index < missing.length) {
        final text = missing[index++];
        final translated = await _translateText(text, lang);
        if (translated == null) {
          failures++;
          if (failures >= _maxConsecutiveFailures) {
            throw StateError('translation-unavailable');
          }
          continue;
        }
        failures = 0;
        translations[text] = translated;
        fresh[text] = translated;
        sinceCheckpoint++;
        if (sinceCheckpoint >= _checkpointEvery) {
          sinceCheckpoint = 0;
          await _commit(lang, source.version, translations, fresh,
              onChanged: onChanged);
        }
        // فاصل صغير يقلّل احتمال تجاوز الحد المسموح من المزوّد.
        if (index < missing.length) await Future<void>.delayed(_requestSpacing);
      }
    }

    final workers = <Future<void>>[];
    for (var i = 0; i < _maxConcurrent; i++) {
      workers.add(worker());
    }
    try {
      await Future.wait(workers);
    } finally {
      // يُحفظ ما تُرجم حتى لو توقف العمل، ويكمل في التشغيل التالي.
      await _commit(lang, source.version, translations, fresh,
          onChanged: onChanged);
    }
  }

  /// يحفظ الدفعة، يخزّنها على الجهاز، ويعرض الجديد في الواجهة.
  Future<void> _commit(
    String lang,
    String version,
    Map<String, String> all,
    Map<String, String> fresh, {
    VoidCallback? onChanged,
  }) async {
    if (fresh.isNotEmpty) {
      AppStrings.table.load(Map<String, String>.of(fresh));
      fresh.clear();
      _done = all.length;
      if (AppStrings.table.generation == 0) AppStrings.table.generation = 1;
    }
    final complete = _total > 0 && all.length >= _total;
    if (complete) AppStrings.table.generation = 2;
    await _writeCache(lang, version, all, complete: complete);
    onChanged?.call();
  }

  // ---- قراءة القاموس العربي -------------------------------------------------

  Future<_SourceDictionary> _loadSource() async {
    final cached = _sourceCache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(dictionaryAsset);
    final decoded = jsonDecode(raw);
    final texts = <String>{};
    if (decoded is Map && decoded['categories'] is Map) {
      // كل الفئات تُترجم ما عدا أنماط الأوامر الصوتية (`voice_commands`) — فهي
      // تعبيرات عربية للمطابقة الحرفية في `voice_intent.dart` (ليست نصوص عرض).
      for (final entry in (decoded['categories'] as Map).entries) {
        if (entry.key == 'voice_commands') continue;
        _collectTexts(entry.value, texts);
      }
    } else {
      _collectTexts(decoded, texts);
    }
    if (texts.isEmpty) {
      throw StateError('dictionary-empty-or-invalid');
    }
    final version = decoded is Map && decoded['meta'] is Map
        ? (decoded['meta'] as Map)['version']?.toString() ?? '1.0.0'
        : '1.0.0';
    final sorted = texts.toList()..sort();
    return _sourceCache = _SourceDictionary(version, sorted);
  }

  /// يجمع كل قيمة `text` في أي عمق من بنية القاموس.
  void _collectTexts(Object? node, Set<String> out) {
    if (node is Map) {
      final text = node['text'];
      if (text is String) {
        final trimmed = text.trim();
        if (trimmed.isNotEmpty && !out.contains(trimmed)) {
          out.add(trimmed);
        }
        return;
      }
      for (final value in node.values) {
        _collectTexts(value, out);
      }
    } else if (node is List) {
      for (final value in node) {
        _collectTexts(value, out);
      }
    }
  }

  /// النصوص التي لها ترجمة فعلية (تُستثنى المطابقة للأصل والعناصر الفارغة).
  Map<String, String> _displayable(Map<String, String> stored) {
    final out = <String, String>{};
    stored.forEach((source, target) {
      if (target.isNotEmpty && target != source) out[source] = target;
    });
    return out;
  }

  // ---- التخزين على الجهاز ---------------------------------------------------

  Future<Directory?> _cacheDirectory() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$_dirName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _cacheFile(String lang) async {
    final dir = await _cacheDirectory();
    if (dir == null) return null;
    return File('${dir.path}/$_filePrefix$lang.json');
  }

  /// يقرأ ترجمة مخزَّنة صالحة (نفس اللغة ونفس نسخة القاموس) أو null.
  Future<Map<String, String>?> _readCache(String lang, String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_langPrefsKey) != lang) return null;
      if (prefs.getString(_versionPrefsKey) != version) return null;
      String? raw;
      final file = await _cacheFile(lang);
      if (file != null) {
        try {
          if (await file.exists()) raw = await file.readAsString();
        } catch (_) {}
      }
      raw ??= prefs.getString(_payloadPrefsKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final strings = decoded['strings'];
      if (strings is! Map) return null;
      final out = <String, String>{};
      strings.forEach((key, value) {
        if (key is String && value is String && value.isNotEmpty) {
          out[key] = value;
        }
      });
      return out;
    } catch (e) {
      _lastError = 'dictionary-cache-unreadable: $e';
      return null;
    }
  }

  /// يخزّن الترجمة في ملف داخل مجلد التطبيق (وSharedPreferences كبديل).
  Future<void> _writeCache(
    String lang,
    String version,
    Map<String, String> strings, {
    required bool complete,
  }) async {
    try {
      final payload = jsonEncode(<String, Object>{
        'meta': <String, Object>{
          'sourceLanguage': 'ar',
          'targetLanguage': lang,
          'sourceDictionaryVersion': version,
          'engine': _engine ?? 'google',
          'sourceCount': _total,
          'translatedCount': strings.length,
          'complete': complete,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        'strings': strings,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_langPrefsKey, lang);
      await prefs.setString(_versionPrefsKey, version);
      final file = await _cacheFile(lang);
      if (file != null) {
        try {
          await file.writeAsString(payload, flush: true);
          await prefs.remove(_payloadPrefsKey);
          await _purgeOtherLanguages(lang);
          return;
        } catch (_) {
          // تعذّر الملف (صلاحيات/مساحة) → نخزّن في التفضيلات.
        }
      }
      await prefs.setString(_payloadPrefsKey, payload);
      await _purgeOtherLanguages(lang);
    } catch (e) {
      _lastError = 'dictionary-cache-write-failed: $e';
    }
  }

  /// لغة واحدة فقط مخزَّنة في كل هاتف: تُحذف ترجمات اللغات الأخرى.
  Future<void> _purgeOtherLanguages(String keep) async {
    final dir = await _cacheDirectory();
    if (dir == null) return;
    final current = '$_filePrefix$keep.json';
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith(_filePrefix) && name != current) {
          await entity.delete();
        }
      }
    } catch (_) {}
  }
  // ---- محرّكات الترجمة ------------------------------------------------------

  /// يترجم نصاً واحداً: جوجل المباشر ← حزمة translator ← DeepSeek (إن وُجد مفتاح).
  ///
  /// يعيد null عند فشل كل المحرّكات، وحينها يُعرض النص العربي كما هو.
  /// وعند تجاوز الحد المسموح (429) ينتظر ويعيد الجولة كاملة بدل اعتباره فشلاً.
  Future<String?> _translateText(String text, String lang) async {
    final masked = _mask(text);
    var delay = _throttleBaseDelay;
    for (var round = 0; round <= _maxThrottleRounds; round++) {
      var throttled = false;
      final attempts = <Future<String?> Function()>[
        () => _googleDirect(masked.body, lang),
        () => _googlePackage(masked.body, lang),
        () => _deepSeek(masked.body, lang),
      ];
      for (final attempt in attempts) {
        try {
          final raw = await attempt();
          if (raw == null) continue;
          final restored = _restore(raw, masked.slots);
          if (restored != null) return restored;
        } on _ThrottledException catch (e) {
          throttled = true;
          if (e.retryAfter > delay) delay = e.retryAfter;
          break; // كل المحرّكات ستُحدّ من نفس المزوّد — ننتظر أولاً.
        } catch (_) {
          // المحرك التالي.
        }
      }
      if (!throttled || round == _maxThrottleRounds) return null;
      await Future<void>.delayed(delay);
      delay *= 2;
    }
    return null;
  }

  /// يحمي متغيرات النص ($name / ${...}) قبل إرساله للمترجم.
  ({String body, List<String> slots}) _mask(String source) {
    final slots = <String>[];
    final body = source.replaceAllMapped(
      TranslationTable.placeholderPattern,
      (match) {
        slots.add(match.group(0)!);
        return '[[${slots.length - 1}]]';
      },
    );
    return (body: body, slots: slots);
  }

  /// يتحقق من بقاء متغيرات النص في الترجمة ويعيد توحيد علاماتها.
  ///
  /// يعيد null إذا فقدت الترجمة أحد المتغيرات، فيُعرض النص العربي بدل جملة ناقصة.
  String? _restore(String raw, List<String> slots) {
    var out = raw.trim();
    if (out.isEmpty) return null;
    out = TranslationTable.normalizeMarkers(out);
    for (var i = 0; i < slots.length; i++) {
      final strict = RegExp('\\[\\[\\s*$i\\s*\\]\\]');
      if (strict.hasMatch(out)) continue;
      // بعض المحرّكات تُفقد قوساً واحداً ([[0]] ← [0]).
      final loose = RegExp(r'\[\s*' '$i' r'\s*\]');
      if (!loose.hasMatch(out)) return null;
      out = out.replaceAllMapped(loose, (match) => '[[$i]]');
    }
    return out;
  }

  /// واجهة جوجل المباشرة (تعمل بلا مفتاح API) — من العربية إلى لغة الواجهة.
  Future<String?> _googleDirect(String text, String lang) =>
      _googleRequest(text, from: 'ar', to: lang);

  /// طلب ترجمة واحد من واجهة جوجل المجانية.
  Future<String?> _googleRequest(
    String text, {
    required String from,
    required String to,
  }) async {
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': from,
      'tl': to,
      'hl': to,
      'dt': 't',
      'ie': 'UTF-8',
      'oe': 'UTF-8',
      'otf': '1',
      'ssel': '0',
      'tsel': '0',
      'kc': '1',
      'q': text,
    });
    final response = await http.get(uri).timeout(_requestTimeout);
    if (response.statusCode == 429 || response.statusCode == 503) {
      throw _ThrottledException(_retryAfter(response));
    }
    if (response.statusCode != 200) {
      throw http.ClientException('google-${response.statusCode}', uri);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
      throw const FormatException('google-unexpected-response');
    }
    final buffer = StringBuffer();
    for (final segment in decoded.first as List) {
      if (segment is List && segment.isNotEmpty && segment.first is String) {
        buffer.write(segment.first as String);
      }
    }
    final out = buffer.toString();
    if (out.trim().isEmpty) throw const FormatException('google-empty');
    _engine ??= 'google';
    return out;
  }

  /// مدة الانتظار التي يطلبها المزوّد (ترويسة Retry-After) أو المهلة الافتراضية.
  Duration _retryAfter(http.Response response) {
    final header = response.headers['retry-after']?.trim() ?? '';
    final seconds = int.tryParse(header);
    if (seconds != null && seconds > 0 && seconds <= 120) {
      return Duration(seconds: seconds);
    }
    return _throttleBaseDelay;
  }

  /// حزمة `translator` (بديل ثانٍ بنفس المزوّد).
  Future<String?> _googlePackage(String text, String lang) async {
    final translator = _packageTranslator ??= GoogleTranslator();
    final Translation result;
    try {
      result = await translator
          .translate(text, from: 'ar', to: lang)
          .timeout(_requestTimeout);
    } on http.ClientException catch (e) {
      if (e.message.contains('429') || e.message.contains('503')) {
        throw const _ThrottledException(_throttleBaseDelay);
      }
      rethrow;
    }
    if (result.text.trim().isEmpty) return null;
    _engine ??= 'google-package';
    return result.text;
  }

  /// DeepSeek كخيار أخير (يعمل فقط عند إضافة مفتاح API من الإعدادات).
  Future<String?> _deepSeek(String text, String lang) async {
    final service = DeepSeekService.instance;
    await service.load();
    if (!service.hasKey) return null;
    final result = await service.chat(
      message: 'ترجم النص التالي من العربية إلى ${_languageName(lang)} '
          'وأعد الترجمة وحدها دون شرح أو تكرار للنص الأصلي، '
          'مع الإبقاء على العلامات [[0]] و[[1]] وأسطر النص كما هي:\n$text',
    );
    if (result.isError && (result.errorMessage?.contains('429') ?? false)) {
      throw const _ThrottledException(_throttleBaseDelay);
    }
    if (!result.hasText) return null;
    _engine ??= 'deepseek';
    return result.text;
  }

  /// اسم اللغة بالإنجليزية (لصياغة طلب الترجمة لدى DeepSeek).
  ///
  /// أسماء اللغات الشائعة مُدرجة محلياً، وأي لغة أخرى يُرسل رمزها كما هو.
  String _languageName(String code) {
    const names = <String, String>{
      'ar': 'Arabic',
      'en': 'English',
      'fr': 'French',
      'de': 'German',
      'es': 'Spanish',
      'it': 'Italian',
      'pt': 'Portuguese',
      'nl': 'Dutch',
      'tr': 'Turkish',
      'ru': 'Russian',
      'uk': 'Ukrainian',
      'pl': 'Polish',
      'ro': 'Romanian',
      'sv': 'Swedish',
      'da': 'Danish',
      'no': 'Norwegian',
      'fi': 'Finnish',
      'el': 'Greek',
      'cs': 'Czech',
      'hu': 'Hungarian',
      'bg': 'Bulgarian',
      'he': 'Hebrew',
      'fa': 'Persian',
      'ur': 'Urdu',
      'hi': 'Hindi',
      'bn': 'Bengali',
      'id': 'Indonesian',
      'ms': 'Malay',
      'sw': 'Swahili',
      'ha': 'Hausa',
      'am': 'Amharic',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'vi': 'Vietnamese',
      'th': 'Thai',
      'tl': 'Filipino',
    };
    return names[code] ?? code;
  }

  static String _normalize(String tag) {
    final code = tag.trim().toLowerCase();
    final dash = code.indexOf('-');
    final base = dash < 0 ? code : code.substring(0, dash);
    return base.isEmpty ? 'ar' : base;
  }
}

class _SourceDictionary {
  const _SourceDictionary(this.version, this.texts);

  /// نسخة القاموس العربي (من `meta.version`).
  final String version;

  /// كل مفردات التطبيق (بلا تكرار، مرتّبة).
  final List<String> texts;
}

/// تجاوز الحد المسموح من مزوّد الترجمة (429/503): يُنتظر ثم تُعاد المحاولة
/// بدل اعتبار النص متعذّراً.
class _ThrottledException implements Exception {
  const _ThrottledException(this.retryAfter);

  final Duration retryAfter;

  @override
  String toString() => 'throttled(retry-after=${retryAfter.inSeconds}s)';
}
