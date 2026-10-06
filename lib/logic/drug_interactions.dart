/// قاعدة التفاعلات الدوائية المحلية (تعمل دون إنترنت).
///
/// تنفيذ بندَي وثيقة التطوير «3.3 تحذير التفاعلات الموسع» و«21.1 قاعدة
/// التفاعلات الدوائية»: قواعد مُطّرقة داخل التطبيق بلا شبكة ولا خادم،
/// وتغطي: دواء–دواء، دواء–طعام، دواء–وقت، دواء–حالة.
///
/// ⚠️ تثقيف وليس استشارة: التطبيق لا يقترح إيقاف أو تعديل جرعة أبداً.
library;

import '../models/sandy_data.dart';

/// مستويات خطورة التفاعل.
class InteractionSeverity {
  static const high = 'high';
  static const medium = 'medium';
  static const low = 'low';
  static const all = [high, medium, low];

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

  static String label(String v) {
    switch (v) {
      case high:
        return 'مرتفع — انتبه';
      case medium:
        return 'متوسط';
      default:
        return 'منخفض';
    }
  }
}

/// أنواع التفاعل (للتجميع في الواجهة).
class InteractionKind {
  static const drugDrug = 'drug-drug';
  static const drugFood = 'drug-food';
  static const drugTime = 'drug-time';
  static const drugCondition = 'drug-condition';

  static String label(String v) {
    switch (v) {
      case drugDrug:
        return 'دواء مع دواء';
      case drugFood:
        return 'دواء مع طعام';
      case drugTime:
        return 'توقيت الجرعة';
      case drugCondition:
        return 'دواء مع حالتك';
      default:
        return 'تنبيه';
    }
  }
}

/// تنبيه تفاعل واحد جاهز للعرض.
class DrugInteraction {
  const DrugInteraction({
    required this.severity,
    required this.kind,
    required this.title,
    required this.detail,
  });

  final String severity;
  final String kind;
  final String title;
  final String detail;
}

/// مجموعات الأدوية: كلمة مفتاحية تكفي للتعرّف على المادة أو العلامة.
class _Group {
  const _Group(this.id, this.keywords);
  final String id;
  final List<String> keywords;
}

const List<_Group> _groups = <_Group>[
  _Group('anticoagulant', ['وارفارين', 'كومادين', 'warfarin', 'coumadin']),
  _Group('antiplatelet', [
    'أسبرين', 'اسبرين', 'acetylsalicylic', 'كلوبيدوجريل', 'بلافكس',
    'clopidogrel', 'aspirin',
  ]),
  _Group('nsaid', [
    'إيبوبروفين', 'ابوبروفين', 'بروفين', 'ادويل', 'ديكلوفيناك', 'فولتارين',
    'نابروكسين', 'ibuprofen', 'diclofenac', 'naproxen', 'meloxicam',
  ]),
  _Group('acei', [
    'إنالابريل', 'انالابريل', 'راميبريل', 'كابتوبريل', 'lisinopril',
    'enalapril', 'ramipril', 'captopril',
  ]),
  _Group('arb', [
    'لوسارتان', 'تلميسارتان', 'فالسارتان', 'اردان', 'losartan',
    'telmisartan', 'valsartan',
  ]),
  _Group('metformin', [
    'ميتفورمين', 'جلوكوفاج', 'فورتاميت', 'جلوسيف', 'metformin', 'glucophage',
  ]),
  _Group('sulfonylurea', [
    'جليمبيز', 'جلورين', 'جلاديج', 'جليبنكلاميد', 'glibenclamide',
    'glimepiride', 'glipizide',
  ]),
  _Group('insulin', [
    'أنسولين', 'انسولين', 'لانتوس', 'ليفيمي', 'نوفورابيد', 'insulin', 'lantus',
  ]),
  _Group('levothyroxine', [
    'ليفوثيروكسين', 'اليتروكس', 'إليتروكس', 'بيوتيكس', 'levothyroxine',
    'euthyrox', 'thyroxine',
  ]),
  _Group('statin', [
    'أتورفاستاتين', 'اتورفاستاتين', 'روسوفاستاتين', 'سيمفاستاتين', 'كريستور',
    'atorvastatin', 'rosuvastatin', 'simvastatin',
  ]),
  _Group('iron', ['حديد', 'فروسلفات', 'فروجر', 'فيروك', 'ferrous', 'iron']),
  _Group('ppi', [
    'أوميبرازول', 'وميبرازول', 'لانسوبازول', 'بانتوبرازول', 'نيكسوم',
    'omeprazole', 'pantoprazole', 'lansoprazole',
  ]),
  _Group('quinolone', [
    'سيبروفلوكساسين', 'ليفوفلوكساسين', 'نورفلوكساسين', 'ciprofloxacin',
    'levofloxacin', 'norfloxacin',
  ]),
  _Group('tetracycline', [
    'دوكسيسايكلين', 'تتراسيكلين', 'دوكسي', 'doxycycline', 'tetracycline',
  ]),
  _Group('ssri', [
    'فلوكستين', 'سيرترالين', 'سيرتالين', 'باروكستين', 'fluoxetine',
    'sertraline', 'paroxetine',
  ]),
  _Group('digoxin', ['ديجوكسين', 'digoxin', 'lanoxin']),
  _Group('amiodarone', ['أميودارون', 'اميودارون', 'كوردارون', 'amiodarone']),
  _Group('diuretic', [
    'فوروسيميد', 'لاسكس', 'هيدروكلوروثيازيد', 'furosemide',
    'hydrochlorothiazide', 'spironolactone', 'سبيرونولاكتون',
  ]),
  _Group('steroid', [
    'كورتيزون', 'بريدنيزولون', 'بريدنيزول', 'ديكساميثازون', 'prednisolone',
    'prednisone', 'dexamethasone',
  ]),
  _Group('betaBlocker', [
    'بروبرانولول', 'ميتوبرولول', 'بيسوبرولول', 'اتينولول', 'propranolol',
    'metoprolol', 'bisoprolol', 'atenolol',
  ]),
  _Group('decongestant', [
    'سودوإيفدرين', 'سودوافدرين', 'افدران', 'pseudoephedrine', 'phenylephrine',
  ]),
];

