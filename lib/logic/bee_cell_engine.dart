/// محرك "خلية النحل الصحية" — نظام مترابط يربط:
/// (الدواء + الحالة المزاجية + الغذاء) مع (النشاط الرياضي + الفحص الغذائي).
///
/// مبدأ التصميم:
/// - منطق خالص (Pure Dart): يستقبل بيانات من `SandyStore` ويعيد توصيات،
///   ولا يلمس الشبكة ولا التخزين — لذا يُختبر بسهولة.
/// - تعليمي فقط: كل المخرجات إرشادات عامة وليست تشخيصاً طبياً.
/// - إضافي بالكامل: لا يعدّل أي ميزة قائمة في التطبيق.
library;

import '../models/sandy_data.dart';
import 'vital_quality.dart';

// ---------------------------------------------------------------------------
// 1) المزاج — خيارات موحّدة (مفاتيح إنجليزية ثابتة + تسميات عربية للعرض)
// ---------------------------------------------------------------------------

/// مفاتيح حالات المزاج المستخدمة في نظام خلية النحل.
///
/// المفاتيح إنجليزية ثابتة حتى لا تتعطل القواعد مع الترجمة، والتسمية
/// العربية تُعرض عبر [PostDoseMood.label].
class PostDoseMood {
  static const good = 'good'; // 😊 متاح
  static const sad = 'sad'; // 😔 حزين
  static const tired = 'tired'; // 😰 متعب
  static const tense = 'tense'; // 😤 متوتر
  static const neutral = 'neutral'; // 😐 عادي

  /// كل الخيارات بالترتيب المعروض للمريض.
  static const all = <String>[good, sad, tired, tense, neutral];

  /// التسمية العربية + الرمز التعبيري.
  static String label(String key) {
    switch (key) {
      case good:
        return '😊 متاح';
      case sad:
        return '😔 حزين';
      case tired:
        return '😰 متعب';
      case tense:
        return '😤 متوتر';
      case neutral:
        return '😐 عادي';
      default:
        return key;
    }
  }

  /// يوحّد مزاجاً مسجَّلاً بالعربية في اليوميات (ممتاز/جيد/لا بأس/تعبان)
  /// إلى مفتاح خلية النحل حتى تعمل القواعد مع سجل قديم.
  static String fromJournalMood(String mood) {
    switch (mood) {
      case 'ممتاز':
      case 'جيد':
        return good;
      case 'تعبان':
        return tired;
      case 'لا بأس':
        return neutral;
      default:
        return all.contains(mood) ? mood : neutral;
    }
  }

  /// هل المزاج من عائلة "سلبية" التي تستوجب التنبيه (حزين/متعب)؟
  static bool isConcerning(String key) => key == sad || key == tired;
}

// ---------------------------------------------------------------------------
// 2) ربط الدواء بالحالة المزاجية — عدّاد التكرار وتنبيه الطبيب
// ---------------------------------------------------------------------------

/// تنبيه يُطلق عند تكرار مزاج سلبي بعد نفس الدواء.
class DoctorMoodAlert {
  /// اسم الدواء الذي تكرر بعده السلب.
  final String medicationName;

  /// عدد مرات التكرار (>= 3).
  final int occurrences;

  /// المزاج المتكرر ('sad' أو 'tired').
  final String mood;

  const DoctorMoodAlert({
    required this.medicationName,
    required this.occurrences,
    required this.mood,
  });

  /// نص التنبيه الموجّه للطبيب (يُضمَّن في تقرير الطبيب).
  String get message =>
      'تكرر شعور ${PostDoseMood.label(mood)} بعد دواء "$medicationName" '
      '$occurrences مرات — يُنصح بمراجعة ملاءمة الدواء أو موعده.';
}

/// يفحص أحداث ما بعد الجرعة ويكشف تكرار الحزن/التعب **3 مرات أو أكثر بعد
/// نفس الدواء** (آخر 30 يوماً) ليُرسل تنبيهاً للطبيب.
///
/// يُرجع أقوى نمط (الأكثر تكراراً) أو null إن لم يوجد.
DoctorMoodAlert? detectRepeatedPostDoseMood(
  List<MedicationDoseEvent> events, {
  int threshold = 3,
  int windowDays = 30,
}) {
  final cutoff = DateTime.now().toUtc().subtract(Duration(days: windowDays));
  // العدّاد: (اسم الدواء + المزاج) ← التواريخ.
  final counts = <String, List<DateTime>>{};
  for (final event in events) {
    final mood = event.postDoseMood;
    if (mood == null || !PostDoseMood.isConcerning(mood)) continue;
    final created = DateTime.tryParse(event.createdAt)?.toUtc();
    if (created == null || created.isBefore(cutoff)) continue;
    counts.putIfAbsent('${event.medicationName}|$mood', () => []).add(created);
  }
  String? bestKey;
  var bestCount = 0;
  counts.forEach((key, dates) {
    if (dates.length >= threshold && dates.length > bestCount) {
      bestKey = key;
      bestCount = dates.length;
    }
  });
  if (bestKey == null) return null;
  final parts = bestKey!.split('|');
  return DoctorMoodAlert(
    medicationName: parts[0],
    mood: parts[1],
    occurrences: bestCount,
  );
}

