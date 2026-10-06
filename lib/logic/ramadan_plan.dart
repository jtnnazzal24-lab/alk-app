/// خطة رمضان الذكية — تنفيذ بند «1.2 وضع رمضان الذكي» من وثيقة التطوير.
///
/// اقتراحات محلية حسب فئة الدواء ووعيده: متى يُؤخذ مع السحور أو الإفطار،
/// ومتى يتطلّب قياس السكر استباقياً. لا تعدّل التطبيق أي جرعة من تلقائه.
library;

import '../models/sandy_data.dart';

/// اقتراح واحد في خطة رمضان.
class RamadanTip {
  const RamadanTip({
    required this.title,
    required this.detail,
    required this.severity,
  });

  final String title;
  final String detail;

  /// high | medium | low
  final String severity;
}

/// هل اسم الدواء يشير إلى أدوية ترفع خطر الهبوط قبل الإفطار؟
bool _isHypoglycemiaRisk(String name) {
  final n = name.toLowerCase();
  const keys = [
    'أنسولين', 'انسولين', 'لانتوس', 'ليفيمي', 'نوفورابيد',
    'جليمبيز', 'جلورين', 'جلاديج', 'جليبنكلاميد', 'جلوبورين',
    'insulin', 'lantus', 'levemir', 'glimepiride', 'glibenclamide',
    'glipizide',
  ];
  for (final k in keys) {
    if (n.contains(k)) return true;
  }
  return false;
}

bool _contains(String name, List<String> keys) {
  final n = name.toLowerCase();
  for (final k in keys) {
    if (n.contains(k.toLowerCase())) return true;
  }
  return false;
}

/// يبني خطة رمضان من قائمة أدوية المريض.
///
/// [suhoorTime] و[iftarTime] بصيغة `HH:mm` لعرض نافذة الخطر قبل الإفطار.
List<RamadanTip> buildRamadanPlan({
  required List<Medication> medications,
  String suhoorTime = '04:00',
  String iftarTime = '18:30',
}) {
  final tips = <RamadanTip>[];
  final hasRisk = medications.any((m) => _isHypoglycemiaRisk(m.name));
  final hasMetformin = medications
      .any((m) => _contains(m.name, ['ميتفورمين', 'جلوكوفاج', 'metformin']));
  final hasLevo = medications.any((m) =>
      _contains(m.name, ['ليفوثيروكسين', 'اليتروكس', 'levothyroxine']));
  final hasDiuretic = medications.any((m) => _contains(m.name, [
        'فوروسيميد', 'لاسكس', 'هيدروكلوروثيازيد', 'furosemide',
        'hydrochlorothiazide',
      ]));
  final hasPressure = medications
      .any((m) => m.category == MedicationCategory.pressure);

  if (hasRisk) {
    tips.add(const RamadanTip(
      severity: 'high',
      title: 'خطر هبوط السكر قبل الإفطار',
      detail:
          'مع أنسولين أو أدوية تُنزل السكر، قد ينخفض سكرك قبل نداء الأذان بساعة إلى ساعتين. '
          'اقطع الصيام بتمر وماء ثم قِس السكر بعد نصف ساعة.',
    ));
  }
  if (hasMetformin) {
    tips.add(const RamadanTip(
      severity: 'medium',
      title: 'الميتفورمين مع وجبة',
      detail:
          'تناوله مع الإفطار أو السحور مباشرة لتقليل الإسهال والغثيان، ولا تؤخره إلى منتصف الليل وحده.',
    ));
  }
  if (hasLevo) {
    tips.add(const RamadanTip(
      severity: 'high',
      title: 'الليفوثيروكسين في السحور',
      detail:
          'يحتاج معدة فارغة — أفضل توقيت أثناء الصيام قبل نومك بساعتين، لا بعد الإفطار مع الطعام.',
    ));
  }
  if (hasDiuretic) {
    tips.add(const RamadanTip(
      severity: 'medium',
      title: 'مدرات البول في السحور',
      detail:
          'تأخذها مع السحور في وقت مبكر فتفضّ الحاجة أثناء الليل، وتحافظ على نومك وسوائلك.',
    ));
  }
  if (hasPressure) {
    tips.add(const RamadanTip(
      severity: 'medium',
      title: 'أدوية الضغط والجفاف',
      detail:
          'قلّل المخللات والوجبات الجاهزة في السحور، واشرب ماءاً كافياً بين الإفطار ووقت النوم.',
    ));
  }

  tips.add(RamadanTip(
    severity: 'low',
    title: 'نافذة الإفطار الآمنة',
    detail:
        'الإفطار عند $iftarTime والسحور عند $suhoorTime — وزّع سوائلك بينهما بالتدريج بدل شرب كمية دفعة واحدة.',
  ));
  tips.add(const RamadanTip(
    severity: 'low',
    title: 'حركة بعد الإفطار',
    detail: 'مشي 15 دقيقة بعد ساعة من الإفطار يحسّن توازن السكر والضغط.',
  ));

  tips.sort((a, b) {
    int rank(String s) => s == 'high' ? 0 : (s == 'medium' ? 1 : 2);
    final r = rank(a.severity).compareTo(rank(b.severity));
    return r != 0 ? r : a.title.compareTo(b.title);
  });
  return tips;
}
