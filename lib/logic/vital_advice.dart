/// مُفسِّر القراءات الحيوية — يحوّل رقم القراءة (ضغط / سكر / نبض / أكسجين)
/// إلى نتيجة مفهومة لكبار السن مع توجيه عملي فوري.
///
/// المستويات (من الأفضل إلى الأسوأ):
///  - [VitalLevel.normal]      طبيعي — استمر على نظامك.
///  - [VitalLevel.borderline]  مقبول لكنه يحتاج انتباهاً — أعد القياس وراقب.
///  - [VitalLevel.abnormal]    غير مقبول — راجع طبيبك مع نصيحة رياضة/أكل.
///  - [VitalLevel.emergency]   خطر عاجل — اتصل بالإسعاف الآن.
///  - [VitalLevel.unknown]     لا يمكن تفسير النص — أعد القياس.
///
/// العتبات مرجعية عامة لكبار السن وليست تشخيصاً طبياً؛ تُعرض دائماً في
/// الواجهة مع تنويه «إرشاد تثقيفي فقط — راجع طبيبك». منطق نقي بلا أي
/// اعتماد على Flutter ليُختبر بسهولة (انظر `test/logic/vital_advice_test.dart`).
library;

import '../models/sandy_data.dart';
import 'food_advice.dart';
import 'vital_quality.dart';

/// مستوى نتيجة التفسير — يُستخدم لونه في الواجهة وإشعار النظام.
class VitalLevel {
  static const normal = 'normal';
  static const borderline = 'borderline';
  static const abnormal = 'abnormal';
  static const emergency = 'emergency';
  static const unknown = 'unknown';

  /// تسمية عربية مختصرة تُعرض كشارة ملوّنة.
  static String label(String level) {
    switch (level) {
      case normal:
        return 'طبيعية';
      case borderline:
        return 'تحتاج انتباهاً';
      case abnormal:
        return 'غير مقبولة';
      case emergency:
        return 'خطر عاجل';
      default:
        return 'غير مفهومة';
    }
  }
}

/// حدود التفسير (مرجعية عامة لكبار السن، قابلة للتعديل لاحقاً).
///
/// الوحدات: الضغط mmHg، السكر mg/dL، النبض نبضة/دقيقة، الأكسجين %.
abstract final class VitalThresholds {
  // ---- ضغط الدم (طبيعي <120/80، مرتفع ≥140/90، أزمة ≥180/120، منخفض <90/60).
  static const pressureNormalSystolic = 120;
  static const pressureNormalDiastolic = 80;
  static const pressureHighSystolic = 140;
  static const pressureHighDiastolic = 90;
  static const pressureEmergencySystolic = 180;
  static const pressureEmergencyDiastolic = 120;
  static const pressureLowSystolic = 90;
  static const pressureLowDiastolic = 60;

  // ---- السكر حسب سياق القياس (صائم / بعد الأكل بساعتين / عشوائي).
  static const sugarNormalFasting = 100;
  static const sugarNormalNonFasting = 140;
  static const sugarAbnormalFasting = 126;
  static const sugarAbnormalAfterMeal = 180;
  static const sugarAbnormalRandom = 181;
  static const sugarEmergency = 250; // خطر حماض/جفاف شديد.
  static const sugarLow = 70; // هبوط.
  static const sugarLowSevere = 54; // هبوط خطير.

  // ---- الأكسجين المشبّع (طبيعي ≥95، 93-94 حدي، 90-92 منخفض، <90 خطر).
  static const oxygenNormal = 95;
  static const oxygenBorderline = 93;
  static const oxygenLow = 90;

  // ---- النبض (طبيعي 60-100، حدي 50-59 و101-110، خطر <40 أو >130).
  static const pulseNormalMin = 60;
  static const pulseNormalMax = 101; // حتى 100.
  static const pulseBorderlineMin = 50;
  static const pulseBorderlineMax = 111; // حتى 110.
  static const pulseAbnormalMin = 40;
  static const pulseAbnormalMax = 131; // حتى 130.
}