// ---------------------------------------------------------------------------
// 3) ربط الدواء بالغذاء — تعارضات دوائية-غذائية
// ---------------------------------------------------------------------------

/// مستوى خطورة التعارض الغذائي-الدوائي.
class ConflictLevel {
  static const forbidden = 'forbidden'; // ممنوع
  static const warning = 'warning'; // تحذير
  static const advice = 'advice'; // توصية

  static String label(String level) {
    switch (level) {
      case forbidden:
        return '🚫 ممنوع';
      case warning:
        return '⚠️ تحذير';
      default:
        return '💡 توصية';
    }
  }
}

/// قاعدة تعارض بين دواء (بالكلمات المفتاحية في اسمه أو فئته المرضية) وطعام.
class MedFoodConflict {
  /// كلمات تُطابق اسم الدواء (ميتفورمين، Glucophage...).
  final List<String> medKeywords;

  /// فئات مرضية تُطبَّق عليها القاعدة دون ذكر اسم الدواء (اختياري).
  final List<String> medCategories;

  /// كلمات تُطابق اسم الطعام المسجَّل. فارغة = قاعدة سلوكية دائمة.
  final List<String> foodKeywords;

  /// مستوى الخطورة (انظر [ConflictLevel]).
  final String level;

  /// نص القاعدة للمريض.
  final String rule;

  const MedFoodConflict({
    required this.medKeywords,
    this.medCategories = const [],
    required this.foodKeywords,
    required this.level,
    required this.rule,
  });

  /// هل يطابق هذا الدواء القاعدة؟
  bool matchesMedication(Medication med) {
    final name = med.name.toLowerCase();
    if (medKeywords.any((k) => name.contains(k.toLowerCase()))) return true;
    return medCategories.contains(med.category);
  }

  /// هل يطابق هذا الطعام القاعدة؟
  bool matchesFood(String food) {
    final lowered = food.toLowerCase();
    return foodKeywords.any((k) => lowered.contains(k.toLowerCase()));
  }
}

