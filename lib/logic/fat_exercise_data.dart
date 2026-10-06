library;

/// بيانات الدهون والتمارين المستمدة من مرجع الدهون وحرقها
/// (`c:/Users/جمال/Desktop/القسم الأول.docx`).
///
/// هذه البيانات منفصلة عن منطق التطبيق ويمكن استبدالها بقاعدة بيانات حقيقية
/// أو تحديثها لاحقاً دون التأثير على بقية التطبيق.
///
/// المصادر:
///  - 1 غرام دهون (أي نوع) = 9 سعرة حرارية
///  - 1 غرام دهون مشبعة = 9 سعرة حرارية
///  - 1 كيلوغرام دهون جسم ≈ 7700 سعرة حرارية
///  - 1 باوند دهون جسم ≈ 3500 سعرة حرارية
///  - الحد الموصى به من الدهون المشبعة: أقل من 10% من السعرات اليومية
///  - الجداول معدلة لشخص بوزن 80 كيلوغرام (قابلة للتعديل حسب وزن المريض)

class FatConstants {
  /// سعرة حرارية لكل غرام دهون (أي نوع).
  static const fatCalPerGram = 9;

  /// سعرة حرارية لكل غرام دهون مشبعة.
  static const saturatedFatCalPerGram = 9;

  /// سعرة حرارية لكل كيلوغرام دهون جسم.
  static const kgBodyFatInCalories = 7700;

  /// سعرة حرارية لكل باوند دهون جسم.
  static const lbBodyFatInCalories = 3500;

  /// الحد الأقصى الموصى به للدهون المشبعة كنسبة مئوية من السعرات اليومية.
  static const saturatedFatDailyLimitPercent = 10;
}

/// تقدير كمية الدهون المشبعة (غرام) في أطعمة شائعة لكل حصة معتدلة.
///
/// هذه قيم تقديرية مستمدة من المرجع وعرف غذائي عام؛ يمكن استبدالها
/// بقاعدة بيانات أدق لاحقاً. المفتاح مطابق لكلمات القاعدة في `food_advice.dart`.
const Map<String, double> kSaturatedFatInFood = {
  'زبدة': 7.0,
  'سمن': 7.0,
  'سمنة': 7.0,
  'كريمة': 5.0,
  'مارغرين': 4.5,
  'دهون': 6.0,
  'جبن مالح': 6.0,
  'جبنة مالح': 6.0,
  'جبن قديم': 6.0,
  'أجبان مملحة': 6.0,
  'برجر': 6.0,
  'شاورما': 5.0,
  'بيتزا': 4.5,
  'دجاج مقلي': 4.0,
  'سمك مقلي': 4.0,
  'بطاطس مقلية': 4.0,
  'مقلي': 3.5,
  'مقلية': 3.5,
  'فقوس': 4.0,
  'بقري مدهون': 5.0,
  'لحوم حمراء': 4.0,
  'كبد': 2.0,
  'قلبي': 2.0,
  'لحم ضأن': 4.0,
  'بفتيك': 3.0,
  'لانشون': 3.0,
  'سجق': 3.0,
  'بسطرمة': 3.0,
  'نقانق': 3.0,
  'لحم مصنع': 3.0,
  'سلامي': 3.0,
  'فاست فود': 4.0,
  'وجبات سريعة': 4.0,
  'نسكافيه محلى': 2.5,
  'حلويات': 3.0,
  'شوكولات': 3.0,
  'كوكيز': 3.0,
  'بسكويت': 2.5,
  'جاتوه': 3.0,
  'كيك': 3.0,
  'معكرونة': 1.0,
  'مكرونة': 1.0,
  'باستا': 1.0,
  'أرز أبيض': 0.3,
  'رز أبيض': 0.3,
  'خبز أبيض': 0.3,
  'عيش أبيض': 0.3,
  'شبس': 2.0,
  'رقائق': 2.0,
  'فرايز': 2.0,
  'بطاطس': 0.2,
  'بطاطا': 0.2,
  'مخلل': 0.5,
  'مخللات': 0.5,
  'زيتون مملح': 0.5,
  'ملح': 0.0,
  'أكل مالح': 0.5,
  'معلبات': 1.0,
  'أسماك معلبة': 1.5,
  'تونة معلبة': 1.0,
  'صلصة جاهزة': 1.0,
  'كاتشب': 1.0,
  'صويا صوص': 0.5,
  'مشروب غازي': 0.0,
  'غازية': 0.0,
  'بيبس': 0.0,
  'كولا': 0.0,
  'عصير': 0.0,
  'تمر': 0.2,
  'عسل': 0.1,
  'مربى': 0.1,
  'مربّى': 0.1,
  'تفاح': 0.0,
  'سلطة خضار': 0.0,
  'خضار': 0.0,
  'فواكه طازجة': 0.0,
};

