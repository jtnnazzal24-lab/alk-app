import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../models/sandy_data.dart';
import '../state/sandy_store.dart';

/// Builds a structured health report text from the local data and delivers it
/// to the treating doctor via WhatsApp, email, or the system share sheet.
class DoctorReportService {
  const DoctorReportService();

  static const _vitalLabels = <String, String>{
    VitalKind.pressure: 'ضغط الدم',
    VitalKind.sugar: 'سكر الدم',
    VitalKind.pulse: 'النبض',
    VitalKind.oxygen: 'الأكسجين',
  };

  static const _doseTypeLabels = <String, String>{
    DoseEventType.taken: 'تم تناولها',
    DoseEventType.missed: 'فائتة',
    DoseEventType.asNeeded: 'عند الحاجة',
  };

  /// Normalizes a phone number to the international format required by
  /// `wa.me` (digits only). Keeps existing country codes and assumes local
  /// numbers starting with 0 need no rewrite (doctor must save the number in
  /// international format for reliable delivery).
  static String normalizePhone(String raw) =>
      raw.replaceAll(RegExp(r'[^\d]'), '');

  /// Builds the full report text from the store data.
  String buildReportText(SandyStore store) {
    final patient = store.patient;
    final medications = store.medications;
    final vitals = store.vitals;
    final missed = store.missedDoseEvents;
    final now = DateTime.now();

    final buffer = StringBuffer()
      ..writeln('📋 تقرير صحي — تطبيق ALK'.tr)
      ..writeln('تاريخ التقرير: ${_formatDate(now.toIso8601String())}'.tr)
      ..writeln('━━━━━━━━━━━━━━━━━━━━');

    // Patient identity.
    buffer
      ..writeln()
      ..writeln('👤 بيانات المريض:'.tr);
    if (patient.fullName.isNotEmpty) {
      buffer.writeln('• الاسم: ${patient.fullName}'.tr);
    }
    if (patient.identityNumber.isNotEmpty) {
      buffer.writeln('• رقم الهوية: ${patient.identityNumber}'.tr);
    }
    if (patient.conditionName.isNotEmpty) {
      buffer.writeln('• الحالة المرضية: ${patient.conditionName}'.tr);
    }
    if (patient.nextReviewDate.isNotEmpty) {
      buffer.writeln('• موعد المراجعة القادم: ${patient.nextReviewDate}'.tr);
    }

    // Adherence.
    final taken = medications.where((m) => m.taken).length;
    final rate =
        medications.isEmpty ? 0 : (taken / medications.length * 100).round();
    buffer
      ..writeln()
      ..writeln('💊 التزام الأدوية اليوم: $rate%'.tr)
      ..writeln('• $taken من ${medications.length} جرعات مؤكدة'.tr);

    // Current medications.
    if (medications.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('💊 الأدوية الحالية:'.tr);
      for (final med in medications) {
        final times = med.doseTimes.isNotEmpty
            ? med.doseTimes.join('، ')
            : med.time;
        final dose = (med.dose?.isNotEmpty ?? false) ? ' — ${med.dose}' : '';
        final status = med.asNeeded
            ? 'عند الحاجة'.tr
            : (med.taken ? '✔ مؤكدة اليوم'.tr : '—');
        buffer.writeln('• ${med.name}$dose — المواعيد: $times — $status'.tr);
      }
    }

    // Recent missed doses.
    if (missed.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('⚠️ آخر الجرعات (${missed.length} آخر حدث):'.tr);
      for (final event in missed.take(10)) {
        final type = (_doseTypeLabels[event.type] ?? event.type).tr;
        buffer.writeln(
            '• ${event.medicationName}: $type — ${_formatDate(event.createdAt)}'
                .tr);
      }
    }

    // Recent vitals.
    if (vitals.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('🩺 آخر القياسات:'.tr);
      for (final v in vitals.take(10)) {
        final kind = (_vitalLabels[v.kind] ?? v.kind).tr;
        buffer.writeln(
            '• $kind: ${v.displayValue} — ${_formatDate(v.createdAt)}'.tr);
      }
    }

    // Doctor notes.
    if (patient.doctorNotes.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('📝 ملاحظات الطبيب:'.tr)
        ..writeln(patient.doctorNotes);
    }

    buffer
      ..writeln()
      ..writeln('━━━━━━━━━━━━━━━━━━━━')
      ..writeln('هذا التقرير ملخص تنظيمي لبيانات أدخلها المريض في تطبيق ALK،'.tr)
      ..writeln('ولا يفسر القياسات ولا يقدم تشخيصًا طبيًا.'.tr);

    return buffer.toString().trim();
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '—';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  /// Sends the report text to the doctor's WhatsApp number.
  /// Returns false when the number is missing or WhatsApp cannot open.
  ///
  /// FIX: never gates on `canLaunchUrl` — on Android 11+ it returns false for
  /// https links without `<queries>` package visibility, silently doing
  /// nothing. Launch directly with a direct app-scheme fallback.
  Future<bool> sendViaWhatsApp(String rawPhone, String reportText) async {
    final phone = normalizePhone(rawPhone);
    if (phone.isEmpty) return false;
    final encoded = Uri.encodeComponent(reportText);
    final uri = Uri.parse('https://wa.me/$phone?text=$encoded');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return true;
    } catch (_) {
      // Fall through to the direct app-scheme attempt.
    }
    try {
      final appUri =
          Uri.parse('whatsapp://send?phone=$phone&text=$encoded');
      return await launchUrl(appUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Sends the report text to the doctor's email address via the default
  /// mail app. Returns false when the address is missing or mail cannot open.
  Future<bool> sendViaEmail(String rawEmail, String reportText) async {
    final email = rawEmail.trim();
    if (email.isEmpty || !email.contains('@')) return false;
    final uri = Uri.parse(
      'mailto:$email?subject=${Uri.encodeComponent('تقرير صحي — ALK'.tr)}'
      '&body=${Uri.encodeComponent(reportText)}',
    );
    try {
      // FIX: launch directly — `canLaunchUrl` is unreliable for mailto on
      // Android 11+ (package visibility).
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  /// Opens the system share sheet so the user can pick any other channel
  /// (Telegram, SMS, saving as file, ...).
  Future<void> shareReport(String reportText) async {
    await Share.share(reportText, subject: 'تقرير صحي — ALK'.tr);
  }
}