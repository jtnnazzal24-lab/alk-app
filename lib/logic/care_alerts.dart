/// تنبيهات الرعاية اليومية: المخزون، انتهاء الصلاحية، والفحوصات الدورية.
///
/// تنفيذ بندات وثيقة التطوير «16.3 تتبع المخزون»، «16.4 تذكير قبل
/// الفحوصات»، «16.5 تذكير بالتطعيمات»، و«16.6 تحذير انتهاء الصلاحية».
/// كل الحسابات محلية بلا شبكة.
library;

import '../models/sandy_data.dart';

/// صنف التنبيه.
class CareAlertKind {
  static const stock = 'stock';
  static const expiry = 'expiry';
  static const checkup = 'checkup';

  static String label(String v) {
    switch (v) {
      case stock:
        return 'المخزون';
      case expiry:
        return 'الصلاحية';
      case checkup:
        return 'فحص دوري';
      default:
        return 'تنبيه';
    }
  }
}

/// تنبيه رعاية جاهز للعرض.
class CareAlert {
  const CareAlert({
    required this.severity,
    required this.kind,
    required this.title,
    required this.detail,
  });

  /// high | medium | low
  final String severity;

  /// stock | expiry | checkup
  final String kind;
  final String title;
  final String detail;

  static int rank(String v) {
    switch (v) {
      case 'high':
        return 0;
      case 'medium':
        return 1;
      default:
        return 2;
    }
  }
}

void sortCareAlerts(List<CareAlert> list) {
  list.sort((a, b) {
    final r = CareAlert.rank(a.severity).compareTo(CareAlert.rank(b.severity));
    return r != 0 ? r : a.title.compareTo(b.title);
  });
}

/// تنبيهات المخزون، من حقول `stockRemaining` و`stockThreshold` في النموذج.
List<CareAlert> stockAlerts(List<Medication> medications) {
  final out = <CareAlert>[];
  for (final m in medications) {
    final remaining = m.stockRemaining;
    if (remaining == null) continue;
    final threshold = m.stockThreshold;
    if (remaining <= 0) {
      out.add(CareAlert(
        severity: 'high',
        kind: CareAlertKind.stock,
        title: 'نفد ${m.name}',
        detail:
            'لا توجد حبات متبقية — جدّد الوصفة من الطبيب أو الصيدلية قبل أن تنتهي.',
      ));
    } else if (threshold != null && remaining <= threshold) {
      out.add(CareAlert(
        severity: 'medium',
        kind: CareAlertKind.stock,
        title: 'بقيت ${m.name}',
        detail:
            'بقي ${remaining.round()} حبة فقط (حدّ التجديد ${threshold.round()}) — رتّب التجديد الآن.',
      ));
    }
  }
  sortCareAlerts(out);
  return out;
}

String formatDateShort(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// تحذير انتهاء الصلاحية قبل [horizonDays] يوماً أو بعد مضيّها.
List<CareAlert> expiryAlerts(
  List<Medication> medications, {
  DateTime? now,
  int horizonDays = 30,
}) {
  final nowDt = now ?? DateTime.now();
  final today = DateTime(nowDt.year, nowDt.month, nowDt.day);
  final out = <CareAlert>[];
  for (final m in medications) {
    final raw = (m.endDate ?? '').trim();
    if (raw.isEmpty) continue;
    final end = DateTime.tryParse(raw);
    if (end == null) continue;
    final days = end.difference(today).inDays;
    if (days < 0) {
      out.add(CareAlert(
        severity: 'high',
        kind: CareAlertKind.expiry,
        title: 'انتهت صلاحية ${m.name}',
        detail:
            'تجاوز تاريخ الانتهاء (${formatDateShort(end)}) — لا تتناول الدواء المتأخر.',
      ));
    } else if (days <= horizonDays) {
      out.add(CareAlert(
        severity: days <= 7 ? 'high' : 'medium',
        kind: CareAlertKind.expiry,
        title: 'قرب انتهاء ${m.name}',
        detail:
            'ينتهي بعد $days يوماً (${formatDateShort(end)}) — جدّده قبل النفاد.',
      ));
    }
  }
  sortCareAlerts(out);
  return out;
}

/// فحص دوري مطلوب مع دوريته بالأيام.
class CheckupItem {
  const CheckupItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.intervalDays,
  });

  final String id;
  final String title;
  final String detail;
  final int intervalDays;
}

