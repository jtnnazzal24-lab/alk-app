import '../l10n/app_strings.dart';

/// Arabic-first UI strings for the Flutter build.
///
/// The RN app keyed translations by the Arabic source text; this port keeps
/// the same Arabic strings as the canonical labels, and the `.tr` extension
/// renders the stored on-device translation (e.g. French) whenever the phone
/// language is not Arabic.
class AlkStrings {
  AlkStrings._();

  static const home = 'الرئيسية';
  static const medications = 'الأدوية';
  static const vitals = 'القياسات';
  static const journal = 'يومياتي';
  static const more = 'المزيد';

  static const addMedication = 'إضافة دواء';
  static const medicationName = 'اسم الدواء';
  static const medicationNameHint = 'مثال: دواء الضغط';
  static const doseTime = 'وقت الجرعة';
  static const category = 'الفئة';
  static const dailyReminder = 'تذكير يومي محلي';
  static const saveMedication = 'حفظ الدواء';
  static const cancel = 'إلغاء';
  static const save = 'حفظ';
  static const delete = 'حذف';
  static const general = 'عام';
  static const heart = 'قلب';
  static const diabetes = 'سكري';

  static const noMedications = 'لا توجد أدوية مسجلة';
  static const noMedicationsHint = 'أضف جرعاتك اليومية واختر تذكيرًا محليًا إذا رغبت.';
  static const doseTaken = 'تم التناول ✓';
  static const confirmDose = 'تأكيد التناول';
  static const pendingConfirm = 'بانتظار التأكيد';

  static const bloodPressure = 'ضغط الدم';
  static const bloodSugar = 'سكر الدم';
  static const pulse = 'النبض';
  static const newReading = 'قراءة جديدة';
  static const saveReading = 'حفظ القراءة';
  static const history = 'السجل';
  static const noReadings = 'لا توجد قراءات بعد';

  static const journalTitle = 'يومياتي';
  static const mood = 'المزاج';
  static const note = 'الملاحظة';
  static const addEntry = 'إضافة تدوينة';
  static const noEntries = 'لا توجد تدوينات بعد';

  static const settings = 'الإعدادات';
  static const patientProfile = 'الملف الشخصي';
  static const fullName = 'الاسم الكامل';
  static const identityNumber = 'الرقم الهوية';
  static const conditionName = 'اسم الحالة';
  static const lockApp = 'قفل التطبيق (بصمة/وجه)';
  static const dataBackup = 'تصدير نسخة احتياطية (JSON)';
  static const dataRestore = 'استيراد نسخة احتياطية (JSON)';
  static const quietMode = 'الوضع الهادئ (تعطيل التذكيرات)';
  static const travelMode = 'وضع السفر';
  static const trustedContact = 'جهة اتصال موثوقة';
  static const dataRetention = 'مدة الاحتفاظ بالبيانات المتغيرة';
  static const forever = 'للأبد';
  static const fontScale = 'حجم الخط';
  static const defaultFont = 'افتراضي';
  static const largeFont = 'كبير';
  static const language = 'اللغة';
  static const deviceDefault = 'لغة الجهاز';
  static const doctorSummary = 'تصدير ملخص للطبيب';
  static const migratedFrom = 'تم استيراد بياناتك من النسخة السابقة بنجاح';
  static const snooze15 = 'تأجيل 15 دقيقة';
  static const markMissed = 'تسجيل جرعة فائتة';

  static const moodGreat = 'ممتاز';
  static const moodGood = 'جيد';
  static const moodOkay = 'لا بأس';
  static const moodLow = 'تعبان';

  static String moodFor(String mood, String code) {
    final key = _moodKey(mood) ?? mood;
    // النص العربي هو مفتاح القاموس — يُترجم عبر الترجمة المخزَّنة على الجهاز.
    final look = key.tr;
    if (look != key) return look;
    if (code == 'ar') return key;
    final zh = code.toLowerCase().startsWith('zh');
    switch (key) {
      case moodGreat:
        return zh ? '极好' : 'Great';
      case moodGood:
        return zh ? '良好' : 'Good';
      case moodOkay:
        return zh ? '一般' : 'Okay';
      case moodLow:
        return zh ? '疲倦' : 'Low';
    }
    return key;
  }

  /// يوحّد المزاج المخزَّن (عربي أو إنجليزي قديم) إلى المفتاح العربي.
  static String? _moodKey(String mood) {
    switch (mood) {
      case moodGreat:
      case 'Great':
      case '极好':
        return moodGreat;
      case moodGood:
      case 'Good':
      case '良好':
        return moodGood;
      case moodOkay:
      case 'Okay':
      case 'OK':
      case '一般':
        return moodOkay;
      case moodLow:
      case 'Low':
      case 'Bad':
      case '疲倦':
        return moodLow;
    }
    return null;
  }

  static String _pick(String code, String ar, String en, String zh) {
    if (code.toLowerCase().startsWith('ar')) return ar;
    if (code.toLowerCase().startsWith('zh')) return zh;
    return en;
  }

  static String vitalLabel(String kind, String code) {
    // النص العربي هو مفتاح القاموس — يُترجم عبر الترجمة المخزَّنة على الجهاز.
    switch (kind) {
      case 'pressure':
        final look = bloodPressure.tr;
        if (look != bloodPressure) return look;
        return _pick(code, bloodPressure, 'Blood pressure', '血压');
      case 'sugar':
        final look = bloodSugar.tr;
        if (look != bloodSugar) return look;
        return _pick(code, bloodSugar, 'Blood sugar', '血糖');
      default:
        final look = pulse.tr;
        if (look != pulse) return look;
        return _pick(code, pulse, 'Pulse', '脉搏');
    }
  }

  static String categoryLabel(String category, String code) {
    // القيم المخزَّنة عربية — تُترجم للعرض عبر الترجمة المخزَّنة على الجهاز.
    final look = category.tr;
    if (look != category) return look;
    switch (category) {
      case 'قلب':
        return _pick(code, heart, 'Heart', '心脏');
      case 'سكري':
        return _pick(code, diabetes, 'Diabetes', '糖尿病');
      default:
        return _pick(code, general, 'General', '常规');
    }
  }

  static String reminderStatusLabel(String status, String code) {
    // حالات التذكير الإنجليزية المخزَّنة لها مفاتيح عربية في القاموس.
    const arByStatus = {
      'active': 'تذكير يومي مفعّل',
      'quiet': 'مؤجل في الوضع الهادئ',
      'denied': 'التذكير غير مسموح',
      'unsupported': 'يتاح في تطبيق الهاتف',
    };
    final ar = arByStatus[status];
    if (ar != null) {
      final look = ar.tr;
      if (look != ar) return look;
    }
    switch (status) {
      case 'active':
        return _pick(code, 'تذكير يومي مفعّل', 'Daily reminder on', '每日提醒已开启');
      case 'quiet':
        return _pick(
            code, 'مؤجل في الوضع الهادئ', 'Paused (quiet mode)', '已暂停（静音模式）');
      case 'denied':
        return _pick(code, 'التذكير غير مسموح', 'Reminder not allowed', '未允许提醒');
      case 'unsupported':
        return _pick(code, 'يتاح في تطبيق الهاتف', 'Available on the mobile app',
            '仅在手机应用中可用');
      default:
        return _pick(code, 'بلا تذكير', 'No reminder', '无提醒');
    }
  }
}
