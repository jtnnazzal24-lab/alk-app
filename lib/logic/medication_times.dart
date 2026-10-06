/// Ported from `lib/medication-times.ts` (RN).
library;

import 'sandy_logic.dart';
import '../models/sandy_data.dart';

/// Deduplicates + validates + sorts dose times (`HH:mm`).
List<String> normalizeMedicationTimes(Iterable<String> times) {
  final valid = times.map((t) => t.trim()).where(isMedicationTime).toSet();
  final list = valid.toList()..sort((a, b) => a.compareTo(b));
  return list;
}

bool areMedicationTimesValid(Iterable<String> times) {
  final list = times.toList();
  return list.isNotEmpty && list.every(isMedicationTime);
}

/// Dose times of a medication, falling back to its primary `time` field —
/// identical fallback semantics to the RN `getMedicationDoseTimes`.
List<String> getMedicationDoseTimes(Medication medication) {
  final times = normalizeMedicationTimes(medication.doseTimes);
  if (times.isNotEmpty) return times;
  return normalizeMedicationTimes([medication.time]);
}

/// Arabic-joined label for a medication's dose times.
String medicationTimesLabel(Medication medication) {
  return getMedicationDoseTimes(medication).join('، ');
}

/// أقرب موعد جرعة قادم لأدوية التذكير (من [now]) — يُستخدم لنطق التذكير في
/// وقته عندما يكون التطبيق مفتوحاً، حيث لا يكفي الإشعار وحده.
///
/// يتجاهل الأدوية بلا تذكير والأدوية «حسب الحاجة»، ويعيد غداً لأي موعد مضى.
({DateTime at, Medication medication})? nextDoseOccurrence(
  Iterable<Medication> medications,
  DateTime now,
) {
  ({DateTime at, Medication medication})? best;
  for (final medication in medications) {
    if (!medication.reminderEnabled || medication.asNeeded) continue;
    for (final time in getMedicationDoseTimes(medication)) {
      final parts = time.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      var at = DateTime(now.year, now.month, now.day, hour, minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      if (best == null || at.isBefore(best.at)) {
        best = (at: at, medication: medication);
      }
    }
  }
  return best;
}

/// أقرب موعد «اقترب موعد دوائك» قادم (من [now]) — يؤتيه بـ[preLeadMinutes]
/// قبل موعد الجرعة. يُستخدم لنطق تنبيه مسبق للتطبيق المفتوح.
///
/// يتجاهل الأدوية بلا تذكير والأدوية «حسب الحاجة»، ويعيد غداً لأي موعد مضى.
/// إذا كان الوقت الحالي أقرب إلى موعد الجرعة الأصلي من
/// [preLeadMinutes]، يُعيد موعداً غير آتٍ (null) — فالتنبيه المسبق
/// لم يعد مرتاحاً لهذا الموعد.
({DateTime at, Medication medication})? nextPreDoseOccurrence(
  Iterable<Medication> medications,
  DateTime now, {
  int preLeadMinutes = 15,
}) {
  ({DateTime at, Medication medication})? best;
  for (final medication in medications) {
    if (!medication.reminderEnabled || medication.asNeeded) continue;
    for (final time in getMedicationDoseTimes(medication)) {
      final parts = time.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      var at = DateTime(now.year, now.month, now.day, hour, minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      // نأخر [preLeadMinutes] قبل الجرعة — لكن لا نُعيد موعداً
      // ماضياً إذا كان الآن أقرب إلى الجرعة الأصلية.
      final preAt = at.subtract(Duration(minutes: preLeadMinutes));
      if (!preAt.isAfter(now)) continue;
      if (best == null || preAt.isBefore(best.at)) {
        best = (at: preAt, medication: medication);
      }
    }
  }
  return best;
}
