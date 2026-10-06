/// محرك النصائح التعويضية: يحوّل ما تناوله المريض إلى نصائح فورية للتخلّص
/// من الضرر (تمارين حرق + إرشادات مخصصة للمرض المزمن).
///
/// الفكرة: إذا فرط المريض في الأكل أو لم يلتزم بالمعايير، يعطي التطبيق
/// نصائح تعويضية بدل الاكتفاء بالتحذير.
library;

import '../models/sandy_data.dart';
import 'fat_exercise_data.dart';
import 'food_advice.dart';

/// شدة التلميح التعويضي.
class FatAdviceLevel {
  static const none = 'none'; // لا دهون معروفة
  static const ok = 'ok'; // ضمن الحد
  static const warn = 'warn'; // قريب من الحد (70%-100%)
  static const over = 'over'; // تجاوز الحد
  static String label(String v) {
    switch (v) {
      case over:
        return 'تجاوز الحد';
      case warn:
        return 'قريب من الحد';
      case ok:
        return 'ضمن الحد';
      default:
        return 'لا دهون مشبعة معروفة';
    }
  }
}

/// نصيحة تعويضية لوجبة أو ليوم كامل.
class FatExerciseAdvice {
  /// ملخص الدهون المشبعة.
  final SaturatedFatSummary summary;

  /// شدة التلميح (`FatAdviceLevel`).
  final String level;

  /// أفضل التمارين المقترحة مع الوقت لكل تمرين.
  final List<ExerciseSuggestion> suggestions;

  /// نصيحة مخصصة للمرض المزمن (أو نصيحة عامة).
  final String conditionAdvice;

  /// أنواع التأثر (sugar/pressure/heart) المرتبطة بالأطعمة المدخلة.
  final List<String> impactKinds;

  const FatExerciseAdvice({
    required this.summary,
    required this.level,
    required this.suggestions,
    required this.conditionAdvice,
    required this.impactKinds,
  });

  bool get hasAction => level != FatAdviceLevel.none;
}

/// نصائح مخصصة حسب كلمات مفتاحية في `conditionName`.
const Map<String, String> kConditionAdvice = {
  'سكري':
      'لديك سكري: الدهون المشبعة تزيد مقاومة الأنسولين. فضّل المشي السريع بعد الوجبة بـ 30-45 دقيقة فهو يخفض سكر الدم أيضاً، وقلّل الزبدة والسمن والمقليات.',
  'ضغط':
      'لديك ضغط: الدهون المشبعة ترفع الكوليسترول وتضغط على الأوعية. فضّل المشي العادي أو السباحة، وتجنّب رفع الأثقال الشديد، وقلّل الملح معها.',
  'قلب':
      'لديك مشكلة قلبية: الدهون المشبعة خطر مباشر. فضّل المشي السريع أو السباحة، وتجنّب الملاكمة ورفع الأثقال الشديد، واستبدل بالسمك والزيت النباتي.',
  'كبد':
      'لديك مشكلة كبد (دهون كبد): التمارين الهوائية 150-300 دقيقة أسبوعياً تخفض دهون الكبد. المشي السريع أو السباحة يومياً 30 دقيقة خيار ممتاز.',
  'كوليسترول':
      'لديك كوليسترول مرتفع: الدهون المشبعة ترفعه مباشرة. المشي السريع يومياً 30-45 دقيقة يخفضه، وقلّل الزبدة والجبن المالح والمقليات.',
  'بدانة':
      'عندك زيادة وزن: لخسارة نصف كجم أسبوعياً تحتاج عجز 500 سعرة يومياً. المشي السريع 45-90 دقيقة أو الجري المتوسط 45 دقيقة يحقق ذلك.',
};

/// نصيحة عامة إن لم تتطابق حالة المريض.
const kGeneralFatAdvice =
    'الدهون المشبعة ترفع الكوليسترول. الحد اليومي أقل من 10% من السعرات. '
    'إن فرطت، علّق الوجبة بتمرين هوائي مناسب وقلّل الكمية في الوجبة التالية.';

/// يستخرج نصيحة مخصصة من `conditionName` (أو نصيحة عامة).
String conditionAdviceFor(String conditionName) {
  final lowered = conditionName.trim().toLowerCase();
  for (final entry in kConditionAdvice.entries) {
    if (lowered.contains(entry.key)) return entry.value;
  }
  return kGeneralFatAdvice;
}

