/// اقتراح العافية حسب الحالة النفسية من اليوميات.
/// كل مزاج -> تمرين مفصّل + موسيقى مناسبة مع شرح سبب الاختيار.
/// يمنح المستخدم إجابة واضحة: "ماذا أفعل؟" و"لماذا هذه الموسيقى؟".
library;

class MoodWellbeing {
  final String exerciseTitle;
  final String exerciseSteps;
  final String musicTitle;
  final String musicReason; // لماذا اخترنا هذه الموسيقى لهذا المزاج
  final String musicQuery; // عبارة البحث لتشغيل الموسيقى
  final String tip;
  const MoodWellbeing({
    required this.exerciseTitle,
    required this.exerciseSteps,
    required this.musicTitle,
    required this.musicReason,
    required this.musicQuery,
    required this.tip,
  });
}

/// خريطة المزاج -> توصية (تعمل حتى بدون إنترنت/ذكاء).
MoodWellbeing wellbeingForMood(String mood) {
  final m = mood.trim();
  if (m.contains('حزين') || m.contains('مكتئب') || m.contains('قلق') || m.contains('متوتر')) {
    return const MoodWellbeing(
      exerciseTitle: 'تمرين التمدد والتنفس لتهدئة الحزن والتوتر',
      exerciseSteps:
          'خطوات واضحة، كرر مرة واحدة:\n'
          'أنت جالس على كرسي مريح. ضع يديك على فخذيك.\n'
          '1) شهيق عميق من الأنف مع عد 4 (املأ رئتيك بالهواء).\n'
          '2) احتفظ بالهواء مع عد 4.\n'
          '3) زفير بطيء من الفم مع عد 6 (أفرغ الهواء كله).\n'
          'كرر ذلك 5 مرات ببطء.\n'
          '4) بعدها: ارفع كتفيك نحو أذنيك وعد 3، ثم أرخِهما. كرر 5 مرات.\n'
          '5) أخيراً أدر رأسك يميناً ثم يساراً ببطء 3 مرات.',
      musicTitle: 'موسيقى مبهجة هادئة',
      musicReason:
          'اخترنا موسيقى مبهجة هادئة لأنها تخفف الشعور بالحزن والتوتر '
              'وترفع معنوياتك تدريجياً دون أن تزعجك.',
      musicQuery: 'uplifting calm relaxing music for seniors',
      tip: 'الحزن شعور طبيعي يمر بنا جميعاً. إن استمر أكثر من أسبوعين أو زاد، '
          'تحدث مع طبيبك أو من تثق به.',
    );
  }
  if (m.contains('متعب') || m.contains('مرهق') || m.contains('خامل')) {
    return const MoodWellbeing(
      exerciseTitle: 'تمرين تنشيط الدورة والتعامل مع التعب',
      exerciseSteps:
          'خطوات واضحة، كرر مرة واحدة:\n'
          'أنت جالس. ابدأ ببطء ولا تُجهد نفسك.\n'
          '1) تنفس: شهيق من الأنف 4 ثوان، ثم زفير من الفم 6 ثوان. كررها 4 مرات.\n'
          '2) حرّك كاحلي قدمك اليمنى دوائر 5 مرات، ثم اليسرى 5 مرات.\n'
          '3) افتح واقبض أصابع يديك 10 مرات.\n'
          '4) اجلس ثم قم ببطء مسنداً على الطاولة. كررها 5 مرات.\n'
          '5) اشرب كوب ماء وتمشّ في المنزل 3 دقائق.',
      musicTitle: 'موسيقى نشيطة هادئة (لرفع الطاقة)',
      musicReason:
          'اخترنا موسيقى نشيطة هادئة لأنها ترفع طاقتك بلطف وتخفف الإحساس '
              'بالخمول والتعب دون أن تتعبك.',
      musicQuery: 'gentle morning energy music calm',
      tip: 'التعب قد يكون بسبب قلة النوم أو الدواء أو الجفاف. خذ راحتك، '
          'وإن استمر التعب الشديد راجع طبيبك.',
    );
  }
  if (m.contains('هادئ') || m.contains('مرتاح') || m.contains('سعيد') || m.contains('جيد')) {
    return const MoodWellbeing(
      exerciseTitle: 'تمرين الحفاظ على نشاطك',
      exerciseSteps:
          'خطوات واضحة، كرر مرة واحدة:\n'
          '1) تمدّد: ارفع ذراعيك إلى الأعلى مع شهيق، ثم أنزلهما مع زفير. 5 مرات.\n'
          '2) مشي بطيء داخل المنزل أو في الخارج لمدة 10 دقائق.\n'
          '3) تمديد خفيف للساقين: اجلس ومدّ رجلك اليمنى ثم اليسرى 3 مرات.\n'
          '4) تنفس عميق 4-6، 5 مرات. اشرب ماء بعدها.',
      musicTitle: 'موسيقى استرخاء هادئة',
      musicReason:
          'اخترنا موسيقى استرخاء هادئة لأنك بحالة جيدة، وهي تساعدك على '
              'المحافظة على الهدوء والسكينة وتحصين مزاجك الرائع.',
      musicQuery: 'calming relaxation music gentle',
      tip: 'ممتاز! استمر على روتينك من حركة وماء ونوم منتظم، وسجّل مزاجك يومياً.',
    );
  }
  return const MoodWellbeing(
    exerciseTitle: 'تمرين التنفس العام (لأي حالة)',
    exerciseSteps:
        'خطوات واضحة، كرر مرة واحدة:\n'
        '1) اجلس مستقيماً بشكل مريح.\n'
        '2) شهيق من الأنف مع عد 4.\n'
        '3) احتفظ بالهواء مع عد 4.\n'
        '4) زفير من الفم مع عد 6.\n'
        'كررها 5 مرات ببطء.',
    musicTitle: 'موسيقى هادئة',
    musicReason: 'اخترنا موسيقى هادئة لأنها تناسب أي حالة وتريح أعصابك.',
    musicQuery: 'calming relaxation music gentle',
    tip: 'سجّل حالتك المزاجية يومياً لتتابع تحسّنك وتعرف ما يناسبك.',
  );
}
