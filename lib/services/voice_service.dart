import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../storage/sandy_repository.dart';

/// Voice preferences — same JSON schema and storage key as the RN build.
class VoicePreferences {
  final String? voice;
  final double rate;
  final double pitch;

  const VoicePreferences({this.voice, this.rate = 0.52, this.pitch = 1.0});

  factory VoicePreferences.fromJson(Map<String, dynamic> json) {
    final voice = json['voice'] as String?;
    return VoicePreferences(
      voice: (voice == null || voice.trim().isEmpty) ? null : voice,
      rate: _clamp((json['rate'] as num?)?.toDouble() ?? 0.52, 0.3, 1.0),
      pitch: _clamp((json['pitch'] as num?)?.toDouble() ?? 1.0, 0.8, 1.25),
    );
  }

  Map<String, dynamic> toJson() => {
        if (voice != null) 'voice': voice,
        'rate': rate,
        'pitch': pitch,
      };

  VoicePreferences copyWith({String? voice, double? rate, double? pitch}) {
    return VoicePreferences(
      voice: voice ?? this.voice,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
    );
  }

  static double _clamp(double value, double min, double max) =>
      value < min ? min : (value > max ? max : value);
}

/// On-device TTS + speech recognition. Replaces expo-speech and the old
/// server-side transcription; reads/writes the same `alk.voice-preferences.v1`
/// storage key as the RN build so preferences survive migration.
class VoiceService {
  VoiceService._();

  static final VoiceService instance = VoiceService._();

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();
  final SandyRepository _repository = SandyRepository();

  VoicePreferences _preferences = const VoicePreferences();
  bool _ttsReady = false;
  bool _sttInitialized = false;

  VoicePreferences get preferences => _preferences;

  Future<void> loadPreferences() async {
    final raw = await _repository.loadVoicePreferencesRaw();
    if (raw != null) {
      _preferences = VoicePreferences.fromJson(raw);
      // ترحيل تلقائي: من كان على السرعة القديمة السريعة (0.9+) ننقله للبطيئة.
      if (_preferences.rate > 0.8) {
        _preferences = _preferences.copyWith(rate: 0.52);
        await _repository.saveVoicePreferencesRaw(_preferences.toJson());
      }
    }
  }

  Future<void> savePreferences(VoicePreferences preferences) async {
    _preferences = preferences;
    await _repository.saveVoicePreferencesRaw(preferences.toJson());
  }

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    try {
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
    _ttsReady = true;
  }

  /// Speaks [text] in [languageTag] — بطيء وواضح لكبار السن.
  /// [slow] يجعل النطق أبطأ (للتنبيهات المهمة). [elderlyMode] يبطئ أكثر.
  Future<void> speak(
    String text, {
    required String languageTag,
    int variant = 0,
    bool slow = false,
    bool elderlyMode = true,
  }) async {
    if (text.isEmpty) return;
    await _ensureTts();
    try {
      await _tts.setLanguage(languageTag);
      await _selectLanguageVoice(languageTag);
      // سرعة مخصصة لكبار السن: القاعدة 0.52 (بطيئة)، والمهم يُنطق أبطأ.
      var effectiveRate = _preferences.rate;
      if (elderlyMode) {
        effectiveRate = (effectiveRate - 0.05).clamp(0.3, 1.0).toDouble();
        // العربية تحتاج إبطاءً إضافياً لأن محركات TTS تسرع فيها عادة.
        if (languageTag.toLowerCase().startsWith('ar')) {
          effectiveRate = (effectiveRate - 0.05).clamp(0.3, 1.0).toDouble();
        }
      }
      if (slow) {
        effectiveRate = (effectiveRate - 0.08).clamp(0.3, 1.0).toDouble();
      }
      if (variant == 1) {
        effectiveRate = (effectiveRate - 0.02).clamp(0.3, 1.0).toDouble();
      }
      // A very small pitch movement keeps rotated reminders from sounding
      // like the exact same recording, without making the voice artificial.
      final variantPitch = variant == 1 ? -0.015 : (variant == 2 ? 0.015 : 0);
      final effectivePitch =
          (_preferences.pitch + variantPitch).clamp(0.8, 1.25).toDouble();
      await _tts.setSpeechRate(effectiveRate);
      await _tts.setPitch(effectivePitch);
      await _tts.setVolume(1.0);
      await _tts.stop();
      // Keep punctuation as natural pauses; spoken ellipses sound mechanical
      // on several Android voices.
      await _tts.speak(
          pronunciationText(naturalPaced(text, slow: slow), languageTag));
    } catch (_) {
      // Speaking must never crash the app.
    }
  }