/// الفحوصات الدورية المعتمدة على الحالة المرضية المسجَّلة.
///
/// تنفيذ بندَي «16.4 تذكير قبل الفحوصات» و«16.5 تذكير بالتطعيمات».
List<CheckupItem> standardCheckups(String condition) {
  final c = condition.toLowerCase();
  final diabetes = c.contains('سكري') || c.contains('diabet');
  final pressure = c.contains('ضغط') || c.contains('hypert');
  final kidney = c.contains('كلى') || c.contains('renal');
  final items = <CheckupItem>[
    const CheckupItem(
      id: 'flu-vaccine',
      title: 'تطعيم الإنفلونزا',
      detail: 'جرعة سنوية — الأفضل أواخر الخريف قبل موسم البرد.',
      intervalDays: 365,
    ),
  ];
  if (diabetes || pressure) {
    items.add(const CheckupItem(
      id: 'hba1c',
      title: 'تحليل السكر التراكمي (HbA1c)',
      detail: 'يقيس متوسط سكر آخر 3 أشهر — الهدف أقل من 7% غالباً.',
      intervalDays: 91,
    ));
    items.add(const CheckupItem(
      id: 'eye-exam',
      title: 'فحص العين السنوي',
      detail: 'كشف تدهور الشبكية مبكراً قبل أن يؤثر على البصر.',
      intervalDays: 365,
    ));
    items.add(const CheckupItem(
      id: 'lipid-panel',
      title: 'تحليل الكوليسترول والدهون الثلاثية',
      detail: 'للتأكد من أثر الدواء على دهونك — سنوياً.',
      intervalDays: 365,
    ));
  }
  if (diabetes || pressure || kidney) {
    items.add(const CheckupItem(
      id: 'kidney-function',
      title: 'فحص وظائف الكلى',
      detail: 'كرياتينين وألبومين في البول — سنوياً أو حسب تعليمات الطبيب.',
      intervalDays: 365,
    ));
  }
  return items;
}

/// الفحوصات المستحقة الآن.
///
/// [lastDone] تاريخ آخر إنجاز لكل فحص بصيغة ISO (`{id: 'YYYY-MM-DD'}`).
List<CareAlert> dueCheckups({
  required String condition,
  required Map<String, String> lastDone,
  DateTime? now,
}) {
  final nowDt = now ?? DateTime.now();
  final today = DateTime(nowDt.year, nowDt.month, nowDt.day);
  final out = <CareAlert>[];
  for (final item in standardCheckups(condition)) {
    final raw = (lastDone[item.id] ?? '').trim();
    final base = raw.isEmpty ? null : DateTime.tryParse(raw);
    if (base == null) {
      out.add(CareAlert(
        severity: 'low',
        kind: CareAlertKind.checkup,
        title: item.title,
        detail: '${item.detail} لم تسجّل إنجازه بعد — حدّد موعداً مع طبيبك.',
      ));
      continue;
    }
    final days = base
        .add(Duration(days: item.intervalDays))
        .difference(today)
        .inDays;
    if (days > 0) continue;
    out.add(CareAlert(
      severity: days <= -30 ? 'high' : 'medium',
      kind: CareAlertKind.checkup,
      title: 'حان موعد ${item.title}',
      detail: '${item.detail} متأخر ${-days} يوماً عن موعده.',
    ));
  }
  sortCareAlerts(out);
  return out;
}