/// معدل الحرق بالسعرات لكل دقيقة لتمارين شائعة — لشخص وزنه 80 كيلوغرام
/// (كما في المرجع، القسم الثاني).
const Map<String, double> kExerciseBurnPerMinute = {
  'مشي عادي (5 كم/س)': 4.0,
  'مشي سريع (6.5 كم/س)': 5.5,
  'جري خفيف (8 كم/س)': 9.0,
  'جري متوسط (10 كم/س)': 11.0,
  'جري سريع (12 كم/س)': 13.5,
  'الدراجة الثابتة (متوسط)': 8.0,
  'السباحة (متوسط)': 9.0,
  'نط الحبل': 12.0,
  'تمارين وزن الجسم (Burpees)': 10.0,
  'رفع الأثقال (متوسط)': 6.0,
  'اليوجا': 3.0,
  'الملاكمة (كيس)': 10.0,
  'التجديف (آلة)': 9.5,
  'صعود الدرج': 11.0,
};

/// تمارين مرتبة حسب الملاءمة لكبار السن وذوي الأمراض المزمنة
/// (منخفضة/متوسطة الشدة أولاً) ثم حسب فعالية الحرق.
const List<String> kRecommendedExercisesForFatBurn = [
  'مشي سريع (6.5 كم/س)',
  'السباحة (متوسط)',
  'الدراجة الثابتة (متوسط)',
  'مشي عادي (5 كم/س)',
  'جري خفيف (8 كم/س)',
  'جري متوسط (10 كم/س)',
  'صعود الدرج',
  'التجديف (آلة)',
  'نط الحبل',
  'تمارين وزن الجسم (Burpees)',
];

/// يعطي الغرامات التقديرية للدهون المشبعة لاسم طعام.
///
/// يعطي 0.0 إذا لم يعرف الطعام في القاعدة.
double saturatedFatGramsFor(String foodName) {
  final lowered = foodName.trim().toLowerCase();
  for (final entry in kSaturatedFatInFood.entries) {
    if (lowered.contains(entry.key)) return entry.value;
  }
  return 0.0;
}

/// يحسب إجمالي الدهون المشبعة والسعرات لقائمة أطعمة.
///
/// إذا مُرِّرت [dailyCalories] يُحسب أيضاً النسبة من حد الـ 10% اليومي.
SaturatedFatSummary totalSaturatedFatFromFoods(
  List<String> foods, {
  double? dailyCalories,
}) {
  double grams = 0;
  final matched = <String, double>{};
  for (final f in foods) {
    final g = saturatedFatGramsFor(f);
    if (g > 0) {
      matched[f] = g;
      grams += g;
    }
  }
  final calories = grams * FatConstants.saturatedFatCalPerGram;
  double? limitCalories;
  double? percentage;
  if (dailyCalories != null && dailyCalories > 0) {
    limitCalories = dailyCalories *
        (FatConstants.saturatedFatDailyLimitPercent / 100);
    percentage = limitCalories > 0 ? (calories / limitCalories) * 100 : null;
  }
  return SaturatedFatSummary(
    totalGrams: grams,
    totalCalories: calories,
    limitCalories: limitCalories,
    percentageOfLimit: percentage,
    matched: matched,
  );
}

/// ملخص الدهون المشبعة المجمعة لقائمة أطعمة.
class SaturatedFatSummary {
  /// إجمالي الغرامات المقدَّرة.
  final double totalGrams;