/// القواعد الست المعتمدة (تعارضات دوائية-غذائية).
const List<MedFoodConflict> kMedFoodConflicts = [
  // 1) ميتفورمين → منع الكحول (خطر الحماض اللبني وهبوط السكر).
  MedFoodConflict(
    medKeywords: ['ميتفورمين', 'ميتفورم', 'metformin', 'glucophage'],
    foodKeywords: ['كحول', 'خمر', 'بيرة', 'نبيذ', 'alcohol', 'beer', 'wine'],
    level: ConflictLevel.forbidden,
    rule: 'الكحول ممنوع مع الميتفورمين: يرفع خطر الحماض اللبني وهبوط السكر.',
  ),
  // 2) وارفارين → تثبيت فيتامين K (لا تغيير مفاجئ في الورقيات).
  MedFoodConflict(
    medKeywords: ['وارفارين', 'warfarin', 'كومادين', 'coumadin'],
    foodKeywords: ['سبانخ', 'بروكلي', 'خس', 'ملفوف', 'جرجير', 'ملوخية'],
    level: ConflictLevel.warning,
    rule:
        'مع الوارفارين: ثبّت كمية الخضار الورقية (فيتامين K) يومياً — '
        'التغيير المفاجئ (زيادة أو انقطاع) يفسد تأثير الدواء.',
  ),
  // 3) حاصرات بيتا → تحذير من الأطعمة عالية البوتاسيوم.
  MedFoodConflict(
    medKeywords: ['بروبرانولول', 'كارفيديلول', 'ميتوبرولول', 'أتينولول'],
    medCategories: [MedicationCategory.heart, MedicationCategory.pressure],
    foodKeywords: ['موز', 'تمر', 'أفوكادو', 'بطاطا', 'بطاطس', 'عصير برتقال'],
    level: ConflictLevel.warning,
    rule:
        'مع حاصرات بيتا يرتفع البوتاسيوم في الدم — لا تُفرط في الموز والتمر '
        'والأفوكادو، واسأل طبيبك عن الكمية المسموحة.',
  ),
  // 4) الأنسولين → منع تخطي وجبة بعد الحقن (قاعدة سلوكية دائمة).
  MedFoodConflict(
    medKeywords: ['أنسولين', 'انسولين', 'insulin', 'لانتوس', 'نوفورابيد'],
    foodKeywords: [],
    level: ConflictLevel.forbidden,
    rule:
        'بعد حقن الأنسولين يجب أكل الوجبة في موعدها — تخطي الوجبة يسبب هبوط '
        'سكر خطير. إن فترت شهيتك استشر طبيبك في تعديل الجرعة، ولا تتخطَّ الوجبة.',
  ),
  // 5) ستاتين → منع عصير الجريب فروت.
  MedFoodConflict(
    medKeywords: ['ستاتين', 'atorvastatin', 'simvastatin', 'rosuvastatin'],
    foodKeywords: ['جريب فروت', 'غراب فروت', 'grapefruit'],
    level: ConflictLevel.forbidden,
    rule:
        'عصير الجريب فروت ممنوع مع الستاتين: يرفع تركيز الدواء في الدم '
        'ويزيد خطر تلف العضلات.',
  ),
  // 6) مدرات البول → التوصية بتعويض البوتاسيوم (قاعدة سلوكية دائمة).
  MedFoodConflict(
    medKeywords: ['فوروسيميد', 'هيدروكلوروثيازيد', 'مدر', 'furosemide', 'lasix'],
    foodKeywords: [],
    level: ConflictLevel.advice,
    rule:
        'مدرات البول تُخرج البوتاسيوم مع البول — عوّضه يومياً من الموز '
        '(حبة إلى حبتين) والتمر (2-3 حبات) والبطاطا المسلوقة، إلا إذا منعك طبيبك.',
  ),
];

/// نتيجة تعارض مكتشفة بين دواء وطعام.
class MedFoodFinding {
  /// الدواء الذي طابق القاعدة.
  final Medication medication;

  /// الطعام المطابق (فارغ للقواعد السلوكية الدائمة).
  final String food;

  /// القاعدة المطبَّقة.
  final MedFoodConflict conflict;

  const MedFoodFinding({
    required this.medication,
    required this.food,
    required this.conflict,
  });

  /// رسالة جاهزة للعرض للمريض.
  String get message =>
      '${ConflictLevel.label(conflict.level)} ${medication.name}'
      '${food.isEmpty ? '' : ' × $food'} — ${conflict.rule}';
}

/// يفحص الأدوية مقابل الأطعمة المسجَّلة ويُرجع التعارضات المكتشفة.
///
/// القواعد السلوكية (الأنسولين/المدرات) تظهر مرة واحدة لكل دواء متطابق حتى
/// لو لم يُسجَّل طعام، لأنها تحذير دائم لا يتوقف على وجبة بعينها.
List<MedFoodFinding> detectMedFoodConflicts({
  required List<Medication> medications,
  required List<String> foods,
}) {
  final findings = <MedFoodFinding>[];
  final seen = <String>{};
  for (final med in medications) {
    for (final conflict in kMedFoodConflicts) {
      if (!conflict.matchesMedication(med)) continue;
      if (conflict.foodKeywords.isEmpty) {
        if (seen.add('${med.id}|${conflict.rule}')) {
          findings.add(
              MedFoodFinding(medication: med, food: '', conflict: conflict));
        }
        continue;
      }
      for (final food in foods) {
        if (!conflict.matchesFood(food)) continue;
        if (seen.add('${med.id}|$food|${conflict.rule}')) {
          findings.add(MedFoodFinding(
              medication: med, food: food, conflict: conflict));
        }
      }
    }
  }
  return findings;
}

// ---------------------------------------------------------------------------
// 4) ربط الحالة المزاجية بالغذاء — خطة الوجبات الثلاث لكل مزاج
// ---------------------------------------------------------------------------

/// خطة وجبات (فطور/غداء/عشاء) لحالة مزاج واحدة.
class MoodMealPlan {
  final String mood;
  final String breakfast;
  final String lunch;
  final String dinner;

  const MoodMealPlan({
    required this.mood,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
  });
}