/// سياق قياس السكر — يُستخرج من نص القراءة نفسها حفاظاً على مخطط JSON
/// الموحّد مع تطبيق React Native (الحقل `value` نص حر مثل «160 بعد الأكل»).
class SugarContext {
  static const fasting = 'fasting'; // صائم
  static const afterMeal = 'afterMeal'; // بعد الأكل بساعتين
  static const random = 'random'; // عشوائي/جهاز

  /// يكتشف السياق من نص القراءة (كلمات عربية اختيارية بعد الرقم).
  static String of(String value) {
    if (value.contains('صائم')) return fasting;
    if (value.contains('بعد الأكل') || value.contains('بعد وجبة')) {
      return afterMeal;
    }
    return random;
  }

  /// لافقة تُضاف للقراءة عند الإدخال اليدوي (مثل «160 بعد الأكل»).
  static String suffix(String context) {
    switch (context) {
      case fasting:
        return ' صائم';
      case afterMeal:
        return ' بعد الأكل';
      default:
        return '';
    }
  }

  static String label(String context) {
    switch (context) {
      case fasting:
        return 'صائم';
      case afterMeal:
        return 'بعد الأكل';
      default:
        return 'عشوائي';
    }
  }
}

/// تسمية عربية لنوع القياس (تُستخدم في القوائم والإشعارات).
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
      return kind;
  }
}

/// نتيجة تفسير قراءة واحدة.
class VitalAdvice {
  final String kind;
  final String value;
  final String level; // راجع [VitalLevel]
  final String title;
  final String message;

  /// تمارين مقترحة (فارغة في الخطر أو عند منع الجهد).
  final List<String> exercises;

  /// نصائح غذائية مرتبطة بنوع القياس (food_advice.dart).
  final List<String> foods;

  /// ملاحظة مخصصة حسب الحالة المزمنة (سكري/ضغط/قلب) أو ''.
  final String conditionNote;

  /// مفتاح التأثر الغذائي (FoodImpactKind) لفتح شاشة التغذية أو ''.
  final String impactKind;

  const VitalAdvice({
    required this.kind,
    required this.value,
    required this.level,
    required this.title,
    required this.message,
    this.exercises = const [],
    this.foods = const [],
    this.conditionNote = '',
    this.impactKind = '',
  });

  /// يحتاج زيارة/استشارة الطبيب (غير مقبول أو خطر).
  bool get needsDoctor =>
      level == VitalLevel.abnormal || level == VitalLevel.emergency;

  /// خطر عاجل يتطلب اتصالاً فورياً بالإسعاف.
  bool get emergency => level == VitalLevel.emergency;

  /// نص موحّد يُقرأ للمريض بصوت بطيء (زر السماعة / ضغط الإشعار).
  String get spokenText {
    final buffer = StringBuffer('$title. $message');
    if (conditionNote.isNotEmpty) buffer.write(' $conditionNote');
    return buffer.toString();
  }
}

// ---------------------------------------------------------------------------
// واجهة التفسير العامة
// ---------------------------------------------------------------------------

/// يفسّر قياساً حسب نوعه ونص قراءته.
///
/// [conditionName] اسم الحالة المزمنة للمريض (سكري/ضغط/قلب…) لتُضاف ملاحظة
/// مخصصة عند الحاجة. لا يرمي استثناءات أبداً — القراءة غير المفهومة تعود
/// بمستوى [VitalLevel.unknown].
VitalAdvice adviseVital({
  required String kind,
  required String value,
  String conditionName = '',
}) {
  switch (kind) {
    case VitalKind.pressure:
      return _advisePressure(value, conditionName);
    case VitalKind.sugar:
      return _adviseSugar(value, conditionName);
    case VitalKind.pulse:
      return _advisePulse(value, conditionName);
    case VitalKind.oxygen:
      return _adviseOxygen(value, conditionName);
    default:
      return _unknown(kind, value);
  }
}

