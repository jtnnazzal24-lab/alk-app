/// جدول نصوص الواجهة.
///
/// العربية هي لغة المصدر الوحيدة داخل الشيفرة (كل النصوص مكتوبة بالعربية)،
/// وواجهة `.tr` تعرض الترجمة **المخزَّنة على الجهاز** عندما تكون لغة الواجهة
/// غير العربية (فرنسية مثلاً).
///
/// [TranslationTable] جدول في الذاكرة فقط: لا شبكة ولا ملفات، وتعبئته مسؤولية
/// `DictionaryTranslationService` الذي يقرأ القاموس العربي
/// (`assets/source_dictionary.json`)، يترجمه مرة واحدة، ثم يخزّنه على الجهاز
/// ليُقرأ في كل تشغيل لاحق بدل إعادة الترجمة.
library;

/// جدول ترجمة جاهز في الذاكرة: نص عربي ← نص بلغة الواجهة.
class TranslationTable {
  /// أنماط متغيرات Dart داخل النصوص: `$name` أو `${expression}`.
  ///
  /// النصوص التي تحتوي متغيرات تُعالَج كقوالب: يُبنى منها تعبير مطابقة يُستخرج
  /// منه ما وضعه التطبيق وقت العرض (اسم الدواء، رقم القراءة، ...) ثم يُعاد
  /// تركيبها في الترجمة عبر علامات `[[0]]` و`[[1]]` ...
  static final RegExp placeholderPattern =
      RegExp(r'\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*');

  /// طول البادئة التي تُفهرَس بها القوالب (تسريع البحث).
  static const int prefixLength = 8;

  static final RegExp _spacedMarker = RegExp(r'\[\[\s*(\d+)\s*\]\]');

  final Map<String, String> _exact = <String, String>{};
  final Map<String, List<_TextTemplate>> _templates =
      <String, List<_TextTemplate>>{};

  /// قوالب بادئتها الثابتة أقصر من [prefixLength] — تُفحص دائماً.
  final List<_TextTemplate> _shortTemplates = <_TextTemplate>[];

  int _templateCount = 0;

  /// لغة الواجهة الحالية — 'ar' تعني العرض من المصدر مباشرة.
  String language = 'ar';

  /// 0 = لا ترجمة بعد، 1 = ترجمة جزئية، 2 = ترجمة كاملة.
  ///
  /// لا تتغيّر [generation] عند كل دفعة ترجمة، بل عند الانتقال بين المراحل فقط،
  /// لتُستخدم في إعادة بناء شجرة الواجهة مرة واحدة عند جهوز الترجمة.
  int generation = 0;

  /// عدد النصوص المترجمة المتاحة للعرض.
  int get size => _exact.length + _templateCount;
  int get exactCount => _exact.length;
  int get templateCount => _templateCount;

  /// هل يُعرض النص المترجم بدل العربي؟
  bool get active => language != 'ar' && size > 0;

  /// يغيّر لغة الواجهة؛ وعند تغيّرها يُفرَّغ الجدول حتى لا تُخلط لغتان.
  void setLanguage(String tag) {
    final next = _languageCode(tag);
    if (next == language) return;
    language = next;
    clear();
  }

  static String _languageCode(String tag) {
    final code = tag.trim().toLowerCase();
    final dash = code.indexOf('-');
    final base = dash < 0 ? code : code.substring(0, dash);
    return base.isEmpty ? 'ar' : base;
  }

  /// يفرّغ الجدول (يمرّر النصوص العربية كما هي).
  void clear() {
    _exact.clear();
    _templates.clear();
    _shortTemplates.clear();
    _templateCount = 0;
    generation = 0;
  }

  /// يضيف مجموعة نصوص مترجمة (نص عربي ← ترجمة بلغة الواجهة).
  void load(Map<String, String> strings) {
    strings.forEach(put);
  }

  /// يضيف نصاً واحداً؛ المكرر يُحدَّث بآخر ترجمة.
  void put(String source, String target) {
    if (source.isEmpty || target.isEmpty) return;
    final normalized = normalizeMarkers(target);
    if (normalized == source) return; // ترجمة مطابقة للأصل — لا فائدة منها
    final slots = placeholderPattern.allMatches(source).length;
    if (slots == 0) {
      _exact[source] = normalized;
      return;
    }
    final pattern = _buildPattern(source);
    if (pattern == null) return;
    // نصٌّ هو متغير واحد فقط (مثل `$x`) يطابق أي نص — لا يصلح قالباً.
    final first = placeholderPattern.firstMatch(source);
    if (slots == 1 &&
        first != null &&
        first.start == 0 &&
        first.end == source.length) {
      return;
    }
    final template = _TextTemplate(pattern, normalized, slots);
    final prefix = _literalPrefix(source);
    if (prefix.length >= prefixLength) {
      _templates.putIfAbsent(prefix, () => <_TextTemplate>[]).add(template);
    } else {
      _shortTemplates.add(template);
    }
    _templateCount++;
  }

