/// تحليل تفاعل الغذاء مع الدواء (خاصة دواء الصباح).
library;

import '../models/sandy_data.dart';
import 'food_advice.dart';
import 'medication_times.dart';
import 'sandy_logic.dart';

class MealRisk {
  static const none = 'none';
  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';
  static String label(String v) {
    switch (v) {
      case high:
        return 'مرتفع — انتبه';
      case medium:
        return 'متوسط';
      case low:
        return 'منخفض';
      default:
        return 'لا يوجد تعارض معروف';
    }
  }
}

class FoodPortionAdvice {
  final String foodName;
  final String amountAdvice;
  final String alternative;
  final String timingAdvice;
  final List<String> kinds;
  const FoodPortionAdvice({
    required this.foodName,
    required this.amountAdvice,
    required this.alternative,
    required this.timingAdvice,
    required this.kinds,
  });
}

class MealMedAnalysis {
  final String mealType;
  final List<String> foods;
  final String risk;
  final String summary;
  final List<FoodPortionAdvice> items;
  final List<String> morningMeds;
  const MealMedAnalysis({
    required this.mealType,
    required this.foods,
    required this.risk,
    required this.summary,
    required this.items,
    required this.morningMeds,
  });
}

List<Medication> morningMedications(List<Medication> all) {
  return all.where((m) {
    final times = getMedicationDoseTimes(m);
    for (final t in times) {
      final parsed = parseDailyTime(t);
      if (parsed != null && parsed.$1 < 12) return true;
    }
    return false;
  }).toList();
}

bool medCategoryMatchesKind(String category, String kind) {
  if (category == MedicationCategory.diabetes && kind == FoodImpactKind.sugar) return true;
  if (category == MedicationCategory.pressure && kind == FoodImpactKind.pressure) return true;
  if (category == MedicationCategory.heart && kind == FoodImpactKind.heart) return true;
  if (category == MedicationCategory.general) return true;
  return false;
}

String timingAdviceFor(String mealType) {
  if (mealType == FoodMealType.breakfast) {
    return 'اترك فاصلا 30-60 دقيقة بين الدواء والفطور، والدواء بالماء فقط';
  }
  if (mealType == FoodMealType.lunch) {
    return 'الغداء بعيد عن الدواء - حافظ على الكمية حتى لا يرتفع السكر مساء';
  }
  if (mealType == FoodMealType.dinner) {
    return 'العشاء خفيف ومبكر قبل النوم بساعتين';
  }
  return 'باعد بين الدواء والوجبة الخفيفة بساعة';
}

const List<PortionRule> kPortionRules = [
  PortionRule(keywords: ['خبز أبيض', 'أرز أبيض', 'معكرونة', 'مكرونة'], amount: 'نصف الكمية فقط واكمل بالخضار', alternative: 'خبز اسمر / شوفان / برغل'),
  PortionRule(keywords: ['حلويات', 'شوكولات', 'كيك', 'بسكويت'], amount: 'قطعة صغيرة مرتين اسبوعيا كحد اقصى', alternative: 'فاكهة طازجة او تمرة مع مكسرات'),
  PortionRule(keywords: ['عصير', 'غازية', 'كولا'], amount: 'نصف كوب صغير فقط وليس مع الدواء', alternative: 'ماء وليمون او فاكهة كاملة'),
  PortionRule(keywords: ['تمر', 'عسل', 'مربى'], amount: '1-3 تمرات كحد اقصى وملعقة عسل صغيرة', alternative: 'تفاح او برتقال مع زبادي'),
  PortionRule(keywords: ['بطاطس', 'بطاطا', 'شبس', 'فرايز'], amount: 'حبة صغيرة مسلوقة بدل المقلية', alternative: 'بطاطا حلوة مشوية او خضار'),
  PortionRule(keywords: ['مخلل', 'ملح'], amount: 'ملعقة صغيرة فقط وبدون ملح اضافي', alternative: 'سلطة بليمون وزعتر بدون ملح'),
  PortionRule(keywords: ['مقلي'], amount: 'قطعة صغيرة واحدة وازل الطبقة المقلية', alternative: 'مشوي بالفرن بزيت زيتون'),
  PortionRule(keywords: ['زبدة', 'سمن', 'كريمة'], amount: 'ملعقة صغيرة واحدة فقط', alternative: 'زيت زيتون بكمية قليلة'),
  PortionRule(keywords: ['برجر', 'شاورما', 'بيتزا', 'فاست فود'], amount: 'نصف ساندويتش او شريحتين صغيرتين وبدون مقليات', alternative: 'ساندويتش بيتي بخبز اسمر ودجاج مشوي'),
  PortionRule(keywords: ['لانشون', 'سجق', 'نقانق', 'معلبات', 'كاتشب'], amount: 'تجنبها مع دواء الضغط او نصف العلبة فقط', alternative: 'دجاج مسلوق / بيض / فول'),
  PortionRule(keywords: ['جبن مالح', 'جبن قديم'], amount: 'قطعة صغيرة وانقعها بالماء', alternative: 'جبن قليل الملح او قريش'),
  PortionRule(keywords: ['لحوم حمراء', 'بفتيك', 'ضأن'], amount: 'قطعة بحجم الكف بدون دهن مرتين اسبوعيا', alternative: 'سمك او دجاج او عدس'),
];