/// يفسّر قراءة مخزَّنة مباشرة.
VitalAdvice adviseReading(VitalReading reading, {String conditionName = ''}) =>
    adviseVital(
      kind: reading.kind,
      value: reading.value,
      conditionName: conditionName,
    );

/// أحدث قراءة من كل نوع (حسب `createdAt`) مفسَّرة بالترتيب المعروض
/// (ضغط، سكر، نبض، أكسجين). تتجاهل الأنواع غير المعروفة والقيم الفارغة.
List<VitalAdvice> latestVitalAdvices(
  List<VitalReading> vitals, {
  String conditionName = '',
}) {
  final latest = <String, VitalReading>{};
  for (final reading in vitals) {
    if (reading.value.trim().isEmpty) continue;
    final prev = latest[reading.kind];
    if (prev == null || reading.createdAt.compareTo(prev.createdAt) >= 0) {
      latest[reading.kind] = reading;
    }
  }
  final out = <VitalAdvice>[];
  for (final kind in VitalKind.all) {
    final reading = latest[kind];
    if (reading == null) continue;
    out.add(adviseReading(reading, conditionName: conditionName));
  }
  return out;
}

// ---------------------------------------------------------------------------
// القراءات الأربعة
// ---------------------------------------------------------------------------

/// ضغط الدم — القيمة بصيغة «sys/dia» (يجب توفر رقمين على الأقل).
VitalAdvice _advisePressure(String value, String conditionName) {
  final numbers = RegExp(r'\d+(?:\.\d+)?')
      .allMatches(value)
      .map((m) => double.tryParse(m.group(0)!))
      .whereType<double>()
      .toList();
  if (numbers.length < 2) return _unknown(VitalKind.pressure, value);
  final sys = numbers[0];
  final dia = numbers[1];

  if (sys >= VitalThresholds.pressureEmergencySystolic ||
      dia >= VitalThresholds.pressureEmergencyDiastolic) {
    return VitalAdvice(
      kind: VitalKind.pressure,
      value: value,
      level: VitalLevel.emergency,
      title: 'ضغط خطر — اتصل بالإسعاف',
      message:
          'القراءة $value أعلى من الحد الخطر 180/120. اتصل بالإسعاف الآن ولا تهمل أي ألم صدر أو ضيق نفس أو صداع شديد.',
      impactKind: FoodImpactKind.pressure,
      conditionNote: _conditionNote(
          conditionName, VitalLevel.emergency, VitalKind.pressure),
    );
  }
  if (sys >= VitalThresholds.pressureHighSystolic ||
      dia >= VitalThresholds.pressureHighDiastolic) {
    return VitalAdvice(
      kind: VitalKind.pressure,
      value: value,
      level: VitalLevel.abnormal,
      title: 'ضغطك مرتفع',
      message:
          'القراءة $value أعلى من الحد المقبول 140/90. استرح 5 دقائق وأعد القياس، وإذا استمر راجع طبيبك.',
      exercises: _walkAndBreathe(20),
      foods: _pressureFoods,
      impactKind: FoodImpactKind.pressure,
      conditionNote: _conditionNote(
          conditionName, VitalLevel.abnormal, VitalKind.pressure),
    );
  }
  if (sys < VitalThresholds.pressureLowSystolic ||
      dia < VitalThresholds.pressureLowDiastolic) {
    return VitalAdvice(
      kind: VitalKind.pressure,
      value: value,
      level: VitalLevel.abnormal,
      title: 'ضغطك منخفض',
      message:
          'القراءة $value أقل من الحد المقبول 90/60. استلقِ وارفع قدميك، اشرب ماءً، وأعد القياس بعد 5 دقائق. إن شعرت بدوخة شديدة راجع الطبيب فوراً.',
      impactKind: FoodImpactKind.pressure,
      conditionNote: _conditionNote(
          conditionName, VitalLevel.abnormal, VitalKind.pressure),
    );
  }
  if (sys >= VitalThresholds.pressureNormalSystolic ||
      dia >= VitalThresholds.pressureNormalDiastolic) {
    return VitalAdvice(
      kind: VitalKind.pressure,
      value: value,
      level: VitalLevel.borderline,
      title: 'ضغطك قريب من الحد',
      message:
          'القراءة $value ضمن النطاق الحدي (120-139 / 80-89). قلّل الملح اليوم، تحرّك قليلاً، ثم أعد القياس بعد 5 دقائق.',
      exercises: _walkAndBreathe(15),
      foods: _pressureFoods,
      impactKind: FoodImpactKind.pressure,
    );
  }
  return VitalAdvice(
    kind: VitalKind.pressure,
    value: value,
    level: VitalLevel.normal,
    title: 'ضغطك طبيعي',
    message:
        'القراءة $value أقل من 120/80 — ممتاز. حافظ على مشيتك اليومية وقلّل الملح.',
    exercises: const ['المشي العادي (5 كم/س) — 30 دقيقة يومياً'],
    foods: const [
      'قلّل الملح المضاف في الطعام اليومي.',
      'زِد الخضار والفاكهة الغنية بالبوتاسيوم (موز، سبانخ، برتقال).',
    ],
    impactKind: FoodImpactKind.pressure,
  );
}

