/// Spoken-intent parser for the ALK voice assistant (pure logic, testable).
///
/// Understands Arabic (and digits) commands such as:
///  - "سجل سكر ١٤٠" / "ضغط 120 على 80" / "نبضي 90"
///  - "أكلت تفاحة" / "تناولت خبز" (food logging)
///  - "أضف دواء أسبيرين الساعة 8"
///  - "افتح القياسات / الأدوية / التغذية / اليوميات / التقارير / المحادثة"
library;

import '../l10n/app_strings.dart';

/// Screen identifiers the assistant can navigate to.
abstract final class VoiceScreens {
  static const home = 'home';
  static const vitals = 'vitals';
  static const medications = 'medications';
  static const nutrition = 'nutrition';
  static const journals = 'journals';
  static const reports = 'reports';
  static const chat = 'chat';
  static const more = 'more';
}

/// أسماء الشاشات بلغة الواجهة.
String screenLabel(String screen) => switch (screen) {
      VoiceScreens.home => 'الرئيسية'.tr,
      VoiceScreens.vitals => 'القياسات'.tr,
      VoiceScreens.medications => 'الأدوية'.tr,
      VoiceScreens.nutrition => 'التغذية'.tr,
      VoiceScreens.journals => 'اليوميات'.tr,
      VoiceScreens.reports => 'التقارير'.tr,
      VoiceScreens.chat => 'المحادثة'.tr,
      VoiceScreens.more => 'المزيد'.tr,
      _ => screen,
    };

/// أسماء أنواع القياسات بلغة الواجهة.
String vitalLabel(String kind) => switch (kind) {
      'sugar' => 'السكر'.tr,
      'pressure' => 'الضغط'.tr,
      'pulse' => 'النبض'.tr,
      _ => kind,
    };

/// Parsed voice intents.
sealed class VoiceIntent {}

class VoiceOpenScreen extends VoiceIntent {
  final String screen;
  VoiceOpenScreen(this.screen);
}

class VoiceAddVital extends VoiceIntent {
  final String kind; // sugar | pressure | pulse
  final String value;
  VoiceAddVital(this.kind, this.value);
}

class VoiceAddFood extends VoiceIntent {
  final String name;
  final String mealType;
  VoiceAddFood(this.name, {this.mealType = 'وجبة'});
}

class VoiceAddMedication extends VoiceIntent {
  final String name;
  final String time;
  VoiceAddMedication(this.name, this.time);
}

class VoiceGreeting extends VoiceIntent {}

class VoiceUnknown extends VoiceIntent {
  final String text;
  VoiceUnknown(this.text);
}

/// "اتصل بـ فلان" — call an emergency contact by name.
class VoiceCallContact extends VoiceIntent {
  final String name;
  VoiceCallContact(this.name);
}

/// "طوارئ" / "اسعاف" — call the ambulance hotline.
class VoiceCallAmbulance extends VoiceIntent {}

/// Converts Arabic-Indic digits (٠١٢…) into western digits.
String normalizeDigits(String input) => input.replaceAllMapped(
      RegExp('[\u0660-\u0669]'),
      (m) =>
          String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0660 + 0x30),
    );

final RegExp _digitRun = RegExp('[0-9\u0660-\u0669]+');

List<String> _numbers(String text) => _digitRun
    .allMatches(text)
    .map((m) => normalizeDigits(m[0]!))
    .toList();