/// جدول الوجبات حسب الحالة المزاجية (المواصفة المعتمدة).
const List<MoodMealPlan> kMoodMealPlans = [
  MoodMealPlan(
    mood: PostDoseMood.good,
    breakfast: 'فطور متوازن (حبوب كاملة + فاكهة + بروتين خفيف)',
    lunch: 'بروتين + خضار',
    dinner: 'عشاء خفيف',
  ),
  MoodMealPlan(
    mood: PostDoseMood.sad,
    breakfast: 'شوفان + مكسرات + مصدر أوميغا 3 (سمك أو بذور كتان)',
    lunch: 'سمك + أرز بني',
    dinner: 'شوربة دافئة',
  ),
  MoodMealPlan(
    mood: PostDoseMood.tired,
    breakfast: 'تمر + لبن',
    lunch: 'عدس + خضار',
    dinner: 'بيض مسلوق',
  ),
  MoodMealPlan(
    mood: PostDoseMood.tense,
    breakfast: 'فطور بلا كافيين (شاي أعشاب بدل القهوة/الشاي)',
    lunch: 'غداء بتقليل الملح',
    dinner: 'لبن + موز',
  ),
  MoodMealPlan(
    mood: PostDoseMood.neutral,
    breakfast: 'فطور متوازن معتاد',
    lunch: 'غداء معتاد متوازن',
    dinner: 'عشاء معتاد خفيف',
  ),
];

/// خطة الوجبات لحالة مزاج (تعيد الخطة الافتراضية عند مجهول المزاج).
MoodMealPlan mealPlanForMood(String moodKey) {
  for (final plan in kMoodMealPlans) {
    if (plan.mood == moodKey) return plan;
  }
  return kMoodMealPlans.last;
}

// ---------------------------------------------------------------------------
// 5) دمج النشاط الرياضي — قرار النشاط حسب المزاج والسكر
// ---------------------------------------------------------------------------

/// قرار النشاط الرياضي.
class ExerciseDecision {
  /// مسموح/مقترح/ممنوع.
  final String verdict; // suggest-light | suggest-moderate | blocked | none

  /// النشاط المقترح (فارغ عند المنع).
  final String activity;

  /// الدقائق المقترحة.
  final int minutes;

  /// سبب القرار (يُعرض للمريض).
  final String reason;

  const ExerciseDecision({
    required this.verdict,
    required this.activity,
    required this.minutes,
    required this.reason,
  });

  bool get blocked => verdict == 'blocked';
  bool get suggested => verdict == 'suggest-light' || verdict == 'suggest-moderate';
}

/// يحسب قرار النشاط حسب المزاج وأحدث قراءة سكر.
///
/// القواعد (المواصفة):
/// - حزين أو متوتر → نشاط خفيف 10-15 دقيقة (مشي).
/// - سكر مرتفع بعد الوجبة (>= 180) → نشاط هوائي متوسط.
/// - سكر منخفض (< 70) → منع النشاط حتى يعود للمعدل الطبيعي.
/// - غير ذلك → لا اقتراح إضافي.
ExerciseDecision exerciseDecision({
  required String moodKey,
  String? latestSugar,
  String? latestKind,
}) {
  // منع قاطع عند هبوط السكر (أولوية عليا على أي اقتراح). يُقرأ الرقم بأي
  // صيغة (وحدة/سياق صائم أو بعد الأكل) عبر المستخرج الموحد حتى لا تنكسر
  // القاعدة عن القراءات المكتوبة هكذا: «98 صائم» مثلاً.
  final sugar = latestSugar != null && latestKind == 'sugar'
      ? VitalQualityPolicy.primaryValue('sugar', latestSugar)
      : null;
  if (sugar != null && sugar < 70) {
    return const ExerciseDecision(
      verdict: 'blocked',
      activity: '',
      minutes: 0,
      reason:
          'سترك منخفض (< 70) — توقف عن أي جهد الآن، تناول مصدر سكر سريع '
          '(3 تمرات أو نصف كوب عصير) ولا تمارس النشاط حتى يعود سترك للمعدل الطبيعي.',
    );
  }

  // سكر مرتفع بعد الوجبة → نشاط هوائي متوسط.
  if (sugar != null && sugar >= 180) {
    return ExerciseDecision(
      verdict: 'suggest-moderate',
      activity: 'مشي هوائي متوسط',
      minutes: 30,
      reason: 'سترك مرتفع (${sugar.round()}) بعد الوجبة — المشي المتوسط '
          '30 دقيقة يساعد على خفضه بشكل طبيعي.',
    );
  }

  // مزاج سلبي → نشاط خفيف.
  if (moodKey == PostDoseMood.sad || moodKey == PostDoseMood.tense) {
    return ExerciseDecision(
      verdict: 'suggest-light',
      activity: 'مشي خفيف',
      minutes: moodKey == PostDoseMood.sad ? 15 : 10,
      reason: moodKey == PostDoseMood.sad
          ? 'المشي الخفيف 15 دقيقة يحسّن المزاج (يفرز الإندورفين الطبيعي).'
          : 'المشي الخفيف 10 دقيقة يهدّئ التوتر ويخفض الشد العصبي.',
    );
  }

  // لا شرط يستدعي اقتراحاً إضافياً.
  return const ExerciseDecision(
    verdict: 'none',
    activity: '',
    minutes: 0,
    reason: '',
  );
}