/// سكر الدم — يراعي سياق القياس (صائم / بعد الأكل / عشوائي).
VitalAdvice _adviseSugar(String value, String conditionName) {
  final sugar = VitalQualityPolicy.primaryValue(VitalKind.sugar, value);
  if (sugar == null) return _unknown(VitalKind.sugar, value);

  final context = SugarContext.of(value);

  // هبوط السكر (أولوية قصوى على الارتفاع).
  if (sugar < VitalThresholds.sugarLowSevere) {
    return VitalAdvice(
      kind: VitalKind.sugar,
      value: value,
      level: VitalLevel.emergency,
      title: 'هبوط سكر خطير',
      message:
          'القراءة $value أقل من 54 — هبوط خطير. تناول 3 تمرات أو ملعقة عسل فوراً، وأعد القياس بعد 15 دقيقة. إن لم تتحسن حالتك اتصل بالإسعاف.',
      foods: const ['كل مصدر سكر سريع (تمر/عسل/عصير) الآن ثم أعد القياس.'],
      impactKind: FoodImpactKind.sugar,
      conditionNote: _conditionNote(
          conditionName, VitalLevel.emergency, VitalKind.sugar),
    );
  }
  if (sugar < VitalThresholds.sugarLow) {
    return VitalAdvice(
      kind: VitalKind.sugar,
      value: value,
      level: VitalLevel.abnormal,
      title: 'سكرك منخفض (هبوط)',
      message:
          'القراءة $value أقل من 70. تناول مصدر سكر سريع (3 تمرات أو نصف كوب عصير) وأعد القياس بعد 15 دقيقة. لا تمارس أي رياضة حتى يرتفع سكرك.',
      foods: const [
        'مصدر سكر سريع الآن: 3 تمرات أو ملعقة عسل أو نصف كوب عصير.',
        'بعد القياس بـ 15 دقيقة تناول وجبة خفيفة فيها نشويات بطيئة (خبز أسمر).',
      ],
      impactKind: FoodImpactKind.sugar,
      conditionNote:
          _conditionNote(conditionName, VitalLevel.abnormal, VitalKind.sugar),
    );
  }

  // الارتفاع: العتبات حسب سياق القياس.
  final normalMax = context == SugarContext.fasting
      ? VitalThresholds.sugarNormalFasting
      : VitalThresholds.sugarNormalNonFasting;
  final abnormalMin = context == SugarContext.fasting
      ? VitalThresholds.sugarAbnormalFasting
      : context == SugarContext.afterMeal
          ? VitalThresholds.sugarAbnormalAfterMeal
          : VitalThresholds.sugarAbnormalRandom;

  if (sugar >= VitalThresholds.sugarEmergency) {
    return VitalAdvice(
      kind: VitalKind.sugar,
      value: value,
      level: VitalLevel.emergency,
      title: 'سكر خطر — اتصل بالإسعاف',
      message:
          'القراءة $value أعلى من الحد الخطر 250. اتصل بالإسعاف الآن، واشرب ماءً، وانتبه للعطش الشديد والتعب ورائحة النفس الأسيتونية.',
      foods: const ['ماء فقط الآن — لا نشويات ولا عصائر.'],
      impactKind: FoodImpactKind.sugar,
      conditionNote:
          _conditionNote(conditionName, VitalLevel.emergency, VitalKind.sugar),
    );
  }
  if (sugar >= abnormalMin) {
    return VitalAdvice(
      kind: VitalKind.sugar,
      value: value,
      level: VitalLevel.abnormal,
      title: 'سكرك مرتفع',
      message:
          'القراءة $value (${SugarContext.label(context)}) أعلى من الحد المقبول $abnormalMin. اشرب ماءاً وامشِ 15 دقيقة ثم أعد القياس بعد ساعة؛ إن تكرر أو ظهر تعب وعطش راجع طبيبك.',
      exercises: _walkAndBreathe(15),
      foods: _sugarFoods,
      impactKind: FoodImpactKind.sugar,
      conditionNote:
          _conditionNote(conditionName, VitalLevel.abnormal, VitalKind.sugar),
    );
  }
  if (sugar >= normalMax) {
    return VitalAdvice(
      kind: VitalKind.sugar,
      value: value,
      level: VitalLevel.borderline,
      title: 'سكرك قريب من الحد',
      message:
          'القراءة $value (${SugarContext.label(context)}) ضمن النطاق الحدي حتى $abnormalMin. انتبه للنشويات في وجبتك القادمة وأعد القياس بعد ساعتين.',
      exercises: _walkAndBreathe(15),
      foods: _sugarFoods,
      impactKind: FoodImpactKind.sugar,
    );
  }
  return VitalAdvice(
    kind: VitalKind.sugar,
    value: value,
    level: VitalLevel.normal,
    title: 'سكرك طبيعي',
    message:
        'القراءة $value (${SugarContext.label(context)}) ضمن المعدل الطبيعي — ممتاز.',
    exercises: const ['المشي السريع (6.5 كم/س) — 30 دقيقة يومياً'],
    foods: const [
      'حافظ على تناول الخضار والبروتين قبل النشويات في الوجبة.',
      'فضّل الخبز الأسمر والشوفان بدل الأبيض.',
    ],
    impactKind: FoodImpactKind.sugar,
  );
}