  /// توحيد المسافات داخل علامات المتغيرات (`[[ 0 ]]` ← `[[0]]`).
  static String normalizeMarkers(String value) =>
      value.replaceAllMapped(_spacedMarker, (match) => '[[${match.group(1)}]]');
  /// أقصى عمق لترجمة القيم المُدرَجة داخل النصوص (قوالب داخل قوالب).
  static const int _maxValueDepth = 1;

  /// يعيد الترجمة المخزَّنة لـ[text]، أو النص نفسه عند غيابها.
  String lookup(String text) => _lookup(text, 0);

  String _lookup(String text, int depth) {
    if (text.isEmpty || !active) return text;
    final direct = _exact[text];
    if (direct != null) return direct;
    final fromTemplate = _lookupTemplate(text, depth);
    if (fromTemplate != null) return fromTemplate;
    // بعض النصوص تُبنى بمسافات زائدة (نهاية سطر قبل متغير مثلاً).
    final trimmed = text.trim();
    if (trimmed != text && trimmed.isNotEmpty) {
      final exactTrimmed = _exact[trimmed];
      if (exactTrimmed != null) return exactTrimmed;
      final templateTrimmed = _lookupTemplate(trimmed, depth);
      if (templateTrimmed != null) return templateTrimmed;
    }
    return text;
  }

  String? _lookupTemplate(String text, int depth) {
    if (_templateCount == 0) return null;
    for (final template in _shortTemplates) {
      final filled = _fill(template, text, depth);
      if (filled != null) return filled;
    }
    final keyLength = text.length < prefixLength ? text.length : prefixLength;
    if (keyLength == 0) return null;
    final bucket = _templates[text.substring(0, keyLength)];
    if (bucket == null) return null;
    for (final template in bucket) {
      final filled = _fill(template, text, depth);
      if (filled != null) return filled;
    }
    return null;
  }

  /// يُركّب نص الترجمة: يستبدل `[[i]]` بالقيمة التي أخذها التطبيق من النص.
  /// يعيد null إذا فقدت الترجمة أحد المتغيرات (فيُعرض النص العربي بدلاً منها).
  String? _fill(_TextTemplate template, String text, int depth) {
    final match = template.pattern.firstMatch(text);
    if (match == null) return null;
    var out = template.target;
    for (var i = 0; i < template.slots; i++) {
      final marker = RegExp('\\[\\[\\s*$i\\s*\\]\\]');
      if (!marker.hasMatch(out)) return null;
      final value = match.group(i + 1) ?? '';
      // القيم المُدرَجة (اسم الدواء، اسم التمرين، نص النصيحة، نوع الوجبة...)
      // تُترجم أيضاً إذا وُجدت في القاموس، وإلا تبقى كما كتبها المستخدم.
      out = out.replaceAll(
        marker,
        depth >= _maxValueDepth ? value : _lookup(value, depth + 1),
      );
    }
    return out;
  }

  /// يبني تعبير مطابقة كامل النص مع أقواس التقاط مكان كل متغير.
  RegExp? _buildPattern(String source) {
    final buffer = StringBuffer('^');
    var last = 0;
    var slots = 0;
    for (final match in placeholderPattern.allMatches(source)) {
      buffer.write(RegExp.escape(source.substring(last, match.start)));
      buffer.write(r'([\s\S]*?)');
      last = match.end;
      slots++;
    }
    if (slots == 0) return null;
    buffer.write(RegExp.escape(source.substring(last)));
    buffer.write(r'$');
    return RegExp(buffer.toString());
  }

  /// الجزء الثابت من بداية النص قبل أول متغير (مفتاح الفهرس).
  String _literalPrefix(String source) {
    final match = placeholderPattern.firstMatch(source);
    final literal = match == null ? source : source.substring(0, match.start);
    return literal.length <= prefixLength
        ? literal
        : literal.substring(0, prefixLength);
  }
}

class _TextTemplate {
  _TextTemplate(this.pattern, this.target, this.slots);

  final RegExp pattern;
  final String target;
  final int slots;
}

/// نصوص التطبيق. العربية هي لغة المصدر والعرض الافتراضية.
class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  /// لغة الواجهة الحالية (عند تغييرها تُفرَّغ الترجمة المخزَّنة في الذاكرة).
  static String get current => table.language;
  static set current(String tag) => table.setLanguage(tag);

  /// جدول الترجمة النشط على الجهاز.
  static final TranslationTable table = TranslationTable();
}

/// يعرض النص بلغة الواجهة: الترجمة المخزَّنة إن وُجدت، وإلا النص العربي كما هو.
extension Tr on String {
  String get tr {
    final table = AppStrings.table;
    if (!table.active) return this;
    return table.lookup(this);
  }
}

