import '../services/deepseek_service.dart';

/// مساعد الذكاء الاحتياطي: عند نقص المعلومات المحلية، يجلب شرحاً من
/// الذكاء الآلي (بعد أن يضيف المستخدم الـ API Key).
/// يعيد null عند غياب المفتاح أو الفشل — فيعرض التطبيق الرد المحلي.
class AiFallback {
  AiFallback._();
  static Future<String?> fetch({
    required String topic,
    required String languageTag,
    String context = '',
  }) async {
    final svc = DeepSeekService.instance;
    await svc.load();
    if (!svc.hasKey) return null;
    // اللغة للذكاء الآلي من لغة الواجهة نفسها (هاتف فرنسي ← الفرنسية).
    final code = languageTag.toLowerCase().split('-').first;
    final lang = switch (code) {
      'ar' => 'العربية',
      'zh' => '中文',
      'fr' => 'le français',
      'es' => 'el español',
      'de' => 'Deutsch',
      'pt' => 'o português',
      'it' => "l'italiano",
      'tr' => 'Türkçe',
      'ur' => 'اردو',
      _ => 'English',
    };
    final prompt = 'اشرح بإيجاز ووضوح بلغة $lang لكبير سن عن: $topic. $context '
        'بدون تشخيص طبي نهائي، وبأسلوب مطمئن ومختصر.';
    final res = await svc.chat(message: prompt);
    if (res.hasText) return res.text;
    return null;
  }

  /// هل الذكاء الآلي جاهز (يوجد مفتاح)؟
  static Future<bool> ready() async {
    await DeepSeekService.instance.load();
    return DeepSeekService.instance.hasKey;
  }
}