/// الأكسجين المشبّع (SpO2).
VitalAdvice _adviseOxygen(String value, String conditionName) {
  final oxygen = VitalQualityPolicy.primaryValue(VitalKind.oxygen, value);
  if (oxygen == null) return _unknown(VitalKind.oxygen, value);

  if (oxygen < VitalThresholds.oxygenLow) {
    return VitalAdvice(
      kind: VitalKind.oxygen,
      value: value,
      level: VitalLevel.emergency,
      title: 'أكسجينك خطر — اتصل بالإسعاف',
      message:
          'القراءة $value% أقل من 90. اتصل بالإسعاف الآن، وخصوصاً مع ضيق نفس أو زرقة في الشفاه أو أصابع اليد.',
      exercises: const ['لا تمارس أي مجهود — اجلس واسترخِ واتصل بالإسعاف.'],
      conditionNote: _conditionNote(
          conditionName, VitalLevel.emergency, VitalKind.oxygen),
    );
  }
  if (oxygen < VitalThresholds.oxygenBorderline) {
    return VitalAdvice(
      kind: VitalKind.oxygen,
      value: value,
      level: VitalLevel.abnormal,
      title: 'أكسجينك منخفض',
      message:
          'القراءة $value% أقل من الحد المقبول 93. استرح، افتح النوافذ، أعد القياس بعد 5 دقائق؛ وإن استمر راجع طبيبك.',
      exercises: _breathingExercise,
      foods: _oxygenFoods,
      conditionNote:
          _conditionNote(conditionName, VitalLevel.abnormal, VitalKind.oxygen),
    );
  }
  if (oxygen < VitalThresholds.oxygenNormal) {
    return VitalAdvice(
      kind: VitalKind.oxygen,
      value: value,
      level: VitalLevel.borderline,
      title: 'أكسجينك تحت الحد قليلاً',
      message:
          'القراءة $value% بين 93 و94 — قريب من الحد. أعد القياس بعد الاستراحة، وانتبه للحركة والتدخين قبل القياس.',
      exercises: _breathingExercise,
      foods: _oxygenFoods,
    );
  }
  return VitalAdvice(
    kind: VitalKind.oxygen,
    value: value,
    level: VitalLevel.normal,
    title: 'أكسجينك طبيعي',
    message: 'القراءة $value% ضمن المعدل الطبيعي (95 فأعلى) — ممتاز.',
    exercises: const ['المشي في الهواء الطلق — 20 دقيقة يومياً'],
    foods: _oxygenFoods,
  );
}