/// Parses spoken [text] into a [VoiceIntent].
VoiceIntent parseVoiceIntent(String rawText) {
  final text = normalizeDigits(rawText.trim());
  if (text.isEmpty) return VoiceUnknown(rawText);

  // --- Emergency calls (must run before other matchers) ----------------------
  if (RegExp('طوارئ|طوارى|اسعاف|إسعاف|نجدة').hasMatch(text)) {
    return VoiceCallAmbulance();
  }
  final callMatch = RegExp(
    r'(?:اتصل|إتصل|اتّصل|دي|ناد)\s*(?:على|إلى|الى)?\s*'
    r'([أ-ي\u064B-\u0652]+(?:\s[أ-ي\u064B-\u0652]+)?)',
  ).firstMatch(text);
  if (callMatch != null) {
    // Strip leftover preposition particles like "ب" / "بـ".
    final name = callMatch
        .group(1)!
        .replaceAll(RegExp(r'^[بل]+\s*ـ*\s*'), '')
        .replaceAll('ـ', '')
        .trim();
    if (name.isNotEmpty) return VoiceCallContact(name);
  }

  // --- Navigation -----------------------------------------------------------
  if (RegExp('افتح|فتح|اذهب|روح|اعرض').hasMatch(text)) {
    if (RegExp('قياس|مؤشر|الضغط|السكر|النبض').hasMatch(text)) {
      return VoiceOpenScreen(VoiceScreens.vitals);
    }
    if (RegExp('دواء|أدوية|ادوية|دوائي|أدويتي|ادويتي|علاج|جرعة').hasMatch(text)) {
      return VoiceOpenScreen(VoiceScreens.medications);
    }
    if (RegExp('طعام|اكل|أكل|وجب|تغذية|غذا').hasMatch(text)) {
      return VoiceOpenScreen(VoiceScreens.nutrition);
    }
    if (RegExp('يومي|مذك|مشاعر').hasMatch(text)) {
      return VoiceOpenScreen(VoiceScreens.journals);
    }
    if (RegExp('تقرير').hasMatch(text)) {
      return VoiceOpenScreen(VoiceScreens.reports);
    }
    if (RegExp('محادث|دردش|مساعد').hasMatch(text)) {
      return VoiceOpenScreen(VoiceScreens.chat);
    }
    if (RegExp('اعداد|إعدادات|المزيد').hasMatch(text)) {
      return VoiceOpenScreen(VoiceScreens.more);
    }
  }

  // --- Greeting -------------------------------------------------------------
  if (RegExp('^مرحبا|^مرحبًا|^اهلا|^أهلا|^السلام|^هاي|^هلا').hasMatch(text)) {
    return VoiceGreeting();
  }

  // --- Vitals ---------------------------------------------------------------
  final sugar = RegExp('سكر|غلوكوز|جلوكوز').hasMatch(text);
  final pressure = RegExp('ضغط').hasMatch(text);
  final pulse = RegExp('نبض|ضربات').hasMatch(text);
  if (sugar || pressure || pulse) {
    final nums = _numbers(text);
    if (pressure && nums.length >= 2) {
      // "120 على 80" → "120/80".
      return VoiceAddVital('pressure', '${nums[0]}/${nums[1]}');
    }
    if (nums.isNotEmpty) {
      final kind = sugar ? 'sugar' : (pressure ? 'pressure' : 'pulse');
      return VoiceAddVital(kind, nums.first);
    }
  }

  // --- Medication -----------------------------------------------------------
  if (RegExp('دواء|علاج').hasMatch(text)) {
    final nameMatch = RegExp(
      r'(?:دواء|علاج)\s+([\u0600-\u06FF]+(?:\s[\u0600-\u06FF]+)?)',
    ).firstMatch(text);
    final name = nameMatch?.group(1) ?? '';
    final timeMatch = RegExp(
      r'(?:الساعة|ساعة|عند)\s*([0-9]+(?:\.[0-9]+)?)',
    ).firstMatch(text);
    if (name.isNotEmpty) {
      // The greedy capture may swallow "الساعة..." — strip it.
      final cleanName = name
          .replaceAll(RegExp(r'\s*(?:الساعة|ساعة|عند)\s*.*$'), '')
          .trim();
      final time =
          timeMatch == null ? '08:00' : _formatHour(timeMatch.group(1)!);
      return VoiceAddMedication(cleanName, time);
    }
  }

  // --- Food -----------------------------------------------------------------
  final foodMatch = RegExp(
    r'(?:اكلت|أكلت|تناولت|شربت|سجل وجبة|اضف وجبة)\s+(.+)',
  ).firstMatch(text);
  if (foodMatch != null) {
    final rest = foodMatch
        .group(1)!
        .replaceAll(RegExp(r'\s*(?:اليوم|الان|الآن|صباحا|مساء)$'), '')
        .replaceAll(RegExp(r'[.،,!?؟]$'), '')
        .trim();
    if (rest.isNotEmpty) {
      String mealType = 'وجبة';
      if (RegExp('فطور').hasMatch(text)) mealType = 'فطور';
      if (RegExp('غداء').hasMatch(text)) mealType = 'غداء';
      if (RegExp('عشاء').hasMatch(text)) mealType = 'عشاء';
      if (RegExp('خفيف|سناك').hasMatch(text)) mealType = 'وجبة خفيفة';
      return VoiceAddFood(rest, mealType: mealType);
    }
  }

  return VoiceUnknown(rawText);
}

/// Formats a spoken hour ("8", "8.5", "20") into HH:mm.
String _formatHour(String raw) {
  final value = double.tryParse(raw);
  if (value == null) return '08:00';
  final hour = value.floor().clamp(0, 23);
  final minutes = ((value - value.floor()) * 60).round().clamp(0, 59);
  final hh = hour.toString().padLeft(2, '0');
  final mm = minutes.toString().padLeft(2, '0');
  return '$hh:$mm';
}
