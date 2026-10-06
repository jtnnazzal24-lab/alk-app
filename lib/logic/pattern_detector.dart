/// كاشف الأنماط الصامتة في القياسات الحيوية.
///
/// تنفيذ بند وثيقة التطوير «3.1 كاشف الأنماط الصامتة»: إحصاء بسيط محلي
/// (متوسط + انحدار خطي) يكتشف دون إنترنت نمطاً متكرّراً في يوم معين،
/// واتجاه صاعداً/هابطاً في آخر القراءات، وانقطاعاً عن التسجيل.
///
/// لا يقدّم التطبيق تشخيصاً: النمط محفّز لزيارة الطبيب لا بديل عنه.
library;

import '../models/sandy_data.dart';

/// نوع النمط المكتشف.
class PatternKind {
  static const weekday = 'weekday';
  static const trend = 'trend';
  static const streak = 'streak';

  static String label(String v) {
    switch (v) {
      case weekday:
        return 'نمط أسبوعي';
      case trend:
        return 'اتجاه';
      case streak:
        return 'انتظام التسجيل';
      default:
        return 'تنبيه';
    }
  }
}

/// درجة أهمية النمط.
class PatternSeverity {
  static const high = 'high';
  static const medium = 'medium';
  static const low = 'low';

  static int rank(String v) {
    switch (v) {
      case high:
        return 0;
      case medium:
        return 1;
      default:
        return 2;
    }
  }
}

/// نمط مكتشف جاهز للعرض.
class VitalPattern {
  const VitalPattern({
    required this.kind,
    required this.severity,
    required this.title,
    required this.detail,
  });

  final String kind;
  final String severity;
  final String title;
  final String detail;
}

/// أسماء أيام الأسبوع بالعربية (index = DateTime.weekday - 1).
const List<String> arabicWeekdayNames = <String>[
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// تسمية نوع القياس بالعربية.
String vitalKindLabel(String kind) {
  switch (kind) {
    case VitalKind.pressure:
      return 'ضغط الدم';
    case VitalKind.sugar:
      return 'سكر الدم';
    case VitalKind.pulse:
      return 'النبض';
    case VitalKind.oxygen:
      return 'الأكسجين';
    default:
      return 'القياس';
  }
}

/// الفرق المعتبر (بالوحدة) لكل نوع قياس.
double vitalPatternThreshold(String kind) {
  switch (kind) {
    case VitalKind.pressure:
      return 10; // ملم زئبق
    case VitalKind.sugar:
      return 15; // mg/dL
    case VitalKind.oxygen:
      return 2; // %
    case VitalKind.pulse:
    default:
      return 10; // نبضة/دقيقة
  }
}

/// يستخرج قيمة عددية واحدة من نص القياس؛ الضغط «120/80» يعطي 120.
double? parseVitalNumber(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final first = RegExp(r'\d+(?:\.\d+)?').firstMatch(s);
  if (first == null) return null;
  return double.tryParse(first.group(0)!);
}

double _mean(List<double> v) {
  if (v.isEmpty) return 0;
  var acc = 0.0;
  for (final x in v) {
    acc += x;
  }
  return acc / v.length;
}

/// نمط اتجاه عبر انحدار خطي بسيط على آخر قراءات نوع معين.
///
/// [points] قيم مرتبة زمنياً من الأقدم للأحدث؛ يرجع `null` عند نقص العيّنات.
VitalPattern? trendPattern(String kind, List<(double, DateTime)> points) {
  if (points.length < 5) return null;
  final n = points.length;
  final ys = [for (final p in points) p.$1];
  final mx = (n - 1) / 2.0;
  final my = _mean(ys);
  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = i - mx;
    numerator += dx * (ys[i] - my);
    denominator += dx * dx;
  }
  if (denominator == 0) return null;
  final total = (numerator / denominator) * (n - 1);
  final threshold = vitalPatternThreshold(kind);
  if (total.abs() < threshold) return null;
  final label = vitalKindLabel(kind);
  final rising = total > 0;
  final days = points.last.$2.difference(points.first.$2).inDays;
  final window = days <= 0 ? '$n قياسات' : '$n قياسات خلال $days أيام';
  return VitalPattern(
    kind: PatternKind.trend,
    severity:
        total.abs() >= threshold * 2 ? PatternSeverity.high : PatternSeverity.medium,
    title: rising ? 'اتجاه $label صاعد' : 'اتجاه $label هابط',
    detail: rising
        ? 'ارتفع $label بنحو ${total.round()} خلال $window — راجع طبيبك إذا استمر النمط.'
        : 'انخفض $label بنحو ${total.abs().round()} خلال $window — استمر بقياسك المعتاد إن شعرت بدوخة.',
  );
}