bool _matches(String name, _Group g) {
  final n = name.toLowerCase().trim();
  if (n.isEmpty) return false;
  for (final k in g.keywords) {
    if (n.contains(k.toLowerCase())) return true;
  }
  return false;
}

/// المجموعات الدوائية الموثّقة من قائمة أدوية المريض.
Set<String> presentDrugGroups(List<Medication> medications) {
  final found = <String>{};
  for (final m in medications) {
    for (final g in _groups) {
      if (_matches(m.name, g)) found.add(g.id);
    }
  }
  return found;
}

// ── كلمات الأطعمة التي تُثير تنبيهاً ──────────────────────────────────────
const List<String> _dairy = [
  'حليب', 'لبن', 'جبن', 'زبادي', 'قشطة', 'ألبان', 'milk', 'cheese', 'yogurt',
  'dairy', 'calcium', 'كالسيوم',
];
const List<String> _teaCoffee = [
  'شاي', 'قهوة', 'قهوه', 'نسكافيه', 'tea', 'coffee', 'espresso',
];
const List<String> _leafy = [
  'سبانخ', 'خس', 'كرنب', 'بروكلي', 'ملوخية', 'بقدونس', 'خضار ورقي',
  'spinach', 'kale', 'broccoli', 'cabbage', 'lettuce',
];
const List<String> _grapefruit = [
  'جريب فروت', 'جريبفروت', 'برتقال مر', 'grapefruit',
];
const List<String> _alcohol = [
  'كحول', 'خمر', 'بيرة', 'نبيذ', 'الكحول', 'alcohol', 'beer', 'wine',
];
const List<String> _processedMeat = [
  'سوسيس', 'لانشون', 'مرتديلا', 'بسطرمة', 'لحوم محفوظة', 'sausage', 'salami',
];
const List<String> _soy = ['صويا', 'سويا', 'توفو', 'soy', 'soya'];
const List<String> _salty = [
  'مخلل', 'مملح', 'شيبس', 'وجبات سريعة', 'pickled', 'chips', 'fast food',
];
const List<String> _herbal = [
  'عشبة', 'حبة البركة', 'جنسنج', 'ينسون', 'حبوب عشبية',
];

bool _hasFood(List<String> foods, List<String> keywords) {
  for (final raw in foods) {
    final f = raw.toLowerCase().trim();
    if (f.isEmpty) continue;
    for (final k in keywords) {
      if (f.contains(k.toLowerCase())) return true;
    }
  }
  return false;
}

/// صنف قاعدة التفاعل.
class _Rule {
  const _Rule({
    required this.kind,
    required this.severity,
    required this.title,
    required this.detail,
    this.all = const <String>{},
    this.any = const <String>{},
    this.none = const <String>{},
    this.food,
    this.condition,
  });

  final String kind;
  final String severity;
  final String title;
  final String detail;

  /// كل هذه المجموعات لازم تكون موجودة.
  final Set<String> all;

  /// تكفي مجموعة واحدة منها.
  final Set<String> any;