// ---------------------------------------------------------------------------
// 6) دمج الفحص الغذائي — استنتاج النقص/الزيادة من سجل الأسبوع
// ---------------------------------------------------------------------------

/// عنصر غذائي مرصود (نقص أو زيادة).
class NutrientFinding {
  /// اسم العنصر بالعربية (حديد، بوتاسيوم، فيتامين D، صوديوم، سكر...).
  final String nutrient;

  /// 'deficiency' (نقص) أو 'excess' (زيادة).
  final String kind;

  /// ما وُجد من أنماط في السجل (للعرض).
  final String evidence;

  /// التوصية التصحيحية (مصادر غذائية أو بدائل).
  final String recommendation;

  const NutrientFinding({
    required this.nutrient,
    required this.kind,
    required this.evidence,
    required this.recommendation,
  });

  bool get isDeficiency => kind == 'deficiency';
  bool get isExcess => kind == 'excess';
}

/// أنماط أطعمة تدل على غياب مصدر عنصر مهم خلال الأسبوع.
/// (الفحص استنتاجي من السجل الفعلي — لا تحاليل مخبرية).
const Map<String, List<String>> kDeficiencyFoodMarkers = {
  'حديد': ['لحم', 'كبدة', 'عدس', 'سبانخ', 'فول', 'بقوليات'],
  'بوتاسيوم': ['موز', 'تمر', 'بطاطا', 'بطاطس', 'أفوكادو', 'سبانخ'],
  'فيتامين D': ['سمك', 'سلمون', 'تونة', 'سردين', 'صفار', 'بيض'],
  'ألياف': ['شوفان', 'خضار', 'فاكهة', 'بقوليات', 'حبوب كاملة', 'خبز أسمر'],
};

/// أنماط أطعمة تدل على إفراط (تكرار سجلاتها خلال الأسبوع).
const Map<String, List<String>> kExcessFoodMarkers = {
  'صوديوم': ['مخلل', 'زيتون', 'جبن مالح', 'معلبات', 'شيبس', 'وجبات سريعة'],
  'سكر': ['حلويات', 'كيك', 'بسكويت', 'عصير غازي', 'شوكولاتة', 'عسل'],
  'دهون مشبعة': ['زبدة', 'سمن', 'مقليات', 'برجر', 'جبن دهني', 'قشطة'],
};

bool _containsAny(String text, List<String> keywords) {
  final lowered = text.toLowerCase();
  for (final keyword in keywords) {
    if (lowered.contains(keyword)) return true;
  }
  return false;
}