/// أنماط الأيام: يقارن متوسط كل يوم أسبوع ببقية الأيام.
List<VitalPattern> weekdayPatterns(
  String kind,
  List<(double, DateTime)> points,
) {
  final out = <VitalPattern>[];
  if (points.length < 5) return out;
  final label = vitalKindLabel(kind);
  final threshold = vitalPatternThreshold(kind);
  final byWeekday = <int, List<double>>{};
  for (final p in points) {
    byWeekday.putIfAbsent(p.$2.weekday, () => <double>[]).add(p.$1);
  }
  for (final entry in byWeekday.entries) {
    final mine = entry.value;
    if (mine.length < 2) continue;
    final rest = <double>[
      for (final e in byWeekday.entries)
        if (e.key != entry.key) ...e.value,
    ];
    if (rest.length < 3) continue;
    final diff = _mean(mine) - _mean(rest);
    if (diff.abs() < threshold) continue;
    final day = arabicWeekdayNames[entry.key - 1];
    out.add(VitalPattern(
      kind: PatternKind.weekday,
      severity: diff.abs() >= threshold * 1.5
          ? PatternSeverity.high
          : PatternSeverity.medium,
      title: '$label أعلى يوم $day',
      detail: 'متوسط $label يوم $day ${diff > 0 ? 'أعلى' : 'أقل'} '
          'من بقية أيامك بمقدار ${diff.abs().round()} مقارنة بمتوسطك العام.',
    ));
  }
  return out;
}

/// انقطاع المريض عن تسجيل القياسات لعدة أيام.
VitalPattern? streakPattern(
  List<VitalReading> readings,
  DateTime now, {
  int silentDays = 3,
}) {
  if (readings.length < 3) return null;
  final dates = <DateTime>[];
  for (final r in readings) {
    final d = DateTime.tryParse(r.createdAt);
    if (d != null) dates.add(d);
  }
  if (dates.isEmpty) return null;
  dates.sort((a, b) => b.compareTo(a));
  final gap = now.difference(dates.first).inDays;
  if (gap < silentDays) return null;
  return VitalPattern(
    kind: PatternKind.streak,
    severity: PatternSeverity.low,
    title: 'انقطاع عن تسجيل القياسات',
    detail:
        'مرّت $gap يوماً دون قياس جديد — قياسك المنتظم هو ما يجعل الأنماط دقيقة.',
  );
}

/// يكتشف الأنماط الصامتة في كل أنواع القياسات.
///
/// [now] يُحقن في الاختبارات لضبط حساب الفواصل الزمنية.
List<VitalPattern> detectVitalPatterns(
  List<VitalReading> readings, {
  DateTime? now,
}) {
  if (readings.length < 3) return const <VitalPattern>[];
  final nowDt = now ?? DateTime.now();

  final byKind = <String, List<(double, DateTime)>>{};
  for (final r in readings) {
    final v = parseVitalNumber(r.value);
    final d = DateTime.tryParse(r.createdAt);
    if (v == null || d == null) continue;
    byKind.putIfAbsent(r.kind, () => <(double, DateTime)>[]).add((v, d));
  }
  if (byKind.isEmpty) return const <VitalPattern>[];

  final out = <VitalPattern>[];
  for (final entry in byKind.entries) {
    final pts = entry.value.toList()..sort((a, b) => a.$2.compareTo(b.$2));
    final trend = trendPattern(entry.key, pts);
    if (trend != null) out.add(trend);
    out.addAll(weekdayPatterns(entry.key, pts));
  }
  final streak = streakPattern(readings, nowDt);
  if (streak != null) out.add(streak);

  out.sort((a, b) => PatternSeverity.rank(a.severity)
      .compareTo(PatternSeverity.rank(b.severity)));
  final seen = <String>{};
  return out.where((e) => seen.add(e.title)).toList(growable: false);
}

