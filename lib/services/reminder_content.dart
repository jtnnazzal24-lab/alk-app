import '../l10n/app_strings.dart';
import 'voice_service.dart';

/// Port of `lib/reminder-voice.ts` — localized reminder lines with the same
/// 3-variant rotation chosen deterministically from the medication id.
class ReminderMessage {
  final String title;
  final String body;
  final String spokenText;
  final String languageTag;
  final int variant;

  const ReminderMessage({
    required this.title,
    required this.body,
    required this.spokenText,
    required this.languageTag,
    required this.variant,
  });
}

class _ReminderContent {
  final String title;

  /// عنوان تذكير ما قبل الجرعة («اقترب موعد دوائك»).
  final String preTitle;
  final String tag;
  final List<String Function(String name)> lines;

  /// أسطر ما قبل الجرعة: (اسم الدواء، عدد الدقائق المتبقية).
  final List<String Function(String name, int minutes)> preLines;
  const _ReminderContent(
      this.title, this.preTitle, this.tag, this.lines, this.preLines);
}

/// Only ar/en/zh reminder voices ship (other language tags fall back to en).
final _reminderLines = <String, _ReminderContent>{
  'ar': const _ReminderContent('موعد دوائك', 'اقترب موعد دوائك', 'ar-SA', [
    _arLine1,
    _arLine2,
    _arLine3,
  ], [
    _arPreLine1,
    _arPreLine2,
    _arPreLine3,
  ]),
  'en': const _ReminderContent(
      'Medicine reminder', 'Dose time is near', 'en-US', [
    _enLine1,
    _enLine2,
    _enLine3,
  ], [
    _enPreLine1,
    _enPreLine2,
    _enPreLine3,
  ]),
  'zh': const _ReminderContent('用药提醒', '快到用药时间', 'zh-CN', [
    _zhLine1,
    _zhLine2,
    _zhLine3,
  ], [
    _zhPreLine1,
    _zhPreLine2,
    _zhPreLine3,
  ]),
};

String _arLine1(String n) => 'أهلًا، حان وقت $n. خذه الآن إذا كان مناسبًا لك.';
String _arLine2(String n) =>
    'تذكير لطيف من ALK، موعد $n الآن. لا تنسَ تسجيل الجرعة بعد تناولها.';
String _arLine3(String n) =>
    'مرحبًا، هذه جرعتك المجدولة من $n. اعتنِ بنفسك وخذها في الوقت المناسب.';
String _enLine1(String n) =>
    'Hello, it is time for $n. Please take it now if it is right for you.';
String _enLine2(String n) =>
    'A gentle reminder from ALK: $n is due now. Remember to confirm the dose after.';
String _enLine3(String n) =>
    'Hello, this is your scheduled dose of $n. Take good care and take it at the right time.';
String _zhLine1(String n) => '您好，该吃 $n 了。如果方便，请现在服用。';
String _zhLine2(String n) => '来自 ALK 的温馨提醒：$n 的时间到了。服药后请记得记录。';
String _zhLine3(String n) => '您好，这是您预定的 $n 剂量。请照顾好自己，准时服药。';

/// أسطر «اقترب موعد دوائك» — تُعرض/تُنطق قبل الجرعة بعدة دقائق.
String _arPreLine1(String n, int m) =>
    'اقترب موعد دوائك: بقي $m دقيقة على جرعة $n.';
String _arPreLine2(String n, int m) =>
    'تنبيه من ALK: بعد $m دقيقة حان وقت $n. جهّز دواءك وكأس ماء.';
String _arPreLine3(String n, int m) =>
    'لا تنسَ جرعتك: $n بعد $m دقيقة. اضغط لتسمع التذكير.';
String _enPreLine1(String n, int m) =>
    'Your dose is near: $m minutes until $n.';
String _enPreLine2(String n, int m) =>
    'ALK reminder: $n is due in $m minutes. Get your medicine ready.';
String _enPreLine3(String n, int m) =>
    'Do not forget your dose: $n in $m minutes.';
String _zhPreLine1(String n, int m) => '快到服药时间了：还有 $m 分钟该吃 $n。';
String _zhPreLine2(String n, int m) => 'ALK 提醒：$m 分钟后该服用 $n。请准备好药物。';
String _zhPreLine3(String n, int m) => '别忘了您的药：$m 分钟后服用 $n。';

/// Deterministic variant from the medication id — identical arithmetic to RN.
int reminderVariant(String medicationId) {
  var sum = 0;
  for (final code in medicationId.codeUnits) {
    sum += code;
  }
  return sum % 3;
}