const kDefaultAmount = 'كمية معتدلة: ربع الطبق نشويات وربع بروتين ونصف خضار';
const kDefaultAlternative = 'خضار طازجة مع بروتين خفيف';

class PortionRule {
  final List<String> keywords;
  final String amount;
  final String alternative;
  const PortionRule({required this.keywords, required this.amount, required this.alternative});
}
MealMedAnalysis analyzeMealWithMeds({required String mealType, required List<String> foods, required List<Medication> morningMeds}) {
  final medNames = morningMeds.map((m) => m.name).toList();
  if (foods.isEmpty) {
    return MealMedAnalysis(mealType: mealType, foods: const [], risk: MealRisk.none, summary: 'لا توجد اصناف مسجلة بعد.', items: const [], morningMeds: medNames);
  }
  var hits = 0;
  final items = <FoodPortionAdvice>[];
  for (final f in foods) {
    final concerns = analyzeFood(f);
    final rel = morningMeds.isEmpty ? concerns : concerns.where((c) => morningMeds.any((m) => medCategoryMatchesKind(m.category, c.kind))).toList();
    if (rel.isNotEmpty) hits++;
    final rule = findPortionRule(f);
    items.add(FoodPortionAdvice(foodName: f, amountAdvice: rule?.amount ?? kDefaultAmount, alternative: rule?.alternative ?? kDefaultAlternative, timingAdvice: morningMeds.isEmpty ? 'لا يوجد دواء صباحي - التزم بالكمية' : timingAdviceFor(mealType), kinds: rel.map((c) => c.kind).toList()));
  }
  String risk;
  if (hits == 0) { risk = MealRisk.none; }
  else if (mealType == FoodMealType.breakfast) { risk = MealRisk.high; }
  else if (mealType == FoodMealType.lunch) { risk = hits >= 2 ? MealRisk.high : MealRisk.medium; }
  else if (mealType == FoodMealType.dinner) { risk = hits >= 2 ? MealRisk.medium : MealRisk.low; }
  else { risk = MealRisk.low; }
  String summary;
  if (hits == 0) {
    summary = morningMeds.isEmpty ? 'وجبة متوازنة.' : 'لا تعارض مع دواء الصباح.';
  } else {
    summary = 'يوجد $hits اصناف قد تؤثر على دواء الصباح - قلل الكمية او استبدل بالبديل.';
  }
  return MealMedAnalysis(mealType: mealType, foods: foods, risk: risk, summary: summary, items: items, morningMeds: medNames);
}

Map<String, MealMedAnalysis> analyzeDayMealsWithMeds({required List<FoodEntry> entries, required List<Medication> medications}) {
  final morning = morningMedications(medications);
  List<String> of(String meal) => entries.where((e) => e.mealType == meal).map((e) => e.name).toList();
  return {
    FoodMealType.breakfast: analyzeMealWithMeds(mealType: FoodMealType.breakfast, foods: of(FoodMealType.breakfast), morningMeds: morning),
    FoodMealType.lunch: analyzeMealWithMeds(mealType: FoodMealType.lunch, foods: of(FoodMealType.lunch), morningMeds: morning),
    FoodMealType.dinner: analyzeMealWithMeds(mealType: FoodMealType.dinner, foods: of(FoodMealType.dinner), morningMeds: morning),
  };
}


PortionRule? findPortionRule(String foodName) {
  final lowered = foodName.toLowerCase();
  for (final r in kPortionRules) {
    if (r.keywords.any((k) => lowered.contains(k))) return r;
  }
  return null;
}