  /// أي مجموعة موجودة منها تُلغي القاعدة.
  final Set<String> none;

  /// كلمات طعام تُشترط (تُحوّلها القاعدة إلى تنبيه غذائي).
  final List<String>? food;

  /// شرط الحالة المرضية: pressure | kidney | diabetes | asthma.
  final String? condition;
}

const List<_Rule> _drugRules = <_Rule>[
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.high,
    title: 'الأسبرين مع الوارفارين',
    detail:
        'الجمع يرفع خطر النزيف بوضوح. لا توقف أي دواء بنفسك — راجع طبيبك لضبط حاجة الأسبرين.',
    all: {'anticoagulant', 'antiplatelet'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.high,
    title: 'مميع مع مسكن ألم (إيبوبروفين أو ديكلوفيناك)',
    detail:
        'مضادات الالتهاب مع مميّعات الدم تزيد النزيف وتهيج المعدة. استشر طبيبك قبل أي مسكن.',
    all: {'anticoagulant', 'nsaid'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.medium,
    title: 'الأسبرين مع مسكن الالتهاب',
    detail:
        'زيادة خطر النزيف وتهيّج المعدة. تجنّب الجمع دون استشارة ولا تُستخدم المسكنتات يومياً.',
    all: {'antiplatelet', 'nsaid'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.medium,
    title: 'دواء الضغط مع مسكن الالتهاب',
    detail:
        'مسكنات الالتهاب تُقلّل أثر دواء الضغط وقد تجهد الكلى. لا تُستخدم بانتظام دون سؤال الطبيب.',
    all: {'nsaid'},
    any: {'acei', 'arb'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.medium,
    title: 'الميتفورمين مع الكورتيزون',
    detail:
        'الكورتيزون يرفع السكر فيُضعف جزئياً أثر الميتفورمين. قس السكر أكثر من المعتاد واستشر طبيبك.',
    all: {'metformin', 'steroid'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.medium,
    title: 'المميع مع دواء الاكتئاب',
    detail:
        'بعض أدوية الاكتئاب تُبطئ التخثر فتزيد خطر النزيف البسيط. أخبر طبيبك بالمزيج.',
    all: {'anticoagulant', 'ssri'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.high,
    title: 'الليفوثيروكسين مع مكملات الحديد',
    detail: 'الحديد يمنع امتصاص هرمون الغدة لساعات. افصل بينهما بـ4 ساعات على الأقل.',
    all: {'levothyroxine', 'iron'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.medium,
    title: 'الليفوثيروكسين مع مانح حمض المعدة',
    detail: 'قد يقلّل مانحات الحمض امتصاص هرمون الغدة. خذه صائماً ونبّه طبيبك.',
    all: {'levothyroxine', 'ppi'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.high,
    title: 'الديجوكسين مع الأميودارون',
    detail:
        'يرفع مستوى الديجوكسين وقد يخلّ في نظم القلب. متابعة متكرّرة عند طبيبك إلزامية.',
    all: {'digoxin', 'amiodarone'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.medium,
    title: 'مضاد حيوي مع مدرات البول',
    detail: 'قد يحفّز المضاد هبوط السكر لدى مرضى السكري — راقب السكر خلال العلاج.',
    all: {'quinolone', 'diuretic'},
  ),
  _Rule(
    kind: InteractionKind.drugDrug,
    severity: InteractionSeverity.medium,
    title: 'مضاد حيوي مع الحديد',
    detail: 'يحتاجان فصلاً بساعتين على الأقل ليعمل كل منهما كما ينبغي.',
    all: {'tetracycline', 'iron'},
  ),
  _Rule(
    kind: InteractionKind.drugTime,
    severity: InteractionSeverity.high,
    title: 'الليفوثيروكسين على معدة فارغة',
    detail: 'خذه قبل الفطور بنصف ساعة إلى ساعة، بعيداً عن الشاي والحليب.',
    all: {'levothyroxine'},
  ),
  _Rule(
    kind: InteractionKind.drugTime,
    severity: InteractionSeverity.low,
    title: 'الميتفورمين مع الوجبة',
    detail: 'تناوله مع الطعام أو بعده مباشرة لتقليل الإسهال والغثيان.',
    all: {'metformin'},
  ),
  _Rule(
    kind: InteractionKind.drugTime,
    severity: InteractionSeverity.low,
    title: 'مانح حمض قبل الأكل',
    detail: 'خذ الجرعة قبل الفطور بنصف ساعة للحصول على أقصى أثر.',
    all: {'ppi'},
  ),
  _Rule(
    kind: InteractionKind.drugTime,
    severity: InteractionSeverity.low,
    title: 'الأسبرين بعد الطعام',
    detail: 'تناوله بعد الأكل مباشرة لحماية المعدة من التهيج.',
    all: {'antiplatelet'},
    none: {'anticoagulant'},
  ),
];

/// قواعد دواء–طعام (تطبّق عند تطابق الوجبات المسجَّلة).
const List<_Rule> _foodRules = <_Rule>[
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.high,
    title: 'الألبان مع الليفوثيروكسين',
    detail:
        'الكالسيوم في الحليب واللبن والجبن يمنع امتصاص هرمون الغدة. افصل بينهما بـ4 ساعات.',
    all: {'levothyroxine'},
    food: _dairy,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.medium,
    title: 'الشاي أو القهوة مع الليفوثيروكسين',
    detail: 'المواد الضاربة في الشاي تقلّل الامتصاص — انتظر نصف ساعة بعد الدواء.',
    all: {'levothyroxine'},
    food: _teaCoffee,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.medium,
    title: 'الصويا مع الليفوثيروكسين',
    detail: 'الصويا قد تقلّل امتصاص الدواء — تناوله بين الوجبات إن أمكن.',
    all: {'levothyroxine'},
    food: _soy,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.high,
    title: 'الخضار الورقية مع الوارفارين',
    detail:
        'فيتامين K في السبانخ والخس والبروكلي يُبطل جزءاً من أثر الوارفارين. المهم ثبات الكمية لا حذفها — ناقشها مع طبيبك.',
    all: {'anticoagulant'},
    food: _leafy,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.high,
    title: 'الأعشاب المكمّلة مع مميع الدم',
    detail: 'بعض الأعشاب تزيد خطر النزيف مع الوارفارين — اسأل الصيدلي قبل أي مكمّل.',
    all: {'anticoagulant'},
    food: _herbal,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.medium,
    title: 'جريب فروت مع مثبّتات الكوليسترول',
    detail:
        'الجريب فروت يرفع مستوى الدواء في الدم ويزيده أثراً وآثاراً جانبية. ابقَ عنه بعد الاستشارة.',
    all: {'statin'},
    food: _grapefruit,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.high,
    title: 'الكحول مع الميتفورمين',
    detail:
        'يرفع خطر الهبوط الحاد للسكر وتسمّم الحمض عند الإفراط. تجنّب الكحول أثناء تناوله.',
    all: {'metformin'},
    food: _alcohol,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.medium,
    title: 'الشاي أو القهوة مع الحديد',
    detail: 'تقلّل امتصاص الحديد إلى النصف — افصل ساعتين عن الدواء.',
    all: {'iron'},
    food: _teaCoffee,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.medium,
    title: 'الألبان مع الحديد',
    detail: 'الكالسيوم يمنع امتصاص الحديد — افصل بينهما بساعتين.',
    all: {'iron'},
    food: _dairy,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.medium,
    title: 'الألبان مع هذا المضاد الحيوي',
    detail: 'الكالسيوم يرتبط بالمضاد ويمتصه — تناول الدواء قبل الألبان بساعتين.',
    any: {'quinolone', 'tetracycline'},
    food: _dairy,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.medium,
    title: 'اللحوم المحفوظة مع الأسبرين',
    detail: 'اللحوم المحفوظة تزيد تهيّج المعدة مع الأسبرين — قلّل منها.',
    all: {'antiplatelet'},
    food: _processedMeat,
  ),
  _Rule(
    kind: InteractionKind.drugFood,
    severity: InteractionSeverity.low,
    title: 'الأطعمة المملحة مع مدرات البول',
    detail: 'الملح يُوازن تأثير المدرات فيرفع الضغط — قلّل المخللات والوجبات الجاهزة.',
    all: {'diuretic'},
    food: _salty,
  ),
];

/// قواعد دواء–حالة مرضية.
const List<_Rule> _conditionRules = <_Rule>[
  _Rule(
    kind: InteractionKind.drugCondition,
    severity: InteractionSeverity.high,
    title: 'مسكن الالتهاب مع الضغط',
    detail:
        'إيبوبروفين أو ديكلوفيناك قد يرفع الضغط ويجهد الكلى. استعمله أقصر فترة ممكنة بعد سؤال الطبيب.',
    all: {'nsaid'},
    condition: 'pressure',
  ),
  _Rule(
    kind: InteractionKind.drugCondition,
    severity: InteractionSeverity.high,
    title: 'مسكن الالتهاب مع ضعف الكلى',
    detail:
        'مسكنات الالتهاب قد تُجهد الكلى أكثر. لا تُستخدم يومياً دون متابعة وظائف الكلى.',
    all: {'nsaid'},
    condition: 'kidney',
  ),
  _Rule(
    kind: InteractionKind.drugCondition,
    severity: InteractionSeverity.medium,
    title: 'منفّّح الأنف مع الضغط المرتفع',
    detail: 'مذيبات الزكام ترفع الضغط — اختر بديلاً من الصيدلي وسجّل قراءاتك.',
    all: {'decongestant'},
    condition: 'pressure',
  ),
  _Rule(
    kind: InteractionKind.drugCondition,
    severity: InteractionSeverity.medium,
    title: 'الكورتيزون مع السكري',
    detail: 'يرفع السكر بوضوح — قس أكثر من المعتاد ونخّص طبيبك بجرعتك.',
    all: {'steroid'},
    condition: 'diabetes',
  ),
  _Rule(
    kind: InteractionKind.drugCondition,
    severity: InteractionSeverity.medium,
    title: 'الكورتيزون مع الضغط',
    detail: 'قد يرفع الكورتيزون الضغط — قِس ضغطك يومياً أثناء أزمته.',
    all: {'steroid'},
    condition: 'pressure',
  ),
  _Rule(
    kind: InteractionKind.drugCondition,
    severity: InteractionSeverity.medium,
    title: 'حاجب بيتا مع الربو',
    detail: 'بعض الحواجز تضيّق الشعب الهوائية. لا توقف الدواء — أخبر طبيبك بالأعراض.',
    all: {'betaBlocker'},
    condition: 'asthma',
  ),
  _Rule(
    kind: InteractionKind.drugCondition,
    severity: InteractionSeverity.medium,
    title: 'الميتفورمين مع ضعف الكلى',
    detail: 'يتطلّب فحص وظائف الكلى دورياً قبل الاستمرار على الجرعة الحالية.',
    all: {'metformin'},
    condition: 'kidney',
  ),
];

bool _applies(_Rule r, Set<String> present) {
  if (r.all.isNotEmpty && !present.containsAll(r.all)) return false;
  if (r.any.isNotEmpty && !r.any.any(present.contains)) return false;
  if (r.none.isNotEmpty && r.none.any(present.contains)) return false;
  return r.all.isNotEmpty || r.any.isNotEmpty;
}

String _conditionKey(String condition) {
  final c = condition.toLowerCase();
  if (c.contains('كلى') || c.contains('كلوي') || c.contains('renal')) {
    return 'kidney';
  }
  if (c.contains('ربو') || c.contains('تنفسي') || c.contains('asthma')) {
    return 'asthma';
  }
  if (c.contains('سكري') || c.contains('diabet') || c.contains('sugar')) {
    return 'diabetes';
  }
  if (c.contains('ضغط') || c.contains('ارتفاع') || c.contains('hypert')) {
    return 'pressure';
  }
  return '';
}

DrugInteraction _build(_Rule r) => DrugInteraction(
      severity: r.severity,
      kind: r.kind,
      title: r.title,
      detail: r.detail,
    );

/// يبني قائمة التفاعلات من الأدوية والطعام والحالة المرضية.
///
/// [medications] أدوية المريض، [condition] نص «الحالة المرضية» في الملف،
/// [foods] أسماء وجبات مسجَّلة مؤخراً (اختياري).
///
/// النتيجة مرتّبة من الأعلى خطورة إلى الأدنى وبدون تكرار.
List<DrugInteraction> findDrugInteractions({
  required List<Medication> medications,
  String condition = '',
  List<String> foods = const <String>[],
}) {
  if (medications.isEmpty) return const <DrugInteraction>[];

  final present = presentDrugGroups(medications);
  final condKey = _conditionKey(condition);
  final out = <DrugInteraction>[];

  for (final r in _drugRules) {
    if (_applies(r, present)) out.add(_build(r));
  }
  if (foods.isNotEmpty) {
    for (final r in _foodRules) {
      if (!_applies(r, present)) continue;
      if (!_hasFood(foods, r.food ?? const <String>[])) continue;
      out.add(_build(r));
    }
  }
  if (condKey.isNotEmpty) {
    for (final r in _conditionRules) {
      if (r.condition != condKey) continue;
      if (!_applies(r, present)) continue;
      out.add(_build(r));
    }
  }

  out.sort((a, b) {
    final rank = InteractionSeverity.rank(a.severity)
        .compareTo(InteractionSeverity.rank(b.severity));
    return rank != 0 ? rank : a.title.compareTo(b.title);
  });

  final seen = <String>{};
  return out.where((e) => seen.add(e.title)).toList(growable: false);
}