/// يفحص سجل أطعمة الأسبوع الأخير ويستنتج النقص والزيادة الغذائية.
///
/// - [foodNames]: أسماء الأطعمة المسجَّلة خلال 7 أيام.
/// نقص العنصر = لا يوجد أي طعام من مصادره في الأسبوع كله.
/// زيادة العنصر = 3 سجلات أو أكثر من أنماطه خلال الأسبوع.
List<NutrientFinding> assessWeeklyNutrition(List<String> foodNames) {
  final findings = <NutrientFinding>[];
  if (foodNames.isEmpty) return findings;
  final joined = foodNames.join(' ، ');

  // النقص: غياب كامل لمصادر العنصر خلال الأسبوع.
  const deficiencyAdvice = {
    'حديد': 'أضف 3 مرات أسبوعياً: عدس أو فول أو سبانخ، مع مصدر فيتامين C '
        '(ليمون/برتقال) لتحسين الامتصاص.',
    'بوتاسيوم': 'أضف يومياً: موزة أو 3 تمرات أو بطاطا مسلوقة '
        '(إلا إذا منعك طبيبك مع حاصرات بيتا أو مشاكل كلوية).',
    'فيتامين D': 'أضف سمكاً مرتين أسبوعياً وبيضاً؛ وتعرّض للشمس 15 دقيقة '
        'صباحاً إن سمح حالتك.',
    'ألياف': 'أضف شوفاناً في الفطور وخضاراً في الغداء وخبزاً أسمر — '
        'الألياف تخفض امتصاص السكر وتحسّن الهضم.',
  };
  kDeficiencyFoodMarkers.forEach((nutrient, sources) {
    if (!_containsAny(joined, sources)) {
      findings.add(NutrientFinding(
        nutrient: nutrient,
        kind: 'deficiency',
        evidence: 'لا يوجد أي مصدر من مصادر $nutrient في سجل أسبوعك',
        recommendation: deficiencyAdvice[nutrient]!,
      ));
    }
  });

  // الزيادة: تكرار الأنماط الضارة 3 مرات أو أكثر.
  const excessAdvice = {
    'صوديوم': 'قلّل المخللات والمعلبات والجبن المالح؛ استبدلها بخضار طازجة '
        'واستخدم الليمون والأعشاب بدل الملح.',
    'سكر': 'قلّل الحلويات والعصائر الغازية؛ استبدلها بفاكهة طازجة، '
        'وفتر الطلب بعد أسبوع يصبح أسهل.',
    'دهون مشبعة': 'قلّل المقليات والزبدة والسمن؛ استبدلها بالزيت النباتي '
        'والشوي والسلق — واطّلع على اقتراح التمارين لتعويضها.',
  };
  kExcessFoodMarkers.forEach((nutrient, patterns) {
    var count = 0;
    for (final food in foodNames) {
      if (_containsAny(food, patterns)) count++;
    }
    if (count >= 3) {
      findings.add(NutrientFinding(
        nutrient: nutrient,
        kind: 'excess',
        evidence: 'سجّلت أطعمة مرتفعة بـ$nutrient $count مرات خلال الأسبوع',
        recommendation: excessAdvice[nutrient]!,
      ));
    }
  });

  return findings;
}

/// يصحّح خطة الوجبات حسب نتائج الفحص الغذائي (الطلب 5 من المواصفة).

// ---------------------------------------------------------------------------
// 7) محرك القواعد المركزي — يجمع المدخلات ويُخرج التوصيات
// ---------------------------------------------------------------------------

/// مدخلات محرك خلية النحل (تُبنى من `SandyStore` بسهولة).
class BeeCellInput {
  /// الأدوية الحالية.
  final List<Medication> medications;

  /// أحداث الجرعات (ما بعد الجرعة، تسجيل التناول).
  final List<MedicationDoseEvent> doseEvents;

  /// آخر مزاج (مفتاح خلية النحل: good/sad/tired/tense/neutral).
  final String mood;

  /// أسماء أطعمة آخر 7 أيام (لفحص الغذاء).
  final List<String> weekFoods;

  /// أسماء أطعمة اليوم (لفحص تعارض الدواء مع وجبات اليوم).
  final List<String> todayFoods;

  /// أحدث قراءة قياس (نوعها وقيمتها) — للسكر خصوصاً.
  final String? latestVitalKind;
  final String? latestVitalValue;

  /// دقائق النشاط الرياضي المُسجَّلة هذا الأسبوع (اختياري).
  final int? weekExerciseMinutes;

  const BeeCellInput({
    required this.medications,
    required this.doseEvents,
    required this.mood,
    required this.weekFoods,
    required this.todayFoods,
    this.latestVitalKind,
    this.latestVitalValue,
    this.weekExerciseMinutes,
  });
}

/// مخرجات محرك خلية النحل.
class BeeCellOutput {
  /// خطة وجبات اليوم حسب المزاج.
  final MoodMealPlan mealPlan;

  /// تصحيحات الفحص الغذائي على الخطة.
  final List<String> mealCorrections;

  /// تعارضات دواء × غذاء مكتشفة (بأطعمة محددة).
  final List<MedFoodFinding> conflicts;

  /// قرار النشاط الرياضي.
  final ExerciseDecision exercise;

  /// تنبيه طبيب إن تكرر مزاج سلبي بعد نفس الدواء (null إن لم يوجد).
  final DoctorMoodAlert? doctorMoodAlert;

  /// نتائج الفحص الغذائي الأسبوعي.
  final List<NutrientFinding> nutritionFindings;

  /// قواعد سلوكية دائمة مرتبطة بأدوية المستخدم (أنسولين/مدرات).
  final List<String> standingRules;

