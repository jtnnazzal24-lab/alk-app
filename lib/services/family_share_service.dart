/// مشاركة عائلية عبر واتساب/نظام المشاركة — تنفيذ بنود وثيقة التطوير
/// «2.1 حلقة الرعاية»، «2.2 زر أنا بخير»، «2.3 وصية صحية»، و«15.4 تقرير
/// للعائلة». لا خادم ولا حساب: كل شيء يُرسل يدوياً بضغطة.
library;

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sandy_data.dart';
import '../state/sandy_store.dart';

class FamilyShareService {
  const FamilyShareService();

  static const _vitalLabels = <String, String>{
    VitalKind.pressure: 'ضغط الدم',
    VitalKind.sugar: 'سكر الدم',
    VitalKind.pulse: 'النبض',
    VitalKind.oxygen: 'الأكسجين',
  };

  String _date(String iso) {
    if (iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// نسبة تناول الجرعات من الأدوية المسجَّلة (0–100).
  int adherenceRate(SandyStore store) {
    final meds = store.medications;
    if (meds.isEmpty) return 0;
    final taken = meds.where((m) => m.taken).length;
    return (taken / meds.length * 100).round();
  }

  /// رسالة «أنا بخير» اليومية (البند 2.2).
  String buildIamFineMessage(SandyStore store) {
    final name = store.patient.fullName.trim();
    final who = name.isEmpty ? 'أنا' : name;
    final meds = store.medications;
    final taken = meds.where((m) => m.taken).length;
    final rate = adherenceRate(store);
    return '❤️ $who بخير اليوم — التزام الأدوية $rate% '
        '($taken من ${meds.length} جرعة مؤكدة).';
  }

  /// ملخص أسبوعي للعائلة (البند 15.4) — بلا تفاصيل طبية حسّاسة.
  String buildFamilyReport(SandyStore store) {
    final patient = store.patient;
    final meds = store.medications;
    final b = StringBuffer()
      ..writeln('📋 تقرير العائلة — تطبيق ALK')
      ..writeln('التاريخ: ${_date(DateTime.now().toIso8601String())}')
      ..writeln('━━━━━━━━━━━━━━━━━━━━');

    if (patient.fullName.trim().isNotEmpty) {
      b.writeln('الاسم: ${patient.fullName.trim()}');
    }
    b
      ..writeln('التزام الأدوية اليوم: ${adherenceRate(store)}%')
      ..writeln('عدد الأدوية: ${meds.length}');

    final missed = store.missedDoseEvents.take(5).toList();
    if (missed.isEmpty) {
      b.writeln('لا توجد جرعات فائتة مسجَّلة مؤخراً ✅');
    } else {
      b.writeln('آخر الجرعات الفائتة: ${missed.length}');
    }

    final latest = <String, VitalReading>{};
    for (final v in store.vitals) {
      latest.putIfAbsent(v.kind, () => v);
    }
    if (latest.isNotEmpty) {
      b.writeln('آخر القياسات:');
      latest.forEach((kind, v) {
        final label = _vitalLabels[kind] ?? 'القياس';
        b.writeln('• $label: ${v.displayValue} — ${_date(v.createdAt)}');
      });
    }

    if (store.lastMood.isNotEmpty) {
      b.writeln('المزاج الأخير: ${store.lastMood}');
    }
    b
      ..writeln('━━━━━━━━━━━━━━━━━━━━')
      ..writeln('هذا ملخص لإدخال المريض نفسه — لا يُغني عن رأي الطبيب.');
    return b.toString().trim();
  }

  /// بطاقة الطوارئ (البند 2.3 / 6.2): تُشارَك حتى يقرأها المسعف.
  String buildEmergencyCard(SandyStore store) {
    final p = store.patient;
    final b = StringBuffer()..writeln('🩺 بطاقة طوارئ — ALK');
    b.writeln('━━━━━━━━━━━━━━━━━━━━');
    b.writeln('الاسم: ${p.fullName.trim().isEmpty ? 'غير محدد' : p.fullName.trim()}');
    if (p.bloodType.trim().isNotEmpty) b.writeln('فصيلة الدم: ${p.bloodType.trim()}');
    if (p.conditionName.trim().isNotEmpty) {
      b.writeln('الحالة المرضية: ${p.conditionName.trim()}');
    }
    if (p.allergies.trim().isNotEmpty) {
      b.writeln('الحساسيات: ${p.allergies.trim()}');
    }

    final meds = store.medications;
    if (meds.isNotEmpty) {
      b.writeln('الأدوية الحالية:');
      for (final m in meds) {
        final dose = (m.dose?.isNotEmpty ?? false) ? ' — ${m.dose}' : '';
        b.writeln('• ${m.name}$dose');
      }
    }

    final contacts = store.emergencyContacts;
    if (contacts.isNotEmpty) {
      b.writeln('جهات الاتصال:');
      for (final c in contacts) {
        b.writeln('• ${c.name}: ${c.phone}');
      }
    }
    if (store.ambulanceNumber.trim().isNotEmpty) {
      b.writeln('رقم الإسعاف المحلي: ${store.ambulanceNumber.trim()}');
    }
    b
      ..writeln('━━━━━━━━━━━━━━━━━━━━')
      ..writeln('بيانات يدخلها المريض في تطبيق ALK — إرشادية وليس تشخيصاً.');
    return b.toString().trim();
  }

  /// يفتح واتساب بنص جاهز. يرجع `false` عند فشل الفتح.
  Future<bool> sendViaWhatsApp(String rawPhone, String text) async {
    final phone = rawPhone.replaceAll(RegExp(r'[^\d]'), '');
    if (phone.isEmpty) return false;
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse('https://wa.me/$phone?text=$encoded');
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // fallback below
    }
    try {
      return await launchUrl(
        Uri.parse('whatsapp://send?phone=$phone&text=$encoded'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// يفتح نافذة المشاركة العامة (واتساب، الرسائل، حفظ ملف...).
  Future<void> shareText(String text, {String subject = ''}) async {
    await Share.share(text, subject: subject);
  }
}