  /// السعرات الناتجة عن الدهون المشبعة (غرام × 9).
  final double totalCalories;

  /// الحد اليومي المسموح بالسعرات (إن وُفرت السعرات اليومية)، أو null.
  final double? limitCalories;

  /// النسبة من الحد اليومي (%)، أو null.
  final double? percentageOfLimit;

  /// الطعام ← غراماته المقدَّرة (الطعام المعروف فقط).
  final Map<String, double> matched;

  const SaturatedFatSummary({
    required this.totalGrams,
    required this.totalCalories,
    required this.limitCalories,
    required this.percentageOfLimit,
    required this.matched,
  });

  bool get exceedsLimit =>
      percentageOfLimit != null && percentageOfLimit! > 100;
}

/// الوقت (بالدقائق) اللازم لتمرين معيّن لحرق كمية دهون مشبعة معيّنة.
///
/// يعطي `double.infinity` إن لم يُعرف التمرين.
double exerciseTimeToBurnSatFat({
  required double saturatedFatGrams,
  required String exercise,
  double patientWeightKg = 80,
}) {
  final burn = kExerciseBurnPerMinute[exercise] ?? 0.0;
  if (burn <= 0) return double.infinity;
  final calories = saturatedFatGrams * FatConstants.saturatedFatCalPerGram;
  var minutes = calories / burn;
  // تصحيح حسب وزن المريض (الجدول مبني على 80 كجم).
  if (patientWeightKg != 80 && patientWeightKg > 0) {
    minutes *= (80 / patientWeightKg);
  }
  return minutes;
}

/// اقتراح أفضل 3 تمارين لتعويض كمية دهون مشبعة معيّنة.
List<ExerciseSuggestion> suggestExercisesToBurnSatFat({
  required double saturatedFatGrams,
  double patientWeightKg = 80,
  List<String>? preferredExercises,
}) {
  if (saturatedFatGrams <= 0) return const [];
  final pool = (preferredExercises != null && preferredExercises.isNotEmpty)
      ? preferredExercises
      : kRecommendedExercisesForFatBurn;
  final out = <ExerciseSuggestion>[];
  for (final ex in pool) {
    final minutes = exerciseTimeToBurnSatFat(
      saturatedFatGrams: saturatedFatGrams,
      exercise: ex,
      patientWeightKg: patientWeightKg,
    );
    if (minutes.isFinite && minutes > 0) {
      out.add(ExerciseSuggestion(exercise: ex, minutes: minutes));
    }
  }
  out.sort((a, b) => a.minutes.compareTo(b.minutes));
  if (out.length > 3) out.removeRange(3, out.length);
  return out;
}

/// اقتراح تمرين واحد مع وقت التعويض.
class ExerciseSuggestion {
  /// اسم التمرين كما في `kExerciseBurnPerMinute`.
  final String exercise;

  /// عدد الدقائق اللازمة.
  final double minutes;

  const ExerciseSuggestion({required this.exercise, required this.minutes});
}

/// أسماء التمارين المفضلة حسب نوع المرض المزمن.
const Map<String, List<String>> kPreferredExercisesByCondition = {
  'heart': ['مشي سريع (6.5 كم/س)', 'السباحة (متوسط)', 'الدراجة الثابتة (متوسط)', 'مشي عادي (5 كم/س)'],
  'sugar': ['مشي سريع (6.5 كم/س)', 'مشي عادي (5 كم/س)', 'جري خفيف (8 كم/س)', 'الدراجة الثابتة (متوسط)'],
  'pressure': ['مشي عادي (5 كم/س)', 'مشي سريع (6.5 كم/س)', 'اليوجا', 'السباحة (متوسط)'],
  'liver': ['مشي سريع (6.5 كم/س)', 'السباحة (متوسط)', 'جري خفيف (8 كم/س)', 'الدراجة الثابتة (متوسط)'],
  'general': ['مشي سريع (6.5 كم/س)', 'السباحة (متوسط)', 'الدراجة الثابتة (متوسط)', 'مشي عادي (5 كم/س)'],
};