  const BeeCellOutput({
    required this.mealPlan,
    required this.mealCorrections,
    required this.conflicts,
    required this.exercise,
    required this.doctorMoodAlert,
    required this.nutritionFindings,
    required this.standingRules,
  });

  /// هل هناك أي تنبيه عاجل يستحق إشعاراً فورياً؟
  bool get hasUrgent =>
      doctorMoodAlert != null ||
      conflicts.any((c) => c.conflict.level == ConflictLevel.forbidden) ||
      exercise.blocked;
}

/// يشغّل محرك خلية النحل: يستقبل المدخلات ويُخرج التوصيات الكاملة.
BeeCellOutput runBeeCellEngine(BeeCellInput input) {
  // 1) خطة الوجبات حسب المزاج.
  final plan = mealPlanForMood(input.mood);

  // 2) الفحص الغذائي الأسبوعي + تصحيح الخطة.
  final nutrition = assessWeeklyNutrition(input.weekFoods);
  final corrections = mealPlanCorrections(nutrition);

  // 3) تعارضات الدواء والغذاء (يومية) + القواعد السلوكية الدائمة.
  final findings = detectMedFoodConflicts(
    medications: input.medications,
    foods: input.todayFoods,
  );

  // 4) قرار النشاط (المزاج + السكر) — المنع عند هبوط السكر أولوية عليا.
  final exercise = exerciseDecision(
    moodKey: input.mood,
    latestSugar:
        input.latestVitalKind == 'sugar' ? input.latestVitalValue : null,
    latestKind: input.latestVitalKind,
  );

  // 5) تنبيه الطبيب عند تكرار السلب بعد نفس الدواء.
  final alert = detectRepeatedPostDoseMood(input.doseEvents);

  // 6) القواعد السلوكية الدائمة (أنسولين/مدرات) حتى دون تسجيل طعام.
  final standingRules = findings
      .where((f) => f.food.isEmpty)
      .map((f) => f.message)
      .toList();

  return BeeCellOutput(
    mealPlan: plan,
    mealCorrections: corrections,
    conflicts: findings.where((f) => f.food.isNotEmpty).toList(),
    exercise: exercise,
    doctorMoodAlert: alert,
    nutritionFindings: nutrition,
    standingRules: standingRules,
  );
}

// ---------------------------------------------------------------------------
// 8) التقارير الأسبوعية — للمريض وللطبيب
// ---------------------------------------------------------------------------

