/// Built-in food knowledge base for the ALK nutrition tracker.
///
/// Maps common foods (matched by Arabic keyword substrings) to the body
/// systems they can affect — blood sugar (diabetes), blood pressure, and
/// heart health — alongside plain-language advice to reduce them and
/// healthier alternatives. Educational guidance only, never a diagnosis.
library;

/// The condition/factor a food can influence.
class FoodImpactKind {
  static const sugar = 'sugar';
  static const pressure = 'pressure';
  static const heart = 'heart';

  /// Arabic label for the affected body system (used as a section heading).
  static String label(String kind) {
    switch (kind) {
      case sugar:
        return 'سكر الدم';
      case pressure:
        return 'ضغط الدم';
      case heart:
        return 'صحة القلب';
      default:
        return '';
    }
  }
}

/// A single piece of guidance associated with one food factor.
class FoodConcern {
  final String kind; // see FoodImpactKind
  final String advice;

  const FoodConcern({required this.kind, required this.advice});

  @override
  bool operator ==(Object other) =>
      other is FoodConcern && other.kind == kind;
  @override
  int get hashCode => kind.hashCode;
}

/// A food rule: if any [keywords] substring appears in the logged food name,
/// the food is considered to carry all of the [concerns].
class FoodRule {
  final List<String> keywords;
  final List<FoodConcern> concerns;

  const FoodRule({required this.keywords, required this.concerns});
}

/// Advisory summary for one analyzed food name.
class FoodAnalysis {
  final String name;
  final List<FoodConcern> concerns;

  const FoodAnalysis({required this.name, required this.concerns});

  bool get hasConcerns => concerns.isNotEmpty;

  bool affects(String kind) => concerns.any((c) => c.kind == kind);
}

/// Healthier substitutes shown alongside the advice.
const List<String> kHealthyAlternatives = [
  'الماء بدل المشروبات الغازية والعصير',
  'الخبز الأسمر والشوفان بدل الأبيض',
  'السمك الدهني (السلمون والتونة) مرتين أسبوعياً',
  'زيت الزيتون بدل الدهون المهدرجة',
  'الخضار والبقول والفواكه الطازجة',
  'المكسرات غير المملحة بدل الوجبات الخفيفة',
  'التوابل والأعشاب بدل الملح في الطهي',
];
/// Advisory guidance for foods that can raise blood sugar (diabetes).
const List<FoodConcern> _sugarConcerns = [
  FoodConcern(
    kind: FoodImpactKind.sugar,
    advice:
        'يحتمل أن يرفع سكر الدم (نشويات/سكريات). قلِّل الكمية واختر البدائل الكاملة، '
        'وقِس سكرك بعد الوجبة لتعرف أثرها عليك.',
  ),
];

/// Advisory guidance for high-sodium foods (blood pressure).
const List<FoodConcern> _pressureConcerns = [
  FoodConcern(
    kind: FoodImpactKind.pressure,
    advice:
        'غني بالملح/الصوديوم وقد يرفع ضغط الدم. قلِّل الملح والمخللات والأغذية '
        'المصنعة، وزِد الخضار الغنية بالبوتاسيوم مثل الموز والسبانخ.',
  ),
];

/// Advisory guidance for foods that burden the heart (saturated/trans fats,
/// processed meats).
const List<FoodConcern> _heartConcerns = [
  FoodConcern(
    kind: FoodImpactKind.heart,
    advice:
        'مرتبط بصحة القلب (دهون مشبعة/مقليات/لحوم معالَجة). قلِّل المقليات والدهون '
        'المشبعة، وفضِّل البروتين النباتي والأسماك.',
  ),
];
/// The catalog of food rules. Keywords are Arabic substrings matched against
/// the logged food name (case-insensitive).
const List<FoodRule> kFoodCatalog = [
  // ---- Sugar-raising (diabetes) foods ---------------------------------------
  FoodRule(
    keywords: ['سكريات', 'حلويات', 'شوكولات', 'كوكيز', 'بسكويت', 'جاتوه', 'كيك'],
    concerns: _sugarConcerns,
  ),
  FoodRule(
    keywords: ['عصير', 'غازية', 'بيبس', 'كولا', 'مشروب غازي', 'نسكافيه محلى'],
    concerns: _sugarConcerns,
  ),
  FoodRule(
    keywords: ['خبز أبيض', 'عيش أبيض', 'رز أبيض', 'أرز أبيض', 'معكرونة', 'مكرونة', 'باستا'],
    concerns: _sugarConcerns,
  ),
  FoodRule(
    keywords: ['تمور', 'تمر ', 'تمر بلح', 'عسل', 'مربى', 'مربّى'],
    concerns: _sugarConcerns,
  ),
  FoodRule(
    keywords: ['بطاطس', 'بطاطا', 'شبس', 'رقائق', 'فرايز'],
    concerns: _sugarConcerns,
  ),
  // ---- Blood-pressure (high-sodium) foods -----------------------------------
  FoodRule(
    keywords: ['مخلل', 'مخللات', 'زيتون مملح', 'ملح', 'أكل مالح'],
    concerns: _pressureConcerns,
  ),
  FoodRule(
    keywords: ['لانشون', 'بسطرمة', 'سجق', 'نقانق', 'لحم مصنع', 'برجر محضر'],
    concerns: _pressureConcerns,
  ),
  FoodRule(
    keywords: ['معلبات', 'أسماك معلبة', 'تونة معلبة', 'صلصة جاهزة', 'كاتشب', 'صويا صوص'],
    concerns: _pressureConcerns,
  ),
  FoodRule(
    keywords: ['جبن مالح', 'جبنة مالح', 'جبن قديم', 'أجبان مملحة'],
    concerns: _pressureConcerns,
  ),
  // ---- Heart-health (fats / processed) foods -------------------------------
  FoodRule(
    keywords: ['مقلي', 'مقلية', 'فقوس', 'بطاطس مقلية', 'دجاج مقلي', 'سمك مقلي'],
    concerns: _heartConcerns,
  ),
  FoodRule(
    keywords: ['زبدة', 'سمن', 'سمنة', 'كريمة', 'دهون', 'مارغرين'],
    concerns: _heartConcerns,
  ),
  FoodRule(
    keywords: ['لحوم حمراء', 'كبد', 'قلبي', 'لحم ضأن', 'بفتيك', 'بقري مدهون'],
    concerns: _heartConcerns,
  ),
  FoodRule(
    keywords: ['سجق', 'لانشون', 'بسطرمة', 'نقانق', 'لحم مصنع', 'سلامي'],
    concerns: _heartConcerns,
  ),
  // ---- Foods that can affect several systems at once ------------------------
  FoodRule(
    keywords: ['فاست فود', 'برجر', 'شاورما', 'بيتزا', 'وجبات سريعة'],
    concerns: [
      ..._sugarConcerns,
      ..._pressureConcerns,
      ..._heartConcerns,
    ],
  ),
];

/// Analyzes a food name against the catalog and returns the aggregated,
/// de-duplicated concerns that apply. Empty result means no known concern.
List<FoodConcern> analyzeFood(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) return const [];
  final lowered = normalized.toLowerCase();
  final found = <FoodConcern>[];
  for (final rule in kFoodCatalog) {
    final matched = rule.keywords.any((k) => lowered.contains(k));
    if (matched) {
      for (final concern in rule.concerns) {
        if (!found.contains(concern)) found.add(concern);
      }
    }
  }
  return found;
}

/// Convenience wrapper that returns a full [FoodAnalysis] for a name.
FoodAnalysis analyzeFoodEntry(String name) =>
    FoodAnalysis(name: name, concerns: analyzeFood(name));