/// النبض (نبضة/دقيقة).
VitalAdvice _advisePulse(String value, String conditionName) {
  final pulse = VitalQualityPolicy.primaryValue(VitalKind.pulse, value);
  if (pulse == null) return _unknown(VitalKind.pulse, value);

  if (pulse < VitalThresholds.pulseAbnormalMin ||
      pulse >= VitalThresholds.pulseAbnormalMax) {
    final isSlow = pulse < VitalThresholds.pulseAbnormalMin;
    return VitalAdvice(
      kind: VitalKind.pulse,
      value: value,
      level: VitalLevel.emergency,
      title: isSlow ? 'نبضك بطيء جداً — خطر' : 'نبضك سريع جداً — خطر',
      message:
          'القراءة $value خارج المدى الآمن (أقل من 40 أو أعلى من 130). توقف عن أي مجهود، استرح، واتصل بالإسعاف إن صاحبه دوخة أو ألم صدر.',
      foods: isSlow
          ? const ['اشرب ماءً ولا تتناول منبهات (قهوة/شاي) الآن.']
          : const ['قلّل القهوة والمشروبات الطاقة الآن واشرب ماءً.'],
      impactKind: FoodImpactKind.heart,
      conditionNote:
          _conditionNote(conditionName, VitalLevel.emergency, VitalKind.pulse),
    );
  }
  if (pulse < VitalThresholds.pulseBorderlineMin ||
      pulse >= VitalThresholds.pulseBorderlineMax) {
    return VitalAdvice(
      kind: VitalKind.pulse,
      value: value,
      level: VitalLevel.abnormal,
      title: 'نبضك خارج المعدل',
      message:
          'القراءة $value خارج المدى الطبيعي (60-100). استرح 5 دقائق وأعد القياس؛ وإن تكرر أو شعرت بخفقان راجع طبيبك.',
      exercises: _breathingExercise,
      foods: _pulseFoods,
      impactKind: FoodImpactKind.heart,
      conditionNote:
          _conditionNote(conditionName, VitalLevel.abnormal, VitalKind.pulse),
    );
  }
  if (pulse < VitalThresholds.pulseNormalMin ||
      pulse >= VitalThresholds.pulseNormalMax) {
    return VitalAdvice(
      kind: VitalKind.pulse,
      value: value,
      level: VitalLevel.borderline,
      title: 'نبضك قريب من الحد',
      message:
          'القراءة $value قريبة من المدى الطبيعي (60-100). استرح وأعد القياس بعد 5 دقائق مع تنفّس بطيء.',
      exercises: _breathingExercise,
      foods: _pulseFoods,
      impactKind: FoodImpactKind.heart,
    );
  }
  return VitalAdvice(
    kind: VitalKind.pulse,
    value: value,
    level: VitalLevel.normal,
    title: 'نبضك طبيعي',
    message: 'القراءة $value ضمن المعدل الطبيعي (60-100) — ممتاز.',
    exercises: const ['المشي العادي (5 كم/س) — 30 دقيقة يومياً'],
    foods: const ['اشرب ماءً كافياً يومياً وقلّل الكافيين.'],
    impactKind: FoodImpactKind.heart,
  );
}

