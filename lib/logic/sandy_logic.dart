/// Ported from `lib/sandy-logic.ts` (RN).
library;

/// Validates a `HH:mm` 24-hour medication time string.
bool isMedicationTime(String value) {
  final trimmed = value.trim();
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(trimmed);
  if (match == null) return false;
  final hours = int.tryParse(match.group(1)!);
  final minutes = int.tryParse(match.group(2)!);
  if (hours == null || minutes == null) return false;
  return hours >= 0 && hours <= 23 && minutes >= 0 && minutes <= 59;
}

/// Parses a `HH:mm` string into an (hour, minute) record — port of
/// `parseDailyTime` from `lib/medication-reminders.ts` (RN).
(int, int)? parseDailyTime(String time) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time.trim());
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return (hour, minute);
}

/// Local rule-based assistant replies (Arabic), ported from `sandyReply`.
/// In the standalone build the assistant chat is served by these local
/// answers instead of the old server's LLM endpoint.
String sandyReply(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('دواء') || lower.contains('جرعة')) {
    return 'يمكنك فتح تبويب «الأدوية» لتأكيد جرعتك أو إضافة موعد جديد. لا تغيّر جرعتك دون الرجوع إلى مختص.';
  }
  if (lower.contains('ضغط') || lower.contains('سكر') || lower.contains('نبض')) {
    return 'سجّل القياس كما يظهر في جهازك من تبويب «القياسات». إذا كانت النتيجة مقلقة أو ترافقها أعراض شديدة، تواصل مع مختص أو خدمات الطوارئ المحلية.';
  }
  if (lower.contains('تعب') || lower.contains('ألم')) {
    return 'أفهم أنك لا تشعر على ما يرام. لا أستطيع تقييم الأعراض طبيًا، لكن يمكن أن تساعدك مراجعة طبيب أو الاتصال بالطوارئ عند وجود أعراض شديدة أو مفاجئة.';
  }
  return 'شكرًا لمشاركتك. يمكنني مساعدتك في تنظيم الأدوية والقياسات واليوميات، أو تذكيرك بأن أي قرار علاجي يحتاج إلى مختص.';
}