ReminderMessage localizedReminderMessage({
  required String medicationId,
  required String medicationName,
  required String language,
}) {
  final code = language.split('-').first.toLowerCase();
  final variant = reminderVariant(medicationId);
  final table = AppStrings.table;

  // هاتف لغته غير عربية وجهّزت ترجمة القاموس: تُترجم أسطر التذكير من المصدر
  // العربي نفسه، فيسمع المستخدم التذكير بلغة هاتفه.
  if (table.active && !code.startsWith('ar')) {
    final arabic = _reminderLines['ar']!;
    final arabicBody = arabic.lines[variant](medicationName);
    final body = table.lookup(arabicBody);
    final title = table.lookup(arabic.title);
    if (body != arabicBody && title != arabic.title) {
      return ReminderMessage(
        title: title,
        body: body,
        spokenText: body,
        languageTag: _ttsTagFor(table.language),
        variant: variant,
      );
    }
    // لم تُجهَّز الترجمة بعد → المحتوى الإنجليزي أفضل من العربي لغير الناطقين به.
    final english = _reminderLines['en']!;
    final englishBody = english.lines[variant](medicationName);
    return ReminderMessage(
      title: english.title,
      body: englishBody,
      spokenText: englishBody,
      languageTag: english.tag,
      variant: variant,
    );
  }

  final content = _reminderLines[code] ?? _reminderLines['en']!;
  final spoken = content.lines[variant](medicationName);
  return ReminderMessage(
    title: content.title,
    body: spoken,
    spokenText: spoken,
    languageTag: content.tag,
    variant: variant,
  );
}

/// تذكير ما قبل الجرعة — «اقترب موعد دوائك» — قبل الجرعة بـ[minutes] دقيقة.
///
/// نفس منطق [localizedReminderMessage]: العربية مصدر، وعند لغة واجهة أخرى
/// تُقرأ الترجمة المخزَّنة على الجهاز، وإلا يُعرض المحتوى الإنجليزي.
ReminderMessage localizedPreDoseReminderMessage({
  required String medicationId,
  required String medicationName,
  required String language,
  required int minutes,
}) {
  final code = language.split('-').first.toLowerCase();
  final variant = reminderVariant(medicationId);
  final table = AppStrings.table;

  if (table.active && !code.startsWith('ar')) {
    final arabic = _reminderLines['ar']!;
    final arabicBody = arabic.preLines[variant](medicationName, minutes);
    final body = table.lookup(arabicBody);
    final title = table.lookup(arabic.preTitle);
    if (body != arabicBody && title != arabic.preTitle) {
      return ReminderMessage(
        title: title,
        body: body,
        spokenText: body,
        languageTag: _ttsTagFor(table.language),
        variant: variant,
      );
    }
    final english = _reminderLines['en']!;
    final englishBody = english.preLines[variant](medicationName, minutes);
    return ReminderMessage(
      title: english.preTitle,
      body: englishBody,
      spokenText: englishBody,
      languageTag: english.tag,
      variant: variant,
    );
  }

  final content = _reminderLines[code] ?? _reminderLines['en']!;
  final text = content.preLines[variant](medicationName, minutes);
  return ReminderMessage(
    title: content.preTitle,
    body: text,
    spokenText: text,
    languageTag: content.tag,
    variant: variant,
  );
}

/// وسم نطق (TTS) مناسب للغة الواجهة المترجمة: 'fr' ← 'fr-FR'.
String _ttsTagFor(String language) {
  return VoiceService.speechLocaleFor(language);
}

/// Clamps and normalizes voice preferences exactly like `voice-preferences.ts`.
class VoicePreferences {
  final String? voice;
  final double rate;
  final double pitch;

  const VoicePreferences({this.voice, this.rate = 0.52, this.pitch = 1.0});

  factory VoicePreferences.fromJson(Map<String, dynamic> json) {
    return VoicePreferences(
      voice:
          json['voice'] is String && (json['voice'] as String).trim().isNotEmpty
              ? json['voice'] as String
              : null,
      rate: _clamp((json['rate'] as num?)?.toDouble() ?? 0.52, 0.3, 1.0),
      pitch: _clamp((json['pitch'] as num?)?.toDouble() ?? 1.0, 0.8, 1.25),
    );
  }

  Map<String, dynamic> toJson() => {
        if (voice != null) 'voice': voice,
        'rate': rate,
        'pitch': pitch,
      };
}

double _clamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);