/// يبني تقرير الأسبوع للمريض: أنماط المزاج، الالتزام، اقتراحات تحسين.
String buildWeeklyPatientReport({
  required List<String> journalMoods,
  required List<MedicationDoseEvent> doseEvents,
  required List<String> weekFoods,
  int? exerciseMinutes,
}) {
  final buffer = StringBuffer();
  buffer.writeln('🐝 تقرير أسبوعك — خلية النحل الصحية');
  buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

  // أنماط المزاج.
  final moods = <String, int>{};
  for (final raw in journalMoods) {
    final key = PostDoseMood.fromJournalMood(raw);
    moods[key] = (moods[key] ?? 0) + 1;
  }
  buffer.writeln('😊 حالتك المزاجية هذا الأسبوع:');
  if (moods.isEmpty) {
    buffer.writeln('• لم تسجّل أي حالة مزاجية — سجّلها يومياً في اليوميات.');
  } else {
    for (final entry in moods.entries) {
      buffer.writeln('• ${PostDoseMood.label(entry.key)}: ${entry.value} يوم');
    }
  }

  // الالتزام بالأدوية.
  final taken =
      doseEvents.where((e) => e.type == DoseEventType.taken).length;
  final missed =
      doseEvents.where((e) => e.type == DoseEventType.missed).length;
  final total = taken + missed;
  final rate = total == 0 ? null : (taken / total * 100).round();
  buffer.writeln();
  buffer.writeln('💊 التزامك بالأدوية:');
  if (rate == null) {
    buffer.writeln('• لا توجد جرعات مسجَّلة هذا الأسبوع.');
  } else {
    buffer.writeln('• التزمت بـ $rate% من الجرعات '
        '($taken تم تناولها، $missed فائتة).');
    if (rate < 80) {
      buffer.writeln('• التزامك أقل من 80% — فعّل التذكيرات واطلب من أهلك '
          'متابعتك؛ الالتزام هو أهم عامل في ضبط المرض.');
    }
  }

  // النشاط الرياضي.
  buffer.writeln();
  buffer.writeln('🏃 نشاطك الرياضي:');
  final minutes = exerciseMinutes ?? 0;
  if (minutes == 0) {
    buffer.writeln('• لم يُسجَّل نشاط — ابدأ بمشي 10 دقائق يومياً.');
  } else {
    buffer.writeln('• سجّلت $minutes دقيقة نشاط هذا الأسبوع'
        '${minutes >= 150 ? ' — ممتاز، حققت التوصية العالمية (150 دقيقة)!' : ' — حاول الوصول إلى 150 دقيقة.'}');
  }

  // الفحص الغذائي الأسبوعي.
  buffer.writeln();
  buffer.writeln('🥗 الفحص الغذائي الأسبوعي:');
  final nutrition = assessWeeklyNutrition(weekFoods);
  if (nutrition.isEmpty) {
    buffer.writeln('• لا ملاحظات — سجل غذائك متنوعاً ومتوازناً.');
  } else {
    for (final finding in nutrition) {
      buffer.writeln(finding.isDeficiency
          ? '• نقص ${finding.nutrient}: ${finding.recommendation}'
          : '• زيادة ${finding.nutrient}: ${finding.recommendation}');
    }
  }

  // اقتراحات الأسبوع القادم.
  buffer.writeln();
  buffer.writeln('✅ اقتراحات الأسبوع القادم:');
  if (moods[PostDoseMood.sad] != null || moods[PostDoseMood.tired] != null) {
    buffer.writeln('• سجّلت حزناً أو تعباً — امشِ 15 دقيقة يومياً واتبع خطة '
        '"المزاج المنخفض" (شوفان/سمك/شوربة دافئة).');
  }
  if (rate != null && rate < 80) {
    buffer.writeln('• اربط تناول الدواء بعادة ثابتة (بعد الفطور مباشرة مثلاً).');
  }
  if (nutrition.any((f) => f.isExcess)) {
    buffer.writeln('• ركّز على تصحيح الزيادات المرصودة أعلاه هذا الأسبوع.');
  }
  if (minutes < 150) {
    buffer.writeln('• زد نشاطك 10 دقائق كل يومين حتى تصل إلى 150 دقيقة أسبوعياً.');
  }
  return buffer.toString().trim();
}

/// يبني ملاحق تقرير الطبيب الأسبوعي (تُضاف إلى تقرير `DoctorReportService`):
/// تكرارات الحالات الخطرة والتعارضات المحتملة.
///
/// يعيد أسطراً جاهزة للضم إلى نص التقرير (فارغ إذا لا شيء يستحق الذكر).
List<String> buildWeeklyDoctorLines({
  required List<MedicationDoseEvent> doseEvents,
  required List<Medication> medications,
  required List<String> journalMoods,
  required List<String> weekFoods,
}) {
  final lines = <String>[];

  // تكرار السلب بعد نفس الدواء (3 مرات خلال 30 يوماً).
  final alert = detectRepeatedPostDoseMood(doseEvents);
  if (alert != null) {
    lines.add('⚠️ ${alert.message}');
  }

  // نمط مزاج سلبي عام خلال الأسبوع (حتى دون ربط بدواء بعينه).
  var negativeDays = 0;
  for (final raw in journalMoods) {
    if (PostDoseMood.isConcerning(PostDoseMood.fromJournalMood(raw))) {
      negativeDays++;
    }
  }
  if (negativeDays >= 3) {
    lines.add('⚠️ سجّل المريض حالة سلبية (حزين/متعب) في $negativeDays أيام '
        'هذا الأسبوع — يُنصح بتقييم المزاج والنوم.');
  }

  // تعارضات دوائي-غذائية محتملة بناء على غذاء الأسبوع.
  final conflicts = detectMedFoodConflicts(
    medications: medications,
    foods: weekFoods,
  ).where((f) => f.food.isNotEmpty);
  for (final conflict in conflicts) {
    lines.add('⚠️ ${conflict.message}');
  }

  return lines;
}

/// يصحّح خطة الوجبات حسب نتائج الفحص الغذائي (الطلب 5 من المواصفة).
///
/// يعيد أسطر تصحيح تُضاف تحت خطة المزاج.
List<String> mealPlanCorrections(List<NutrientFinding> findings) {
  final corrections = <String>[];
  for (final finding in findings) {
    if (finding.isDeficiency) {
      corrections.add(
          '🩺 نقص ${finding.nutrient}: ${finding.recommendation}');
    } else {
      corrections.add(
          '⚠️ زيادة ${finding.nutrient}: ${finding.recommendation}');
    }
  }
  return corrections;
}