/// قراءة غير قابلة للتفسير (نص فارغ أو غير رقمي).
VitalAdvice _unknown(String kind, String value) => VitalAdvice(
      kind: kind,
      value: value,
      level: VitalLevel.unknown,
      title: 'لا يمكن تفسير القراءة',
      message:
          'القيمة «$value» غير مفهومة. أعد القياس وأنت مستقر والجهاز نظيف.',
    );

// ---------------------------------------------------------------------------
// نصائح الأكل والرياضة (مرتبطة بقاعدة الأغذية في food_advice.dart)
// ---------------------------------------------------------------------------

/// تمارين تنفّس آمنة لكل الحالات.
const List<String> _breathingExercise = [
  'تنفّس بطني بطيء (شهيق 4 ثوانٍ وزفير 6) — 5 دقائق',
];

/// مشي خفيف + تنفّس (مناسب لكبار السن).
List<String> _walkAndBreathe(int minutes) => [
      'المشي العادي (5 كم/س) — $minutes دقيقة',
      ..._breathingExercise,
    ];

const List<String> _pressureFoods = [
  'قلّل الملح والمخللات والأطعمة المصنعة والشوربة الجاهزة.',
  'زِد الخضار والفاكهة (البطاطا والسبانخ والموز والبرتقال) لرفع البوتاسيوم.',
  'تجنّب اللانشون والنقانق والمعلبات لأنها مملحة جداً.',
  'استبدل الملح بالتوابل والأعشاب في الطهي.',
];

const List<String> _sugarFoods = [
  'قلّل الحلويات والشوكولات والمعجنات والكعك.',
  'قلّل الأرز والخبز الأبيض واستبدل بالأسمر أو الشوفان.',
  'تجنّب العصائر والمشروبات الغازية — الماء أفضل.',
  'امشِ بعد الوجبة 10-15 دقيقة لخفض السكر بسرعة.',
];

const List<String> _oxygenFoods = [
  'اشرب ماءً كافياً خلال اليوم (الجفاف يقلل تحمّل الأكسجين).',
  'هوِّ الغرفة وافتح النوافذ قبل القياس.',
  'تجنّب التدخين قبل القياس بساعة على الأقل.',
];

const List<String> _pulseFoods = [
  'قلّل القهوة والشاي المركّز والمشروبات الطاقة.',
  'تجنّب التدخين لأنه يرفع النبض.',
  'اشرب ماءً كافياً — الجفاف يرفع سرعة القلب.',
];

/// ملاحظة مخصصة حسب الحالة المزمنة للمريض (تُترك فارغة إن لم تتطابق).
///
/// إرشادات عامة فقط — لا تتضمن أي تعديل على الأدوية.
String _conditionNote(String conditionName, String level, String kind) {
  if (conditionName.trim().isEmpty) return '';
  final lowered = conditionName.trim().toLowerCase();
  final serious =
      level == VitalLevel.abnormal || level == VitalLevel.emergency;

  if (lowered.contains('قلب') || lowered.contains('قلبي')) {
    if (kind == VitalKind.pressure || kind == VitalKind.pulse) {
      return serious
          ? 'مع مشكلتك القلبية: أي ألم صدر أو ضيق نفس أو دوخة مفاجئة تعني اتصالاً فورياً بالإسعاف.'
          : '';
    }
  }
  if (lowered.contains('سكري') || lowered.contains('سكر')) {
    if (kind == VitalKind.sugar && serious) {
      return 'مع سكريك: انتبه لعلامات الهبوط (رجفة، عرق، دوخة) وأعد القياس قبل أي مجهود.';
    }
  }
  if (lowered.contains('ضغط')) {
    if (kind == VitalKind.pressure && serious) {
      return 'مع ضغطك: التزم بمواعيد دوائك ومراجعة طبيبك، ولا تتوقف عن دواء بقرارك أنت.';
    }
  }
  return '';
}