/// يستخرج مفاتيح التمارين المفضلة حسب حالة المريض.
List<String> preferredExercisesFor(String conditionName) {
  final lowered = conditionName.trim().toLowerCase();
  String key = 'general';
  if (lowered.contains('سكري') || lowered.contains('سكر')) key = 'sugar';
  if (lowered.contains('قلب') || lowered.contains('كوليسترول')) key = 'heart';
  if (lowered.contains('ضغط')) key = 'pressure';
  if (lowered.contains('كبد')) key = 'liver';
  return kPreferredExercisesByCondition[key] ?? const [];
}

/// يبني النصيحة التعويضية لقائمة أطعمة.
///
/// [patientWeightKg] اختياري لضبط وقت الحرق؛ الافتراضي 80 كجم (الجدول المرجعي).
/// [dailyCalories] اختياري لتحديد تجاوز حد الـ 10%؛ إن لم توفر،
/// تُستخدم عتبة تقديرية مبنية على 2200 سعرة يوم متوسط.
FatExerciseAdvice adviceForFoods({
  required List<String> foods,
  String conditionName = '',
  double patientWeightKg = 80,
  double? dailyCalories,
}) {
  // السكر/الضغط/القلب من قاعدة الأطعمة الحالية.
  final kinds = <String>[];
  for (final f in foods) {
    for (final c in analyzeFood(f)) {
      if (!kinds.contains(c.kind)) kinds.add(c.kind);
    }
  }
  final summary =
      totalSaturatedFatFromFoods(foods, dailyCalories: dailyCalories);
  final exercises = preferredExercisesFor(conditionName);
  final suggestions = suggestExercisesToBurnSatFat(
    saturatedFatGrams: summary.totalGrams,
    patientWeightKg: patientWeightKg,
    preferredExercises: exercises,
  );

  // تحديد الشدة: تجاوز صريح (إن قُدّمت السعرات) أو عتبة تقديرية.
  const kAssumedDailyCalories = 2200.0;
  final limitGrams = summary.limitCalories != null
      ? summary.limitCalories! / FatConstants.saturatedFatCalPerGram
      : kAssumedDailyCalories *
          (FatConstants.saturatedFatDailyLimitPercent / 100) /
          FatConstants.saturatedFatCalPerGram;
  final ratio = limitGrams > 0 ? summary.totalGrams / limitGrams : 0.0;
  String level;
  if (summary.totalGrams <= 0) {
    level = FatAdviceLevel.none;
  } else if (ratio > 1.0) {
    level = FatAdviceLevel.over;
  } else if (ratio >= 0.7) {
    level = FatAdviceLevel.warn;
  } else {
    level = FatAdviceLevel.ok;
  }

  return FatExerciseAdvice(
    summary: summary,
    level: level,
    suggestions: suggestions,
    conditionAdvice: conditionAdviceFor(conditionName),
    impactKinds: kinds,
  );
}

/// يساعد في بناء نص الشرح الظاهر للمريض (مختصر ومقروء).
String adviceSummaryText(FatExerciseAdvice advice) {
  if (advice.level == FatAdviceLevel.none) {
    return 'لا دهون مشبعة معروفة في الوجبة. استمر على الخضار والبروتين الخفيف.';
  }
  final grams = advice.summary.totalGrams.toStringAsFixed(1);
  final cals = advice.summary.totalCalories.toStringAsFixed(0);
  final pct = advice.summary.percentageOfLimit;
  final pctText =
      pct == null ? '' : ' (${pct.toStringAsFixed(0)}% من حد اليوم)';
  final first = advice.suggestions.isEmpty
      ? ''
      : ' تعويضها: ${advice.suggestions.first.exercise} ${advice.suggestions.first.minutes.toStringAsFixed(0)} دقيقة';
  switch (advice.level) {
    case FatAdviceLevel.over:
      return 'أفرطت: $grams غ دهون مشبعة ($cals سعرة)$pctText.$first';
    case FatAdviceLevel.warn:
      return 'قريب من الحد: $grams غ دهون مشبعة ($cals سعرة)$pctText.$first';
    default:
      return 'ضمن الحد: $grams غ دهون مشبعة ($cals سعرة)$pctText. حافظ على المشي اليومي.';
  }
}

/// يبني النصيحة لوجبات اليوم كاملة (كل الوجبات من `SandyData`).
FatExerciseAdvice adviceForDay({
  required SandyData data,
  double patientWeightKg = 80,
  double? dailyCalories,
}) {
  return adviceForFoods(
    foods: data.foodEntries.map((e) => e.name).toList(),
    conditionName: data.patient.conditionName,
    patientWeightKg: patientWeightKg,
    dailyCalories: dailyCalories,
  );
}