  /// Selects a voice only when its locale matches the current translated
  /// language. A saved voice name from another language must never win.
  Future<void> _selectLanguageVoice(String languageTag) async {
    try {
      final result = await _tts.getVoices;
      final availableVoices = result is List ? result : const <dynamic>[];
      final requestedLocale = languageTag.toLowerCase();
      final code = requestedLocale.split('-').first;
      final matching = <Map>[];
      for (final voice in availableVoices) {
        if (voice is! Map) continue;
        final locale = (voice['locale'] as String?)?.toLowerCase() ?? '';
        if (locale == requestedLocale ||
            locale == code ||
            locale.startsWith('$code-')) {
          matching.add(voice);
        }
      }
      if (matching.isEmpty) return;
      final selected = _preferences.voice == null
          ? null
          : matching
              .where((voice) => voice['name'] == _preferences.voice)
              .firstOrNull;
      final voice = selected ?? matching.first;
      final name = voice['name'];
      final locale = voice['locale'];
      if (name is String && locale is String) {
        await _tts.setVoice({'name': name, 'locale': locale});
      }
    } catch (_) {
      // setLanguage above remains the fallback on engines without voice data.
    }
  }

  /// إيقاع مريح: يحوّل النقاط والفواصل إلى وقفات منطوقة.
  static String slowPaced(String text, {bool slow = false}) {
    return naturalPaced(text, slow: slow);
  }

  /// Cleans generated reminder text while leaving punctuation for the TTS
  /// engine to interpret as pauses instead of asking it to pronounce dots.
  static String naturalPaced(String text, {bool slow = false}) {
    var out = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    out = out.replaceAll(RegExp(r'\.{2,}'), '.');
    out = out.replaceAllMapped(
      RegExp(r'([.!؟。！？])(?=[^\s])'),
      (match) => '${match.group(1)} ',
    );
    if (slow) {
      out = out.replaceAllMapped(
        RegExp(r'([،,;:])\s*'),
        (match) => '${match.group(1)}  ',
      );
    }
    return out;
  }

  /// Adds lightweight pronunciation hints for languages where unvocalized
  /// Arabic text is commonly misread by device TTS engines.
  static String pronunciationText(String text, String languageTag) {
    if (!languageTag.toLowerCase().startsWith('ar')) return text;
    var out = text;
    const hints = <String, String>{
      'أهلًا': 'أَهْلًا',
      'مرحبًا': 'مَرْحَبًا',
      'حان': 'حَانَ',
      'موعد': 'مَوْعِد',
      'دوائك': 'دَوَائِكَ',
      'جرعتك': 'جُرْعَتُكَ',
      'الآن': 'الآنَ',
      'خذ': 'خُذْ',
      'خذه': 'خُذْهُ',
      'تذكير': 'تَذْكِير',
      'دواءك': 'دَوَاءَكَ',
      'دقيقة': 'دَقِيقَة',
      'دقائق': 'دَقَائِق',
    };
    for (final entry in hints.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }
    return out;
  }

  /// Returns a standard locale when the translation table only has a base
  /// language code. This lets Android select the correct voice and alphabet.
  static String speechLocaleFor(String language) {
    final code = language.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    const locales = <String, String>{
      'ar': 'ar-SA',
      'de': 'de-DE',
      'en': 'en-US',
      'es': 'es-ES',
      'fr': 'fr-FR',
      'hi': 'hi-IN',
      'id': 'id-ID',
      'it': 'it-IT',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
      'nl': 'nl-NL',
      'pl': 'pl-PL',
      'pt': 'pt-PT',
      'ru': 'ru-RU',
      'th': 'th-TH',
      'tr': 'tr-TR',
      'uk': 'uk-UA',
      'vi': 'vi-VN',
      'zh': 'zh-CN',
    };
    return locales[code] ?? (code.isEmpty ? 'en-US' : code);
  }

  /// اختصار للنطق البطيء جداً (تنبيهات الأدوية والطوارئ).
  Future<void> speakSlow(String text, {required String languageTag}) {
    return speak(text, languageTag: languageTag, slow: true);
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Device voices for a language (first BCP-47 segment match), mirroring
  /// `getDeviceVoicesForLanguage` in the RN build.
  Future<List<String>> voicesForLanguage(String languageTag) async {
    await _ensureTts();
    try {
      final result = await _tts.getVoices;
      final voices = result is List ? result : const <dynamic>[];
      final code = languageTag.toLowerCase().split('-').first;
      return voices
          .whereType<Map>()
          .where((v) =>
              ((v['locale'] as String?) ?? '').toLowerCase().split('-').first ==
              code)
          .map((v) => (v['name'] as String?) ?? '')
          .where((name) => name.isNotEmpty)
          .toList()
        ..sort();
    } catch (_) {
      return const [];
    }
  }

  /// True when the on-device speech recognizer is available and permitted.
  Future<bool> get speechReady async {
    if (_sttInitialized) return true;
    try {
      _sttInitialized = await _stt.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _sttInitialized = false;
    }
    return _sttInitialized;
  }

  /// Starts listening; recognized text is streamed to [onResult].
  Future<bool> startListening({
    required String localeId,
    required void Function(String text) onResult,
  }) async {
    if (!await speechReady) return false;
    try {
      await _stt.listen(
        onResult: (result) => onResult(result.recognizedWords),
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          localeId: localeId,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}

/// Helper used by settings screen to persist raw JSON.
String encodeVoicePreferences(VoicePreferences preferences) =>
    jsonEncode(preferences.toJson());
