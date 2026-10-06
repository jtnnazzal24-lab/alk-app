# -*- coding: utf-8 -*-
"""
tool_extract_dictionary.py — يستخرج كل مفردات اللغة العربية من مشروع ALK (Flutter)
ويبني ملف قاموس واحد source_dictionary.json (في جذر المشروع + نسخة في assets/).

القواعد الصارمة:
- قراءة فقط: لا يعدّل أي ملف في المشروع.
- النصوص تُنسخ حرفياً كما وردت في الشيفرة (لا ترجمة، لا تصحيح إملاء، لا حذف).
- المفاتيح بالإنجليزية: النصوص المعروفة تستخدم مفتاحاً منسّقاً منسوخاً من
  اسم الثابت/المعرف الأصلي، والبقية مفتاح تلقائي بصيغة PREFIX_<hash> مع ذكر المصدر.
- الدمج: النص المطابق تماماً في أكثر من مكان => مفتاح واحد + كل المصادر.

التشغيل:  python tool_extract_dictionary.py
"""
import hashlib
import json
import re
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LIB = ROOT / "lib"
OUT_ROOT = ROOT / "source_dictionary.json"
OUT_ASSETS = ROOT / "assets" / "source_dictionary.json"

ARABIC_LETTER = re.compile(r"[\u0621-\u064A]")  # حرف عربي (ليس علامة ترقيم فقط)
VERSION = "1.0.0"
APP_NAME = "ALK"

# ---------------------------------------------------------------------------
# 1) مُحلِّل لغوي (Lexer) لقراءة سلاسل Dart بدقة:
#    - يتجاهل تعليقات // و /* */ حتى لو احتوت علامات اقتباس شاردة.
#    - يتعامل مع السلاسل الخام r'...' و \\ الهاربة و ${...} المتداخلة.
# ---------------------------------------------------------------------------

def lex_dart(source):
    """يعيد (literals, interps):
    literals: [(القيمة، بداية، نهاية)] للسلاسل ذات المستوى الأعلى.
    interps: [(بداية_محتوى، نهاية_محتوى، بداية_السلسلة_الخارجية)] لمقاطع ${...}.
    """
    literals, interps = [], []
    n = len(source)
    i = 0
    while i < n:
        c = source[i]
        if c == "/" and i + 1 < n and source[i + 1] == "/":
            j = source.find("\n", i)
            i = n if j == -1 else j
            continue
        if c == "/" and i + 1 < n and source[i + 1] == "*":
            j = source.find("*/", i + 2)
            i = n if j == -1 else j + 2
            continue
        if c in "'\"":
            raw = (i > 0 and source[i - 1] == "r"
                   and (i < 2 or not (source[i - 2].isalnum() or source[i - 2] == "_")))
            q = c
            start = i
            j = i + 1
            buf = []
            depth = 0
            interp_start = None
            closed = False
            while j < n:
                cj = source[j]
                if depth > 0:
                    if cj in "'\"":
                        k = j + 1  # سلسلة متداخلة داخل الاستيفاء
                        while k < n:
                            if source[k] == "\\":
                                k += 2
                                continue
                            if source[k] == cj:
                                break
                            k += 1
                        buf.append(source[j:min(k + 1, n)])
                        j = k + 1
                        continue
                    if cj == "{":
                        depth += 1
                    elif cj == "}":
                        depth -= 1
                        if depth == 0:
                            interps.append((interp_start, j, start))
                            interp_start = None
                    buf.append(cj)
                    j += 1
                    continue
                if cj == "\\" and not raw:
                    buf.append(source[j:j + 2])
                    j += 2
                    continue
                if raw and cj == "\\":
                    buf.append(cj)
                    j += 1
                    continue
                if cj == "$" and j + 1 < n and source[j + 1] == "{" and not raw:
                    depth = 1
                    interp_start = j + 2
                    buf.append("${")
                    j += 2
                    continue
                if cj == q:
                    j += 1
                    closed = True
                    break
                buf.append(cj)
                j += 1
            if closed:
                literals.append(("".join(buf), start, j))
                i = j
                continue
            i += 1
            continue
        i += 1
    return literals, interps


def extract_all(source):
    """[(النص، فهرس البداية)] مع دمج السلاسل المتلاصقة ودخول ${...} المتداخل."""
    lits, interps = lex_dart(source)
    lits.sort(key=lambda x: x[1])
    merged = []
    for v, s, e in lits:
        if merged:
            pv, ps, pe = merged[-1]
            if source[pe:s].strip() == "":
                merged[-1] = (pv + v, ps, e)
                continue
        merged.append((v, s, e))
    out = [(v, s) for v, s, _e in merged]
    for cs, ce, outer_start in interps:
        for v, _s2 in extract_all(source[cs:ce]):
            out.append((v, outer_start))
    return out


def rel_of(path):
    return path.relative_to(ROOT).as_posix().replace("\\", "/")


def md6(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()[:6].upper()


# ---------------------------------------------------------------------------
# 2) المفاتيح المنسّقة: نص => (key, category, screen, note)
#    مأخوذة حرفياً من قراءة الملفات. ما ليس هنا يُولَّد مفتاحه تلقائياً.
# ---------------------------------------------------------------------------

C = {}  # text -> (key, category, screen, note)


def cur(text, key, cat="ui", screen=None, note=None):
    C[text] = (key, cat, screen, note)


# --- lib/state/alk_strings.dart (بأسماء ثوابتها الأصلية) ---
cur("الرئيسية", "TAB_HOME", "ui", "home", "تبويب الرئيسية")
cur("الأدوية", "TAB_MEDICATIONS", "ui", "medications", "تبويب الأدوية")
cur("القياسات", "TAB_VITALS", "ui", "vitals", "تبويب القياسات")
cur("يومياتي", "JOURNALS_TITLE", "ui", "journals", "عنوان اليوميات (تبويب + شاشة)")
cur("المزيد", "TAB_MORE", "ui", "more", "تبويب المزيد")
cur("إضافة دواء", "MEDICATIONS_ADD", "ui", "medications")
cur("اسم الدواء", "MEDICATIONS_NAME_FIELD", "ui", "medications")
cur("مثال: دواء الضغط", "MEDICATIONS_NAME_HINT", "ui", "medications")
cur("وقت الجرعة", "MEDICATIONS_DOSE_TIME", "ui", "medications")
cur("الفئة", "MEDICATIONS_CATEGORY", "ui", "medications")
cur("تذكير يومي محلي", "MEDICATIONS_DAILY_REMINDER", "ui", "medications")
cur("حفظ الدواء", "MEDICATIONS_SAVE", "ui", "medications")
cur("إلغاء", "ACTION_CANCEL", "ui", "actions", "زر إلغاء عام")
cur("حفظ", "ACTION_SAVE", "ui", "actions", "زر حفظ عام")
cur("حذف", "ACTION_DELETE", "ui", "actions", "زر حذف عام")
cur("عام", "MED_CAT_GENERAL", "medical", None, "فئة دواء: عام")
cur("قلب", "MED_CAT_HEART", "medical", None, "فئة دواء: قلب")
cur("سكري", "MED_CAT_DIABETES", "medical", None, "فئة دواء: سكري")
cur("لا توجد أدوية مسجلة", "MEDICATIONS_EMPTY_TITLE", "ui", "medications")
cur("أضف جرعاتك اليومية واختر تذكيرًا محليًا إذا رغبت.", "MEDICATIONS_EMPTY_HINT", "ui", "medications")
cur("تم التناول ✓", "MEDICATIONS_DOSE_TAKEN", "ui", "medications")
cur("تأكيد التناول", "MEDICATIONS_CONFIRM_DOSE", "ui", "medications")
cur("بانتظار التأكيد", "MEDICATIONS_PENDING_CONFIRM", "ui", "medications")
cur("ضغط الدم", "MED_BP_LABEL", "medical", None, "مصطلح: ضغط الدم (تسمية قياس وتقرير)")
cur("سكر الدم", "MED_BS_LABEL", "medical", None, "مصطلح: سكر الدم")
cur("النبض", "MED_PULSE_LABEL", "medical", None, "مصطلح: النبض")
cur("قراءة جديدة", "VITALS_NEW_READING", "ui", "vitals")
cur("حفظ القراءة", "VITALS_SAVE_READING", "ui", "vitals")
cur("السجل", "VITALS_HISTORY", "ui", "vitals")
cur("لا توجد قراءات بعد", "VITALS_EMPTY", "ui", "vitals")
cur("المزاج", "JOURNALS_MOOD", "ui", "journals")
cur("الملاحظة", "JOURNALS_NOTE", "ui", "journals")
cur("إضافة تدوينة", "JOURNALS_ADD_ENTRY", "ui", "journals")
cur("لا توجد تدوينات بعد", "JOURNALS_EMPTY", "ui", "journals")
cur("الإعدادات", "SETTINGS_TITLE", "ui", "settings")
cur("الملف الشخصي", "PROFILE_TITLE", "ui", "profile")
cur("الاسم الكامل", "PROFILE_FULL_NAME", "ui", "profile")
cur("الرقم الهوية", "PROFILE_ID_NUMBER", "ui", "profile")
cur("اسم الحالة", "PROFILE_CONDITION", "ui", "profile")
cur("قفل التطبيق (بصمة/وجه)", "SETTINGS_LOCK_APP", "ui", "settings")
cur("تصدير نسخة احتياطية (JSON)", "SETTINGS_BACKUP_EXPORT", "ui", "settings")
cur("استيراد نسخة احتياطية (JSON)", "SETTINGS_BACKUP_IMPORT", "ui", "settings")
cur("الوضع الهادئ (تعطيل التذكيرات)", "SETTINGS_QUIET_MODE", "ui", "settings")
cur("وضع السفر", "SETTINGS_TRAVEL_MODE", "ui", "settings")
cur("جهة اتصال موثوقة", "SETTINGS_TRUSTED_CONTACT", "ui", "settings")
cur("مدة الاحتفاظ بالبيانات المتغيرة", "SETTINGS_DATA_RETENTION", "ui", "settings")
cur("للأبد", "SETTINGS_RETENTION_FOREVER", "ui", "settings")
cur("حجم الخط", "SETTINGS_FONT_SCALE", "ui", "settings")
cur("افتراضي", "SETTINGS_FONT_DEFAULT", "ui", "settings")
cur("كبير", "SETTINGS_FONT_LARGE", "ui", "settings")
cur("اللغة", "SETTINGS_LANGUAGE", "ui", "settings")
cur("لغة الجهاز", "SETTINGS_DEVICE_DEFAULT", "ui", "settings")
cur("تصدير ملخص للطبيب", "SETTINGS_DOCTOR_SUMMARY", "ui", "settings")
cur("تم استيراد بياناتك من النسخة السابقة بنجاح", "SETTINGS_MIGRATED", "ui", "settings")
cur("تأجيل 15 دقيقة", "NOTIFICATION_SNOOZE_15", "notifications", None, "تأجيل التذكير 15 دقيقة")
cur("تسجيل جرعة فائتة", "MEDICATIONS_MARK_MISSED", "ui", "medications")
cur("ممتاز", "JOURNALS_MOOD_GREAT", "ui", "journals")
cur("جيد", "JOURNALS_MOOD_GOOD", "ui", "journals", "قيمة مزاج + كلمة مفتاحية لاكتشاف المزاج")
cur("لا بأس", "JOURNALS_MOOD_OKAY", "ui", "journals")
cur("تعبان", "JOURNALS_MOOD_LOW", "ui", "journals")
cur("تذكير يومي مفعّل", "MEDICATIONS_REMINDER_ACTIVE", "ui", "medications", "حالة التذكير")
cur("مؤجل في الوضع الهادئ", "MEDICATIONS_REMINDER_QUIET", "ui", "medications", "حالة التذكير")
cur("التذكير غير مسموح", "MEDICATIONS_REMINDER_DENIED", "ui", "medications", "حالة التذكير")
cur("يتاح في تطبيق الهاتف", "MEDICATIONS_REMINDER_UNSUPPORTED", "ui", "medications", "حالة التذكير")
cur("بلا تذكير", "MEDICATIONS_REMINDER_NONE", "ui", "medications", "حالة التذكير")

# --- home_screen ---
cur("أدويتي", "MEDS_TAB_TITLE", "ui", "medications", "تبويب الأدوية (صيغة الملكية)")
cur("صباح الخير", "HOME_GREETING_MORNING", "ui", "home")
cur("مساء الخير", "HOME_GREETING_EVENING", "ui", "home")
cur("مساء النور", "HOME_GREETING_NIGHT", "ui", "home")
cur("المستخدم", "HOME_DEFAULT_USER", "ui", "home", "اسم افتراضي عند غياب اسم المريض")
cur("مرحبا. أنا رفيقك الصحي. لديك $takenCount من ${todayMeds.length} جرعات اليوم. اضغط زر المايك الكبير وتحدث معي ببطء.", "HOME_TTS_GREETING", "ui", "home", "نص ترحيبي ديناميكي (قد يُنطق عبر TTS)")
cur("شعار ALK", "HOME_LOGO_SEMANTIC", "ui", "home", "تسمية دلالية للشعار")
cur("رفيقك الصحي اليوم", "HOME_TAGLINE", "ui", "home")
cur("الالتزام بالأدوية", "HOME_ADHERENCE", "ui", "home")
cur("$takenCount من ${todayMeds.length} جرعات", "HOME_DOSES_SUMMARY", "ui", "home", "نص ديناميكي")
cur("أدوية اليوم", "HOME_TODAY_MEDS", "ui", "home")

# --- emergency_screen ---
cur("اكتب الاسم ورقم الهاتف", "ERR_EMERG_FIELDS", "errors", None, "تحقق: حقول ناقصة")
cur("تمت إضافة $name إلى قائمة الطوارئ", "EMERG_CONTACT_ADDED", "ui", "emergency", "نص ديناميكي")
cur("تم تحديث رقم الإسعاف إلى $number", "EMERG_AMBULANCE_UPDATED", "ui", "emergency", "نص ديناميكي")
cur("الطوارئ", "EMERG_TITLE", "ui", "emergency")
cur("عند شعورك أنك ستفقد السيطرة، قل للمساعد الصوتي: ", "EMERG_VOICE_HINT", "ui", "emergency", "يرافق أمراً صوتياً")
cur("رقم الإسعاف", "EMERG_AMBULANCE", "ui", "emergency")
cur("رقم الإسعاف في بلدك", "EMERG_AMBULANCE_HINT", "ui", "emergency")
cur("إضافة شخص للطوارئ", "EMERG_ADD_PERSON", "ui", "emergency")
cur("الاسم (مثال: ابني أحمد)", "EMERG_NAME_HINT", "ui", "emergency")
cur("رقم الهاتف", "EMERG_PHONE_FIELD", "ui", "emergency")
cur("إضافة", "ACTION_ADD", "ui", "actions", "زر إضافة")
cur("أشخاص الطوارئ (${store.emergencyContacts.length})", "EMERG_PEOPLE_COUNT", "ui", "emergency", "نص ديناميكي")
cur("لا يوجد أشخاص بعد — أضف أحدهم فوق", "EMERG_EMPTY", "ui", "emergency")

# --- journals_screen + كلمات اكتشاف المزاج (mood_wellbeing) ---
cur("مرتاح", "JOURNALS_MOOD_RELAXED", "ui", "journals", "قيمة مزاج + كلمة اكتشاف")
cur("هادئ", "JOURNALS_MOOD_CALM", "ui", "journals", "قيمة مزاج + كلمة اكتشاف")
cur("متعب", "JOURNALS_MOOD_TIRED", "ui", "journals", "قيمة مزاج + كلمة اكتشاف")
cur("حزين", "JOURNALS_MOOD_SAD", "ui", "journals", "قيمة مزاج + كلمة اكتشاف")
cur("مكتئب", "JOURNALS_MOOD_DEPRESSED", "ui", "journals", "كلمة اكتشاف المزاج")
cur("قلق", "JOURNALS_MOOD_ANXIOUS", "ui", "journals", "كلمة اكتشاف المزاج")
cur("متوتر", "JOURNALS_MOOD_TENSE", "ui", "journals", "كلمة اكتشاف المزاج")
cur("مرهق", "JOURNALS_MOOD_EXHAUSTED", "ui", "journals", "كلمة اكتشاف المزاج")
cur("خامل", "JOURNALS_MOOD_LETHARGIC", "ui", "journals", "كلمة اكتشاف المزاج")
cur("سعيد", "JOURNALS_MOOD_HAPPY", "ui", "journals", "كلمة اكتشاف المزاج")
cur("حالتك: $mood — هذا ما يناسبك", "JOURNALS_STATUS", "ui", "journals", "نص ديناميكي")
cur("حالتك $mood. أنصحك بـ ${rec.exerciseTitle}. ${rec.exerciseSteps}. ${rec.tip}", "JOURNALS_ADVICE_LINE", "ui", "journals", "نص ديناميكي")
cur("شغّل الموسيقى (يوتيوب)", "JOURNALS_MUSIC_BUTTON", "ui", "journals")
cur("افتح العافية والحركة", "JOURNALS_OPEN_WELLBEING", "ui", "journals")
cur("الحالة النفسية: $mood", "JOURNALS_AI_TOPIC", "ui", "journals", "موضوع استعلام الذكاء الآلي")
cur("كيف كان يومك؟", "JOURNALS_ASK_DAY", "ui", "journals")
cur("اكتب ملاحظة بسيطة عن يومك...", "JOURNALS_NOTE_HINT", "ui", "journals")
cur("حفظ في يومياتي", "JOURNALS_SAVE_ENTRY", "ui", "journals")
cur("ابدأ أول ملاحظة", "JOURNALS_EMPTY", "ui", "journals")

# --- lock_screen + lock_gate ---
cur("قم بالمصادثة لفتح ALK", "LOCK_BIOMETRIC_REASON", "ui", "lock", "نص مصادقة النظام (نُسخ حرفياً كما ورد)")
cur("تعذر التحقق. حاول مرة أخرى.", "ERR_LOCK_VERIFY", "errors", None, "فشل التحقق")
cur("خطأ في المصادقة: ${e.toString()}", "ERR_LOCK_AUTH", "errors", None, "نص ديناميكي")
cur("ALK مقفل", "LOCK_TITLE", "ui", "lock")
cur("استخدم بصمة إصبعك أو رمز الجهاز للفتح", "LOCK_HINT", "ui", "lock")
cur("جاري التحقق...", "LOCK_CHECKING", "ui", "lock")
cur("فتح", "ACTION_UNLOCK", "ui", "actions", "زر فتح")
cur("افتح ALK للوصول إلى بياناتك الصحية", "LOCK_GATE_REASON", "ui", "lock", "سبب المصادقة البيومترية")
cur("قم بالمصادقة لعرض بياناتك الصحية.", "LOCK_PROMPT", "ui", "lock")

# --- medications_screen ---
cur("اكتب اسم الدواء قبل الحفظ", "ERR_MEDS_NAME", "errors", None, "تحقق: اسم الدواء مطلوب")
cur("هذه صفحة أدويتك. سأقرأ لك أسماء الأدوية ومواعيدها ببطء. اضغط زر السماعة بجانب أي دواء لسماعه.", "VOICE_MEDS_INTRO", "voice", None, "نص يُنطق عبر زر الاستماع")
cur("لا توجد أدوية بعد", "MEDS_EMPTY_TITLE", "ui", "medications")
cur("أضف دواءً لمتابعة جرعاتك", "MEDS_EMPTY_HINT", "ui", "medications")
cur("إلغاء تأكيد التناول", "MEDS_UNCONFIRM_DOSE", "ui", "medications")
cur("تأكيد تناول الجرعة", "MEDS_CONFIRM_DOSE_INTAKE", "ui", "medications")
cur("دواء ${med.name}. الموعد ${med.time}. ${_medicationDetails(med)}", "VOICE_MED_READOUT", "voice", None, "سطر يُنطق عبر زر الاستماع (ديناميكي)")
cur("كل يوم", "MEDS_EVERY_DAY", "ui", "medications", "خيار تكرار الجرعة")
cur("كل يومين", "MEDS_EVERY_2_DAYS", "ui", "medications", "خيار تكرار الجرعة")
cur("كل ٣ أيام", "MEDS_EVERY_3_DAYS", "ui", "medications", "خيار تكرار الجرعة")
cur("كل أسبوع", "MEDS_EVERY_WEEK", "ui", "medications", "خيار تكرار الجرعة")
cur("كل $n أيام", "MEDS_EVERY_N_DAYS", "ui", "medications", "نص ديناميكي للتكرار")
cur("عيار الجرعة (مثال: 500 ملغ، قرص واحد)", "MEDS_DOSE_FIELD", "ui", "medications")
cur("شكل الدواء", "MEDS_FORM_LABEL", "ui", "medications")
cur("موعد أخذ الدواء", "MEDS_TIME_LABEL", "ui", "medications")
cur("التكرار", "MEDS_REPEAT", "ui", "medications")
cur("الدواء لأي مرض؟", "MEDS_CATEGORY_PROMPT", "ui", "medications")
cur("تفعيل التذكير", "MEDS_REMINDER_TOGGLE", "ui", "medications")

# --- more_screen ---
cur("ALK بجانبك", "MORE_TAGLINE", "ui", "more")
cur("رفيق للتنظيم والمتابعة اليومية", "MORE_TAGLINE_SUB", "ui", "more")
cur("ملف المريض", "PROFILE_TILE", "ui", "profile", "عنوان شاشة + بلاطة في المزيد")
cur("الهوية الصحية والأدوية", "MORE_PROFILE_SUB", "ui", "more")
cur("محادثة ALK", "CHAT_TILE", "ui", "chat", "عنوان شاشة + بلاطة في المزيد")
cur("دعم عام ونصائح", "MORE_CHAT_SUB", "ui", "more")
cur("التغذية", "NUTRI_TITLE", "ui", "nutrition", "عنوان شاشة + تبويب المساعد الصوتي + بلاطة")
cur("تتبع الوجبات وتأثيرها على السكر والضغط والقلب", "MORE_NUTRI_SUB", "ui", "more")
cur("العافية والحركة", "WELLBEING_TITLE", "ui", "wellbeing", "عنوان شاشة + بلاطة")
cur("تمارين وموسيقى هادئة", "MORE_WELLBEING_SUB", "ui", "more")
cur("التقارير", "REPORTS_TITLE", "ui", "reports", "عنوان شاشة + تبويب المساعد الصوتي + بلاطة")
cur("ملخص الالتزام والقياسات", "MORE_REPORTS_SUB", "ui", "more")
cur("الخصوصية والتذكيرات", "MORE_SETTINGS_SUB", "ui", "more")
cur("ALK لا يقدم تشخيصًا طبيًا. تواصل مع طبيبك عند وجود عرض مقلق.", "MED_DISCLAIMER", "medical", None, "إخلاء مسؤولية طبي (مزيد + إعدادات)")

# --- nutrition_screen ---
cur("اكتب اسم الطعام قبل الحفظ", "ERR_NUTRI_FOOD", "errors", None, "تحقق: اسم الطعام مطلوب")
cur("تم تسجيل ${_mealType == FoodMealType.snack ? 'الوجبة' : _mealType} وتحليله", "NUTRI_LOGGED_ANALYZED", "ui", "nutrition", "نص ديناميكي")
cur("الوجبة", "MED_MEAL_WORD", "medical", None, "كلمة وجبة (نص متداخل داخل قالب)")
cur("تم تسجيل الطعام", "NUTRI_LOGGED", "ui", "nutrition")
cur("توازن الدهون اليومي", "NUTRI_FAT_BALANCE", "ui", "nutrition", "عنوان بطاقة (تغذية + عافية)")
cur("توازن الدهون. ${adviceSummaryText(advice)}. ${advice.conditionAdvice}.", "NUTRI_FAT_SUMMARY", "ui", "nutrition", "نص ديناميكي")
cur("حسناً", "ACTION_OK", "ui", "actions", "زر موافقة")
cur("هذه صفحة التغذية. سأخبرك ببطء كيف تؤثر وجبات الفطور والغداء والعشاء على دواء الصباح، مع الكمية المناسبة والبديل.", "VOICE_NUTRI_INTRO", "voice", None, "نص يُنطق عبر زر الاستماع")
cur("وجبات اليوم", "NUTRI_TODAY_MEALS", "ui", "nutrition")
cur("لا توجد وجبات مسجّلة بعد", "NUTRI_NO_MEALS", "ui", "nutrition")
cur("ما الذي تناولته اليوم؟", "NUTRI_ASK_FOOD", "ui", "nutrition")
cur("اسم الطعام أو الشراب", "NUTRI_FOOD_FIELD", "ui", "nutrition")
cur("مثال: أرز أبيض، مخلل، عصير غازي...", "NUTRI_FOOD_HINT", "ui", "nutrition")
cur("لا يُعرف لهذه الأكلة تأثير واضح على السكر أو الضغط أو القلب.", "MED_NO_IMPACT", "medical", None, "حالة تحليل غذائي غير معروف")
cur("إضافة الوجبة", "ACTION_ADD_MEAL", "ui", "actions")
cur("أمثلة سريعة:", "NUTRI_QUICK_EXAMPLES", "ui", "nutrition")
cur("خبز أبيض", "MED_FOOD_WHITE_BREAD", "medical", None, "مصطلح غذائي (رقاقة اختيار + قواعد الأطعمة)")
cur("عصير غازي", "MED_FOOD_SODA_JUICE", "medical", None, "مصطلح غذائي")
cur("مخلل", "MED_FOOD_PICKLES", "medical", None, "مصطلح غذائي")
cur("دجاج مقلي", "MED_FOOD_FRIED_CHICKEN", "medical", None, "مصطلح غذائي")
cur("برجر", "MED_FOOD_BURGER", "medical", None, "مصطلح غذائي")
cur("هذا الطعام يؤثر على:", "NUTRI_IMPACTS_ON", "ui", "nutrition")
cur("لا يوجد دواء صباحي مسجل — اضف دواء بموعد قبل 12 ظهرا", "NUTRI_NO_MORNING_MEDS", "ui", "nutrition")
cur("دواء الصباح: ${morning.map((m) => m.name).join('، ')}", "NUTRI_MORNING_MEDS", "ui", "nutrition", "نص ديناميكي")
cur("تفاعل الغذاء مع دواء الصباح", "NUTRI_FOOD_MED_TITLE", "ui", "nutrition")
cur("تحليل الوجبات مع دواء الصباح", "NUTRI_ANALYSIS_TITLE", "ui", "nutrition")
cur("وجبة ${a.mealType}", "NUTRI_MEAL_N", "ui", "nutrition", "نص ديناميكي")
cur("الكمية: ${it.amountAdvice}", "NUTRI_AMOUNT", "ui", "nutrition", "نص ديناميكي")
cur("البديل: ${it.alternative}", "NUTRI_ALTERNATIVE", "ui", "nutrition", "نص ديناميكي")
cur("التوقيت: ${it.timingAdvice}", "NUTRI_TIMING", "ui", "nutrition", "نص ديناميكي")
cur("لم تسجل اصناف في وجبة ${a.mealType} بعد.", "NUTRI_NO_ITEMS", "ui", "nutrition", "نص ديناميكي")
cur("آخر قراءة سكر: ${latest.value}", "NUTRI_LAST_SUGAR", "ui", "nutrition", "نص ديناميكي")
cur("${latest.createdAt} — قارنها قبل وبعد الوجبات", "NUTRI_COMPARE_READING", "ui", "nutrition", "نص ديناميكي")
cur("الدهون المشبعة: ${FatAdviceLevel.label(advice.level)}", "NUTRI_SATFAT_LABEL", "ui", "nutrition", "نص ديناميكي")
cur("تمارين تعويضية مقترحة:", "MED_EXERCISE_SUGGESTIONS", "medical", None, "عنوان اقتراح تمارين (تغذية + عافية)")

# --- patient_screen ---
cur("تم حفظ الملف الشخصي", "PROFILE_SAVED", "ui", "profile")
cur("رقم الهوية", "PROFILE_ID_FIELD", "ui", "profile")
cur("اسم الحالة المرضية", "PROFILE_CONDITION_FIELD", "ui", "profile")
cur("ملاحظات الطبيب", "PROFILE_DOCTOR_NOTES", "ui", "profile")
cur("موعد المراجعة القادم", "PROFILE_NEXT_REVIEW", "ui", "profile")
cur("الطبيب المعالج (لإرسال التقارير)", "PROFILE_DOCTOR_SECTION", "ui", "profile")
cur("رقم واتساب الطبيب (بصيغة دولية)", "PROFILE_DOCTOR_WHATSAPP", "ui", "profile", "ملف المريض + التقارير")
cur("مثال: 972591234567", "PROFILE_PHONE_EXAMPLE", "ui", "profile")
cur("البريد الإلكتروني للطبيب", "PROFILE_DOCTOR_EMAIL", "ui", "profile", "ملف المريض + التقارير")
cur("قفل التطبيق", "SET_LOCK_TILE", "ui", "settings", "بلاطة القفل (إعدادات + ملف المريض)")

# --- reports_screen ---
cur("التزام الأدوية اليوم", "REPORTS_ADHERENCE", "ui", "reports")
cur("$taken من ${medications.length} جرعات مؤكدة", "REPORTS_DOSES_SUMMARY", "ui", "reports", "نص ديناميكي")
cur("آخر القياسات", "REPORTS_VITALS_SECTION", "ui", "reports")
cur("لا توجد قراءات مسجلة", "REPORTS_NO_READINGS", "ui", "reports")
cur("المذكرات المحفوظة", "REPORTS_MEMOS", "ui", "reports")
cur("هذا التقرير ملخص تنظيمي لبيانات أدخلتها بنفسك، ولا يفسر القياسات أو يقدم تشخيصًا.", "REPORTS_DISCLAIMER", "ui", "reports")
cur("بيانات الطبيب المعالج", "REPORTS_DOCTOR_DATA", "ui", "reports")
cur("إرسال التقرير إلى الطبيب المعالج", "REPORTS_SEND_TITLE", "ui", "reports")
cur("سيُرسل ملخص الالتزام بالأدوية وآخر القياسات والجرعات الفائتة.", "REPORTS_SEND_SUMMARY", "ui", "reports")
cur("واتساب", "REPORTS_CHANNEL_WHATSAPP", "ui", "reports")
cur("بريد إلكتروني", "REPORTS_CHANNEL_EMAIL", "ui", "reports")
cur("مشاركة عبر تطبيق آخر", "REPORTS_CHANNEL_SHARE", "ui", "reports")
cur("تعديل بيانات الطبيب", "REPORTS_EDIT_DOCTOR", "ui", "reports")
cur("تم فتح واتساب لإرسال التقرير للطبيب", "REPORTS_WHATSAPP_OPENED", "ui", "reports")
cur("تعذر فتح واتساب — تأكد من تثبيته ومن رقم الطبيب", "ERR_REPORTS_WHATSAPP", "errors", None)
cur("تم فتح تطبيق البريد لإرسال التقرير للطبيب", "REPORTS_EMAIL_OPENED", "ui", "reports")
cur("تعذر فتح تطبيق البريد — تأكد من بريد الطبيب", "ERR_REPORTS_EMAIL", "errors", None)
cur("أدخل بيانات الطبيب المعالج أولاً", "ERR_REPORTS_DOCTOR_DATA", "errors", None)

# --- vitals_screen ---
cur("قياس جديد من الجهاز (${_getLabelFor(reading.kind)}): ${reading.value}", "VITALS_DEVICE_READING", "ui", "vitals", "نص ديناميكي")
cur("لم يُمنح الإذن للوصول إلى Health Connect", "ERR_VITALS_HC_PERM", "errors", None)
cur("لا توجد قراءات جديدة", "VITALS_NO_NEW_READINGS", "ui", "vitals")
cur("تمت إضافة $added قراءة من جهازك", "VITALS_ADDED_READINGS", "ui", "vitals", "نص ديناميكي")
cur("الأكسجين", "MED_OXYGEN_LABEL", "medical", None, "مصطلح: الأكسجين (SpO2)")
cur("هذه صفحة القياسات. سجل ضغطك أو سكرك أو نبضك هنا. سأقرأ لك النتيجة ببطء ووضوح.", "VOICE_VITALS_INTRO", "voice", None, "نص يُنطق عبر زر الاستماع")
cur("ضغط", "MED_PRESSURE_SHORT", "medical", None, "مصطلح قياس + زناد أمر صوتي + فئة دواء")
cur("سكر", "MED_SUGAR_SHORT", "medical", None, "مصطلح قياس + كلمة اكتشاف")
cur("نبض", "MED_PULSE_SHORT", "medical", None, "مصطلح قياس")
cur("أكسجين", "MED_OXYGEN_SHORT", "medical", None, "مصطلح قياس SpO2")
cur("القيمة", "VITALS_VALUE_FIELD", "ui", "vitals")
cur("مزامنة من جهازي", "VITALS_SYNC_DEVICE", "ui", "vitals")
cur("${VitalSource.label(v.source)} — تحتاج تدقيقاً", "VITALS_NEEDS_REVIEW", "ui", "vitals", "نص ديناميكي")
cur("القيمة: ${v.value}", "VITALS_VALUE_LINE", "ui", "vitals", "نص ديناميكي")
cur("المصدر: ${VitalSource.label(v.source)}", "VITALS_SOURCE_LINE", "ui", "vitals", "نص ديناميكي")
cur("الجهاز: ${v.deviceName}", "VITALS_DEVICE_LINE", "ui", "vitals", "نص ديناميكي")
cur("تم", "ACTION_DONE", "ui", "actions", "زر إنهاء")
cur("لم تُمنح صلاحيات البلوتوث — لا يمكن البحث عن الأجهزة", "ERR_VITALS_BT_PERM", "errors", None)
cur("لم يُعثر على أجهزة قياس قريبة. شغّل جهاز القياس وضع قربه من الهاتف ثم أعد المحاولة", "ERR_VITALS_NO_DEVICES", "errors", None)
cur("الأجهزة التي تم العثور عليها", "VITALS_FOUND_DEVICES", "ui", "vitals")
cur("جهاز قياس (${device.kinds.join('، ')})", "VITALS_DEVICE_KINDS", "ui", "vitals", "نص ديناميكي")
cur("يقيس: ${device.kinds.map(_kindLabel).join('، ')}", "VITALS_MEASURES_LINE", "ui", "vitals", "نص ديناميكي")
cur("تم ربط الجهاز — سيتم استقبال قياساته تلقائياً", "VITALS_PAIRED", "ui", "vitals")
cur("تعذر الاتصال بالجهاز — تأكد أنه قريب ويعمل", "ERR_VITALS_CONNECT", "errors", None)
cur("الضغط", "MED_PRESSURE_THE", "medical", None, "تسمية منطوقة لقياس الضغط")
cur("السكر", "MED_SUGAR_THE", "medical", None, "تسمية منطوقة لقياس السكر")
cur("جهاز مقترن", "VITALS_PAIRED_DEVICE", "ui", "vitals")
cur("متصل — يستقبل القياسات الآن", "VITALS_ONLINE", "ui", "vitals")
cur("غير متصل حالياً", "VITALS_OFFLINE", "ui", "vitals")
cur("فصل الجهاز", "VITALS_UNPAIR", "ui", "vitals")
cur("جارٍ البحث عن الأجهزة…", "VITALS_SCANNING", "ui", "vitals")
cur("ربط جهاز قياس جديد", "VITALS_PAIR_NEW", "ui", "vitals")
cur("أجهزة القياس المتصلة", "VITALS_CONNECTED_DEVICES", "ui", "vitals")
cur("اربط جهاز الضغط أو السكر أو الأكسجين وسيسجل التطبيق قياساته تلقائياً دون تدخل منك.", "VITALS_PAIR_HINT", "ui", "vitals")

# --- wellbeing_screen ---
cur("تعذر فتح الرابط", "ERR_OPEN_LINK", "errors", None)
cur("${s.exercise} — ${s.minutes.toStringAsFixed(0)} دقيقة", "WELLBEING_EXERCISE_MIN", "ui", "wellbeing", "نص ديناميكي")
cur("تمرين التنفس", "WELLBEING_BREATHING", "ui", "wellbeing")
cur("شهيق", "WELLBEING_INHALE", "ui", "wellbeing", "مرحلة تمارين التنفس")
cur("احتفظ", "WELLBEING_HOLD", "ui", "wellbeing", "مرحلة تمارين التنفس")
cur("زفير", "WELLBEING_EXHALE", "ui", "wellbeing", "مرحلة تمارين التنفس")
cur("ابدأ", "ACTION_START", "ui", "actions")
cur("الدورات المكتملة: $_cycles", "WELLBEING_CYCLES", "ui", "wellbeing", "نص ديناميكي")
cur("إيقاف", "ACTION_STOP", "ui", "actions")
cur("ابدأ التمرين", "WELLBEING_START_EXERCISE", "ui", "wellbeing")
cur("موسيقى هادئة للاسترخاء", "WELLBEING_MUSIC_TITLE", "ui", "wellbeing")
cur("فتح قائمة تشغيل خارجية", "WELLBEING_MUSIC_SUB", "ui", "wellbeing")
cur("نصائح يومية", "WELLBEING_TIPS_TITLE", "ui", "wellbeing")
cur("• اشرب كمية كافية من الماء.", "WELLBEING_TIP_WATER", "ui", "wellbeing")
cur("• تحرك كل ساعة ولو لدقائق قليلة.", "WELLBEING_TIP_MOVE", "ui", "wellbeing")
cur("• نظّم أدويتك في أوقات ثابتة.", "WELLBEING_TIP_MEDS", "ui", "wellbeing")
cur("• خذ قسطًا من النوم الكافي.", "WELLBEING_TIP_SLEEP", "ui", "wellbeing")
cur("هذه التمارين عامة ولا تُغني عن استشارة طبيبك.", "MED_EXERCISE_DISCLAIMER", "medical", None, "تحذير صحي: التمارين عامة")

# --- settings_screen ---
cur("مرحبا. سأتحدث معك ببطء ووضوح. هل تسمعني جيدا؟", "VOICE_TTS_TEST", "voice", None, "جملة اختبار النطق")
cur("بطيء جدا", "SET_RATE_VSLOW", "ui", "settings", "مستوى سرعة الصوت")
cur("بطيء - مريح لكبار السن", "SET_RATE_SLOW", "ui", "settings", "مستوى سرعة الصوت")
cur("متوسط", "LABEL_MEDIUM", "ui", "settings", "مستوى سرعة الصوت + مستوى خطورة تفاعل الوجبة")
cur("سريع", "SET_RATE_FAST", "ui", "settings", "مستوى سرعة الصوت")
cur("سرعة الصوت", "SET_VOICE_RATE", "ui", "settings")
cur("جرّب الصوت", "SET_TRY_VOICE", "ui", "settings")
cur("القيمة الافتراضية بطيئة 0.52 لتناسب كبار السن.", "SET_RATE_HINT", "ui", "settings")
cur("الوضع الهادئ", "SET_QUIET_TITLE", "ui", "settings")
cur("تعطيل تذكيرات الأدوية مؤقتًا", "SET_QUIET_SUB", "ui", "settings")
cur("فتح ببصمة الإصبع أو رمز الجهاز", "SET_LOCK_SUB", "ui", "settings")
cur("التسجيل في الذكاء الآلي", "SET_AI_ENROLL", "ui", "settings")
cur("مفعل · المفتاح:", "SET_AI_ENABLED_PREFIX", "ui", "settings", "نص ديناميكي")
cur("أدخل مفتاح DeepSeek الخاص بك ليتحدث التطبيق معك", "SET_AI_KEY_HINT", "ui", "settings")
cur("الذكاء الآلي (DeepSeek)", "SET_AI_TILE", "ui", "settings")
cur("سجّل بحساب DeepSeek واحصل على مفتاح API من منصتك، ثم الصقه هنا ليستطيع التطبيق التحدث معك عبر الإنترنت. عند غياب المفتاح يعمل التطبيق محلياً دون ذكاء آلي.", "SET_AI_HELP", "ui", "settings")
cur("مفتاح DeepSeek API", "SET_AI_KEY_FIELD", "ui", "settings")
cur("المفتاح الحالي:", "SET_AI_CURRENT_PREFIX", "ui", "settings", "نص ديناميكي")
cur("يُخزَّن المفتاح على جهازك فقط ولا يُرسل إلا إلى DeepSeek عند الدردشة.", "SET_AI_PRIVACY", "ui", "settings")
cur("حذف المفتاح", "SET_DELETE_KEY", "ui", "settings")
cur("الاحتفاظ للأبد", "SET_RETAIN_FOREVER", "ui", "settings", "خيار مدة الاحتفاظ")
cur("30 يومًا", "SET_RETAIN_30", "ui", "settings", "خيار مدة الاحتفاظ")
cur("60 يومًا", "SET_RETAIN_60", "ui", "settings", "خيار مدة الاحتفاظ")
cur("90 يومًا", "SET_RETAIN_90", "ui", "settings", "خيار مدة الاحتفاظ")
cur("180 يومًا", "SET_RETAIN_180", "ui", "settings", "خيار مدة الاحتفاظ")
cur("سنة (365 يومًا)", "SET_RETAIN_365", "ui", "settings", "خيار مدة الاحتفاظ")
cur("م.ب", "SET_UNIT_MB", "ui", "settings", "وحدة حجم (ميغابايت)")
cur("ك.ب", "SET_UNIT_KB", "ui", "settings", "وحدة حجم (كيلوبايت)")
cur("بايت", "SET_UNIT_BYTES", "ui", "settings", "وحدة حجم")
cur("تم ضبط الاحتفاظ: للأبد", "SET_RETENTION_SET", "ui", "settings")
cur("تم ضبط الاحتفاظ:", "SET_RETENTION_PREFIX", "ui", "settings", "نص ديناميكي")
cur("حُذف", "SET_REMOVED_WORD", "ui", "settings", "كلمة داخل رسالة ديناميكية")
cur("سجل قديم", "SET_OLD_RECORD", "ui", "settings", "كلمة داخل رسالة ديناميكية")
cur("مساحة البيانات والتخزين", "SET_STORAGE_TILE", "ui", "settings")
cur("الاحتفاظ:", "SET_RETENTION_LABEL", "ui", "settings", "نص ديناميكي")
cur("المساحة المستخدمة:", "SET_SIZE_LABEL", "ui", "settings", "نص ديناميكي")
cur("تعذر تصدير النسخة الاحتياطية", "ERR_SET_EXPORT", "errors", None)
cur("تم إنشاء ملف النسخة الاحتياطية", "SET_BACKUP_DONE", "ui", "settings")
cur("تم الاستيراد:", "SET_IMPORT_PREFIX", "ui", "settings", "نص ديناميكي")
cur("دواء", "MED_MEDICATION_WORD", "medical", None, "كلمة داخل رسالة ديناميكية + كلمة اكتشاف في المحادثة")
cur("قياس", "MED_MEASUREMENT_WORD", "medical", None, "كلمة داخل رسالة ديناميكية")
cur("ملف النسخة الاحتياطية غير صالح", "ERR_SET_INVALID_BACKUP", "errors", None)
cur("حذف كل البيانات", "SET_DELETE_ALL", "ui", "settings")
cur("حذف كل البيانات؟", "SET_DELETE_ALL_CONFIRM", "ui", "settings")
cur("سيتم حذف الأدوية والقياسات واليوميات نهائيًا. لا يمكن التراجع.", "SET_DELETE_ALL_WARN", "ui", "settings")
cur("أشخاص يُتواصل معهم وقت الخطر ورقم الإسعاف", "SET_EMERG_SUB", "ui", "settings")
cur("واتساب المطور", "SET_DEV_WHATSAPP", "ui", "settings")
cur("أنت على أحدث إصدار", "SET_UP_TO_DATE", "ui", "settings")
cur("تخطي هذا الإصدار", "ACTION_SKIP_VERSION", "ui", "actions")
cur("لاحقًا", "ACTION_LATER", "ui", "actions")
cur("تحديث الآن", "ACTION_UPDATE_NOW", "ui", "actions")
cur("تعذر فتح رابط التحميل", "ERR_SET_UPDATE_LINK", "errors", None)
cur("فحص التحديثات", "SET_CHECK_UPDATES", "ui", "settings")
cur("جارٍ التحقق…", "SET_CHECKING", "ui", "settings")
cur("تحقق من وجود إصدار جديد", "SET_CHECK_UPDATE_HINT", "ui", "settings")
cur("حالة الإشعارات الخلفية", "SET_BG_NOTIF_STATUS", "ui", "settings")
cur("صلاحية الإشعارات", "SET_PERM_NOTIFICATIONS", "ui", "settings")
cur("استثناء من تحسين البطارية", "SET_PERM_BATTERY", "ui", "settings")
cur("لتعمل التذكيرات في الخلفية يجب السماح بالإشعارات واستثناء التطبيق من تحسين البطارية (مهم جداً على شاومي وهواوي وسامسونج).", "SET_BG_NOTIF_HELP", "ui", "settings")
cur("طلب استثناء البطارية", "SET_REQUEST_BATTERY", "ui", "settings")
cur("فتح إعدادات النظام", "SET_OPEN_SYSTEM", "ui", "settings")
cur("مسموح", "SET_PERM_GRANTED", "ui", "settings", "حالة صلاحية")
cur("غير مسموح", "ERR_PERM_DENIED", "errors", None, "حالة صلاحية مرفوضة")
cur("الإشعارات الخلفية", "SET_BG_NOTIFS", "ui", "settings")
cur("تعمل — التذكيرات ستصل حتى والتطبيق مغلق", "SET_BG_OK", "ui", "settings")
cur("يوجد نقص في الصلاحيات — اضغط للإصلاح", "ERR_SET_PERMS_MISSING", "errors", None)
cur("مرحبًا، أودّ أن أشارك ملاحظتي حول تطبيق ALK:", "SET_FEEDBACK_MSG", "ui", "settings", "رسالة ملاحظات عبر واتساب المطور")

# --- voice_assistant_screen ---
cur("المساعد الصوتي", "VOICE_TITLE", "ui", "voice_assistant", "عنوان الشاشة + اختصار المشغل (voice_shortcut_short)")
cur("الإسعاف", "VOICE_CALL_AMBULANCE_REPLY", "voice", None, "رد منطوق عند أمر الطوارئ")
cur("لا يوجد جهة طوارئ باسم $name. أضفه من الإعدادات.", "VOICE_NO_CONTACT", "voice", None, "رد منطوق (ديناميكي)")
cur("تم، فتحت ${screenLabel(screen)}.", "VOICE_OPENED", "voice", None, "رد منطوق (ديناميكي)")
cur("تم تسجيل ${vitalLabel(kind)} بقيمة $value. أحسنت.", "VOICE_VITAL_SAVED", "voice", None, "رد منطوق (ديناميكي)")
cur("تم تسجيل وجبة $name. بارك الله فيك.", "VOICE_FOOD_SAVED", "voice", None, "رد منطوق (ديناميكي)")
cur("تمت إضافة دواء $name على الساعة $time مع تذكير.", "VOICE_MED_ADDED", "voice", None, "رد منطوق (ديناميكي)")
cur("أهلًا وسهلًا! قل مثلاً: سجّل سكر ١٤٠، أو: افتح الأدوية.", "VOICE_GREETING", "voice", None, "رد ترحيب منطوق")
cur("لم أفهم: \"$text\". جرّب: \"سجل ضغط 120 على 80\" أو \"افتح القياسات\".", "VOICE_UNKNOWN", "voice", None, "رد منطوق (ديناميكي)")
cur("جارٍ الاتصال بـ$who...", "VOICE_CALLING", "voice", None, "رد منطوق (ديناميكي)")
cur("تعذر فتح الاتصال على هذا الهاتف.", "ERR_VOICE_DIAL", "errors", None, "فشل الاتصال الهاتفي (يُنطق أيضاً)")
cur("المايك غير متاح. تأكد من إذن المايك في إعدادات الهاتف.", "ERR_VOICE_MIC", "errors", None, "بطاقة خطأ في شاشة المساعد")
cur("أتحدث… تكلم الآن", "VOICE_LISTENING", "ui", "voice_assistant")
cur("اضغط وتحدّث معي", "VOICE_TAP_TO_TALK", "ui", "voice_assistant")
cur("قلت:", "VOICE_YOU_SAID", "ui", "voice_assistant")
cur("أمثلة: \"سجل سكر ١٤٠\" • \"سجل ضغط 120 على 80\" • \"أكلت تفاحة\" • \"افتح الأدوية\"", "VOICE_EXAMPLES", "ui", "voice_assistant")
cur("أخرى", "MED_CAT_OTHER", "medical", None, "فئة دواء: أخرى (تُعين عند إضافة دواء صوتياً)")

# --- chat_screen + sandy_logic + deepseek/ai_fallback ---
cur("مرحبًا! أنا ALK، رفيقك الصحي. كيف أستطيع مساعدتك؟", "CHAT_WELCOME", "ui", "chat")
cur("(تنبيه من DeepSeek: ${result.errorMessage})", "ERR_CHAT_DEEPSEEK", "errors", None, "نص ديناميكي")
cur("الذكاء الآلي غير مفعّل. ردود محلية فقط — فعّله من الإعدادات.", "ERR_CHAT_AI_DISABLED", "errors", None)
cur("اكتب رسالتك...", "CHAT_INPUT_HINT", "ui", "chat")
cur("يمكنك فتح تبويب «الأدوية» لتأكيد جرعتك أو إضافة موعد جديد. لا تغيّر جرعتك دون الرجوع إلى مختص.", "CHAT_FALLBACK_MEDS", "ui", "chat", "رد محلي آمن (ذكاء احتياطي)")
cur("سجّل القياس كما يظهر في جهازك من تبويب «القياسات». إذا كانت النتيجة مقلقة أو ترافقها أعراض شديدة، تواصل مع مختص أو خدمات الطوارئ المحلية.", "CHAT_FALLBACK_VITALS", "ui", "chat", "رد محلي آمن")
cur("أفهم أنك لا تشعر على ما يرام. لا أستطيع تقييم الأعراض طبيًا، لكن يمكن أن تساعدك مراجعة طبيب أو الاتصال بالطوارئ عند وجود أعراض شديدة أو مفاجئة.", "CHAT_FALLBACK_SYMPTOMS", "ui", "chat", "رد محلي آمن")
cur("شكرًا لمشاركتك. يمكنني مساعدتك في تنظيم الأدوية والقياسات واليوميات، أو تذكيرك بأن أي قرار علاجي يحتاج إلى مختص.", "CHAT_FALLBACK_GENERAL", "ui", "chat", "رد محلي آمن")
cur("أنت مساعد ALK الصحي داخل تطبيق أندرويد. ردّ بلغة المستخدم (العربية غالباً) بإيجاز ووضوح، وبأسلوب ودود ومطمئن. لا تقدّم تشخيصاً طبياً نهائياً؛ شجّع على مراجعة مختص عند الأعراض الشديدة. عند ذكر الوجبات أعطِ نصيحة مختصرة واقترح تمريناً خفيفاً آمناً لكبار السن.", "CHAT_AI_SYSTEM_PROMPT", "ui", "chat", "برومبت نظام للذكاء الآلي — لا يُعرض للمستخدم مباشرة")
cur("اشرح بإيجاز ووضوح بلغة $lang لكبير سن عن: $topic. $context بدون تشخيص طبي نهائي، وبأسلوب مطمئن ومختصر.", "CHAT_AI_FALLBACK_PROMPT", "ui", "chat", "برومبت ذكاء احتياطي — لا يُعرض للمستخدم مباشرة")
cur("العربية", "CHAT_AI_LANG_ARABIC", "ui", "chat", "اسم اللغة داخل برومبت الذكاء الآلي")

# --- reminder_content.dart (الإشعارات + النطق) ---
cur("موعد دوائك", "NOTIF_REMINDER_TITLE", "notifications", None, "عنوان إشعار تناول الدواء")
cur("أهلًا، حان وقت $n. خذه الآن إذا كان مناسبًا لك.", "VOICE_REMINDER_V1", "voice", None, "يُستخدم كنص إشعار ونطق (n = اسم الدواء)")
cur("تذكير لطيف من ALK، موعد $n الآن. لا تنسَ تسجيل الجرعة بعد تناولها.", "VOICE_REMINDER_V2", "voice", None, "يُستخدم كنص إشعار ونطق (n = اسم الدواء)")
cur("مرحبًا، هذه جرعتك المجدولة من $n. اعتنِ بنفسك وخذها في الوقت المناسب.", "VOICE_REMINDER_V3", "voice", None, "يُستخدم كنص إشعار ونطق (n = اسم الدواء)")

# --- main.dart (حوار التحديث) ---
cur("يتوفر تحديث جديد", "APP_UPDATE_AVAILABLE", "ui", "app", "حوار التحديث (main + إعدادات)")

# --- models/sandy_data.dart (بأسماء ثوابتها) + state/sandy_store.dart ---
cur("حبة", "MED_FORM_TABLET", "medical", None, "شكل دواء: حبة")
cur("كبسولة", "MED_FORM_CAPSULE", "medical", None, "شكل دواء: كبسولة")
cur("سائل", "MED_FORM_LIQUID", "medical", None, "شكل دواء: سائل")
cur("شراب", "MED_FORM_SYRUP", "medical", None, "شكل دواء: شراب")
cur("إبرة", "MED_FORM_INJECTION", "medical", None, "شكل دواء: إبرة/حقنة")
cur("لصقة", "MED_FORM_PATCH", "medical", None, "شكل دواء: لصقة")
cur("قطرة", "MED_FORM_DROPS", "medical", None, "شكل دواء: قطرة")
cur("تحتاج تدقيقاً", "VITALS_QUALITY_NEEDS_REVIEW", "ui", "vitals", "حالة جودة قراءة")
cur("سليمة", "VITALS_QUALITY_OK", "ui", "vitals", "حالة جودة قراءة")
cur("بلوتوث", "VITALS_SOURCE_BLUETOOTH", "ui", "vitals", "مصدر القراءة: بلوتوث")
cur("يدوي", "VITALS_SOURCE_MANUAL", "ui", "vitals", "مصدر القراءة: إدخال يدوي")
cur("فطور", "MED_MEAL_BREAKFAST", "medical", None, "نوع وجبة: فطور")
cur("غداء", "MED_MEAL_LUNCH", "medical", None, "نوع وجبة: غداء")
cur("عشاء", "MED_MEAL_DINNER", "medical", None, "نوع وجبة: عشاء")
cur("وجبة خفيفة", "MED_MEAL_SNACK", "medical", None, "نوع وجبة: وجبة خفيفة")
cur("وجبة", "MED_MEAL_WORD", "medical", None, "كلمة وجبة (قيمة افتراضية للمساعد الصوتي)")
cur("جرعة غير محددة", "MED_DOSE_UNSPECIFIED", "medical", None, "نص بديل عند غياب الجرعة")
cur("شكل غير محدد", "MED_FORM_UNSPECIFIED", "medical", None, "نص بديل عند غياب شكل الدواء")
cur("جرعة", "MED_DOSE_WORD", "medical", None, "كلمة جرعة + كلمة اكتشاف في المحادثة")
cur("تعب", "MED_SYMPTOM_FATIGUE", "medical", None, "كلمة اكتشاف عرض: تعب")
cur("ألم", "MED_SYMPTOM_PAIN", "medical", None, "كلمة اكتشاف عرض: ألم")

# --- doctor_report_service / food_med_analysis / fat_exercise_advice ---
cur("تقرير صحي — ALK", "REPORT_SUBJECT", "ui", "reports", "موضوع البريد/المشاركة")
cur("تم تناولها", "MED_DOSE_TAKEN_LABEL", "medical", None, "حالة جرعة في التقرير")
cur("فائتة", "MED_DOSE_MISSED_LABEL", "medical", None, "حالة جرعة في التقرير")
cur("عند الحاجة", "MED_DOSE_AS_NEEDED", "medical", None, "نمط جرعة: عند الحاجة")
cur("صحة القلب", "MED_IMPACT_HEART", "medical", None, "عنوان تأثير غذائي على القلب")
cur("مرتفع — انتبه", "MED_RISK_HIGH", "medical", None, "مستوى خطورة تفاعل الوجبة")
cur("منخفض", "MED_RISK_LOW", "medical", None, "مستوى خطورة تفاعل الوجبة")
cur("لا يوجد تعارض معروف", "MED_RISK_NONE", "medical", None, "مستوى خطورة تفاعل الوجبة")
cur("تجاوز الحد", "MED_LEVEL_OVER", "medical", None, "شدة تجاوز الدهون المشبعة")
cur("قريب من الحد", "MED_LEVEL_NEAR", "medical", None, "شدة تجاوز الدهون المشبعة")
cur("ضمن الحد", "MED_LEVEL_OK", "medical", None, "شدة تجاوز الدهون المشبعة")
cur("لا دهون مشبعة معروفة", "MED_LEVEL_NONE", "medical", None, "شدة تجاوز الدهون المشبعة")
cur("كبد", "MED_COND_LIVER", "medical", None, "حالة مزمنة: كبد")
cur("كوليسترول", "MED_COND_CHOLESTEROL", "medical", None, "حالة مزمنة: كوليسترول")
cur("بدانة", "MED_COND_OBESITY", "medical", None, "حالة مزمنة: بدانة")
cur("ضأن", "MED_FOOD_LAMB_SHORT", "medical", None, "كلمة مفتاحية غذائية")

# --- كلمات مفتاحية غذائية (food_advice / fat_exercise_data / food_med_analysis) ---
_FOOD_KW = [
    ("سكريات", "MED_FOOD_SUGARIES"), ("حلويات", "MED_FOOD_SWEETS"),
    ("شوكولات", "MED_FOOD_CHOCOLATE"), ("كوكيز", "MED_FOOD_COOKIES"),
    ("بسكويت", "MED_FOOD_BISCUITS"), ("جاتوه", "MED_FOOD_GATEAU"),
    ("كيك", "MED_FOOD_CAKE"), ("عصير", "MED_FOOD_JUICE"),
    ("غازية", "MED_FOOD_SODA"), ("بيبس", "MED_FOOD_PEPSI"),
    ("كولا", "MED_FOOD_COLA"), ("مشروب غازي", "MED_FOOD_SOFT_DRINK"),
    ("نسكافيه محلى", "MED_FOOD_NESCAFE_SWEET"), ("تمور", "MED_FOOD_DATES"),
    ("تمر", "MED_FOOD_DATE"), ("عسل", "MED_FOOD_HONEY"),
    ("مربى", "MED_FOOD_JAM"), ("بطاطس", "MED_FOOD_POTATO"),
    ("بطاطا", "MED_FOOD_POTATO_ALT"), ("شبس", "MED_FOOD_CHIPS"),
    ("رقائق", "MED_FOOD_CRISPS"), ("فرايز", "MED_FOOD_FRIES"),
    ("مخللات", "MED_FOOD_PICKLES_PLURAL"), ("زيتون مملح", "MED_FOOD_SALTED_OLIVES"),
    ("ملح", "MED_FOOD_SALT"), ("أكل مالح", "MED_FOOD_SALTY_FOOD"),
    ("لانشون", "MED_FOOD_LUNCHEON"), ("بسطرمة", "MED_FOOD_PASTRAMI"),
    ("سجق", "MED_FOOD_SAUSAGE"), ("نقانق", "MED_FOOD_SAUSAGES_PL"),
    ("لحم مصنع", "MED_FOOD_PROCESSED_MEAT"), ("برجر محضر", "MED_FOOD_PREPARED_BURGER"),
    ("معلبات", "MED_FOOD_CANNED"), ("أسماك معلبة", "MED_FOOD_CANNED_FISH"),
    ("تونة معلبة", "MED_FOOD_CANNED_TUNA"), ("صلصة جاهزة", "MED_FOOD_READY_SAUCE"),
    ("كاتشب", "MED_FOOD_KETCHUP"), ("صويا صوص", "MED_FOOD_SOY_SAUCE"),
    ("جبن مالح", "MED_FOOD_SALTY_CHEESE"), ("جبنة مالح", "MED_FOOD_SALTY_CHEESE_ALT"),
    ("جبن قديم", "MED_FOOD_AGED_CHEESE"), ("أجبان مملحة", "MED_FOOD_SALTED_CHEESES"),
    ("مقلي", "MED_FOOD_FRIED"), ("مقلية", "MED_FOOD_FRIED_F"),
    ("فقوس", "MED_FOOD_FAKOUS"), ("بطاطس مقلية", "MED_FOOD_FRIED_POTATO"),
    ("دجاج مقلي", "MED_FOOD_FRIED_CHICKEN"), ("سمك مقلي", "MED_FOOD_FRIED_FISH"),
    ("زبدة", "MED_FOOD_BUTTER"), ("سمن", "MED_FOOD_GHEE"),
    ("سمنة", "MED_FOOD_GHEE_ALT"), ("كريمة", "MED_FOOD_CREAM"),
    ("دهون", "MED_FOOD_FATS"), ("مارغرين", "MED_FOOD_MARGARINE"),
    ("لحوم حمراء", "MED_FOOD_RED_MEAT"), ("قلبي", "MED_FOOD_SWEETBREAD"),
    ("لحم ضأن", "MED_FOOD_LAMB"), ("بفتيك", "MED_FOOD_BEEFSTEAK"),
    ("بقري مدهون", "MED_FOOD_FATTY_BEEF"), ("سلامي", "MED_FOOD_SALAMI"),
    ("فاست فود", "MED_FOOD_FASTFOOD"), ("شاورما", "MED_FOOD_SHAWARMA"),
    ("بيتزا", "MED_FOOD_PIZZA"), ("وجبات سريعة", "MED_FOOD_FAST_MEALS"),
    ("أرز أبيض", "MED_FOOD_WHITE_RICE"), ("رز أبيض", "MED_FOOD_WHITE_RICE_ALT"),
    ("عيش أبيض", "MED_FOOD_WHITE_BREAD_ALT"), ("معكرونة", "MED_FOOD_MACARONI"),
    ("مكرونة", "MED_FOOD_MACARONI_ALT"), ("باستا", "MED_FOOD_PASTA"),
    ("خضار", "MED_FOOD_VEGETABLES"), ("سلطة خضار", "MED_FOOD_VEG_SALAD"),
    ("فواكه طازجة", "MED_FOOD_FRESH_FRUIT"), ("زبدة محلى", "MED_FOOD_BUTTER_SWEET"),
]
for _t, _k in _FOOD_KW:
    cur(_t, _k, "medical", None, "مصطلح/كلمة مفتاحية غذائية (قواعد الأطعمة والدهون)")

# --- تسميات المساعد الصوتي (voice_intent.dart) ---
cur("اليوميات", "JOURNALS_TAB", "ui", "journals", "اسم شاشة اليوميات في المساعد الصوتي")
cur("المحادثة", "CHAT_TAB", "ui", "chat", "اسم شاشة المحادثة في المساعد الصوتي")
cur("السكر", "MED_SUGAR_THE", "medical", None, "تسمية منطوقة لقياس السكر")
cur("الضغط", "MED_PRESSURE_THE", "medical", None, "تسمية منطوقة لقياس الضغط")

# --- widgets ---
cur("إيقاف الصوت", "WIDGET_STOP_SPEAK", "ui", "widgets", "زر إيقاف النطق")
cur("استمع", "WIDGET_LISTEN", "ui", "widgets", "زر الاستماع")
cur("اقرأ لي بصوت بطيء", "WIDGET_SLOW_READ", "ui", "widgets", "زر القراءة البطيئة")
cur("اضغط زر السماعة لسماع الشرح", "WIDGET_SPEAKER_HINT", "ui", "widgets", "وصف زر السماعة")
cur("شرح إضافي من الذكاء الآلي", "WIDGET_AI_MORE", "ui", "wellbeing")
cur("الذكاء الآلي غير متاح حالياً. أضف مفتاح API من الإعدادات ثم أعد المحاولة. المعلومات المحلية أعلاه تكفي للاستخدام اليومي.", "ERR_AI_UNAVAILABLE", "errors", None)
cur("معلومات غير كافية؟ اسأل الذكاء الآلي", "WIDGET_AI_ASK", "ui", "wellbeing")
cur("يتطلب إضافة مفتاح API في الإعدادات", "WIDGET_AI_REQUIREMENT", "ui", "wellbeing")
cur("حالتك: $mood", "WIDGET_MOOD_LABEL", "ui", "wellbeing", "نص ديناميكي")
cur("يناسبك: ${rec.exerciseTitle}", "WIDGET_MOOD_SUIT", "ui", "wellbeing", "نص ديناميكي")
cur("حالتك $mood. ${rec.exerciseTitle}. ${rec.tip}", "WIDGET_MOOD_SUMMARY", "ui", "wellbeing", "نص ديناميكي")

# ---------------------------------------------------------------------------
# 3) الأوامر الصوتية (voice_intent.dart): أنماط regex منسوخة حرفياً + بدائل
# ---------------------------------------------------------------------------

VOICE_COMMANDS = [
    {"key": "CMD_CALL_AMBULANCE", "text": "طوارئ|طوارى|اسعاف|إسعاف|نجدة",
     "aliases": ["طوارئ", "طوارى", "اسعاف", "إسعاف", "نجدة"],
     "source": "lib/logic/voice_intent.dart:105", "note": "أمر: الاتصال بالإسعاف فوراً"},
    {"key": "CMD_CALL_CONTACT",
     "text": r"(?:اتصل|إتصل|اتّصل|دي|ناد)\s*(?:على|إلى|الى)?\s*([أ-ي\u064B-\u0652]+(?:\s[أ-ي\u064B-\u0652]+)?)",
     "aliases": ["اتصل", "إتصل", "اتّصل", "دي", "ناد", "على", "إلى", "الى"],
     "source": "lib/logic/voice_intent.dart:108-110", "note": "أمر: الاتصال بجهة اتصال بالاسم"},
    {"key": "CMD_OPEN", "text": "افتح|فتح|اذهب|روح|اعرض",
     "aliases": ["افتح", "فتح", "اذهب", "روح", "اعرض"],
     "source": "lib/logic/voice_intent.dart:123", "note": "بادئة أمر: فتح شاشة"},
    {"key": "CMD_OPEN_VITALS", "text": "قياس|مؤشر|الضغط|السكر|النبض",
     "aliases": ["قياس", "مؤشر", "الضغط", "السكر", "النبض"],
     "source": "lib/logic/voice_intent.dart:124", "note": "أمر: فتح شاشة القياسات"},
    {"key": "CMD_OPEN_MEDICATIONS", "text": "دواء|أدوية|ادوية|دوائي|أدويتي|ادويتي|علاج|جرعة",
     "aliases": ["دواء", "أدوية", "ادوية", "دوائي", "أدويتي", "ادويتي", "علاج", "جرعة"],
     "source": "lib/logic/voice_intent.dart:127", "note": "أمر: فتح شاشة الأدوية"},
    {"key": "CMD_OPEN_NUTRITION", "text": "طعام|اكل|أكل|وجب|تغذية|غذا",
     "aliases": ["طعام", "اكل", "أكل", "وجب", "تغذية", "غذا"],
     "source": "lib/logic/voice_intent.dart:130", "note": "أمر: فتح شاشة التغذية"},
    {"key": "CMD_OPEN_JOURNALS", "text": "يومي|مذك|مشاعر",
     "aliases": ["يومي", "مذك", "مشاعر"],
     "source": "lib/logic/voice_intent.dart:133", "note": "أمر: فتح شاشة اليوميات"},
    {"key": "CMD_OPEN_REPORTS", "text": "تقرير", "aliases": ["تقرير"],
     "source": "lib/logic/voice_intent.dart:136", "note": "أمر: فتح شاشة التقارير"},
    {"key": "CMD_OPEN_CHAT", "text": "محادث|دردش|مساعد",
     "aliases": ["محادث", "دردش", "مساعد"],
     "source": "lib/logic/voice_intent.dart:139", "note": "أمر: فتح شاشة المحادثة"},
    {"key": "CMD_OPEN_MORE", "text": "اعداد|إعدادات|المزيد",
     "aliases": ["اعداد", "إعدادات", "المزيد"],
     "source": "lib/logic/voice_intent.dart:142", "note": "أمر: فتح شاشة الإعدادات/المزيد"},
    {"key": "CMD_GREETING", "text": "^مرحبا|^مرحبًا|^اهلا|^أهلا|^السلام|^هاي|^هلا",
     "aliases": ["مرحبا", "مرحبًا", "اهلا", "أهلا", "السلام", "هاي", "هلا"],
     "source": "lib/logic/voice_intent.dart:148", "note": "أمر: تحية"},
    {"key": "CMD_LOG_SUGAR", "text": "سكر|غلوكوز|جلوكوز",
     "aliases": ["سكر", "غلوكوز", "جلوكوز"],
     "source": "lib/logic/voice_intent.dart:153", "note": "أمر: تسجيل سكر"},
    {"key": "CMD_LOG_PRESSURE", "text": "ضغط", "aliases": ["ضغط"],
     "source": "lib/logic/voice_intent.dart:154", "note": "أمر: تسجيل ضغط"},
    {"key": "CMD_LOG_PULSE", "text": "نبض|ضربات", "aliases": ["نبض", "ضربات"],
     "source": "lib/logic/voice_intent.dart:155", "note": "أمر: تسجيل نبض"},
    {"key": "CMD_ADD_MEDICATION_NAME",
     "text": r"(?:دواء|علاج)\s+([\u0600-\u06FF]+(?:\s[\u0600-\u06FF]+)?)",
     "aliases": ["دواء", "علاج"],
     "source": "lib/logic/voice_intent.dart:171", "note": "أمر: إضافة دواء بالاسم"},
    {"key": "CMD_ADD_MEDICATION_TIME",
     "text": r"(?:الساعة|ساعة|عند)\s*([0-9]+(?:\.[0-9]+)?)",
     "aliases": ["الساعة", "ساعة", "عند"],
     "source": "lib/logic/voice_intent.dart:175", "note": "أمر: تحديد موعد الدواء"},
    {"key": "CMD_ADD_FOOD",
     "text": r"(?:اكلت|أكلت|تناولت|شربت|سجل وجبة|اضف وجبة)\s+(.+)",
     "aliases": ["اكلت", "أكلت", "تناولت", "شربت", "سجل وجبة", "اضف وجبة"],
     "source": "lib/logic/voice_intent.dart:190", "note": "أمر: تسجيل وجبة/طعام"},
    {"key": "CMD_STRIP_TIME_SUFFIX", "text": r"\s*(?:اليوم|الان|الآن|صباحا|مساء)$",
     "aliases": ["اليوم", "الان", "الآن", "صباحا", "مساء"],
     "source": "lib/logic/voice_intent.dart:195", "note": "تنظيف داخلي: إزالة ظرف الزمن"},
    {"key": "CMD_MEAL_BREAKFAST", "text": "فطور", "aliases": ["فطور"],
     "source": "lib/logic/voice_intent.dart:200", "note": "كلمة مفتاحية: وجبة الفطور"},
    {"key": "CMD_MEAL_LUNCH", "text": "غداء", "aliases": ["غداء"],
     "source": "lib/logic/voice_intent.dart:201", "note": "كلمة مفتاحية: وجبة الغداء"},
    {"key": "CMD_MEAL_DINNER", "text": "عشاء", "aliases": ["عشاء"],
     "source": "lib/logic/voice_intent.dart:202", "note": "كلمة مفتاحية: وجبة العشاء"},
    {"key": "CMD_MEAL_SNACK", "text": "خفيف|سناك", "aliases": ["خفيف", "سناك"],
     "source": "lib/logic/voice_intent.dart:203", "note": "كلمة مفتاحية: وجبة خفيفة"},
    {"key": "CMD_STRIP_PUNCT", "text": r"[.،,!?؟]$",
     "aliases": [".", "،", ",", "!", "?", "؟"],
     "source": "lib/logic/voice_intent.dart:196", "note": "تنظيف داخلي: إزالة علامات الترقيم"},
]

# ---------------------------------------------------------------------------
# 4) قواعد التصنيف الافتراضية حسب الملف
# ---------------------------------------------------------------------------

SCREEN_OF_FILE = {
    "home_screen": "home", "chat_screen": "chat", "emergency_screen": "emergency",
    "journals_screen": "journals", "lock_screen": "lock",
    "medications_screen": "medications", "more_screen": "more",
    "nutrition_screen": "nutrition", "patient_screen": "profile",
    "reports_screen": "reports", "settings_screen": "settings",
    "vitals_screen": "vitals", "voice_assistant_screen": "voice_assistant",
    "wellbeing_screen": "wellbeing",
}

MEDICAL_FILES = {
    "lib/logic/fat_exercise_data.dart", "lib/logic/food_advice.dart",
    "lib/logic/food_med_analysis.dart", "lib/logic/fat_exercise_advice.dart",
    "lib/logic/mood_wellbeing.dart", "lib/logic/vital_quality.dart",
    "lib/models/sandy_data.dart", "lib/state/sandy_store.dart",
    "lib/logic/medication_times.dart",
}

SCREEN_PREFIX = {
    "home": "HOME", "chat": "CHAT", "emergency": "EMERG", "journals": "JOURNAL",
    "lock": "LOCK", "medications": "MEDS", "more": "MORE", "nutrition": "NUTRI",
    "profile": "PROFILE", "reports": "REPORT", "settings": "SET",
    "vitals": "VITALS", "voice_assistant": "VOICE", "wellbeing": "WELL",
    "widgets": "WIDGET", "app": "APP", "actions": "ACTION",
}

ERROR_PAT = re.compile(
    r"تعذر|تعذُّر|تعذّر|فشل|خطأ|لم يُمنح|لم تُمنح|لم يُضبط|لم يحصل|"
    r"غير متاح|غير مسموح|غير صالح|لا يمكن|غير صحيح|غير مفعّل|تأكد أنه"
)


def classify(rel, text, line_text):
    """يعيد (key, category, screen, note)."""
    hit = C.get(text)
    if hit:
        return hit[0], hit[1], hit[2], hit[3]
    if ERROR_PAT.search(text):
        return "ERR_" + md6(text), "errors", None, "مفتاح مولّد تلقائياً (نص خطأ/تحقق)"
    base = rel.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    if rel in MEDICAL_FILES:
        return "MED_" + md6(text), "medical", None, "مصطلح/نص من قاعدة البيانات المحلية"
    if rel == "lib/services/reminder_content.dart":
        return "VOICE_" + md6(text), "voice", None, "مفتاح مولّد تلقائياً (نص تذكير/نطق)"
    if "_respond(" in line_text or "_dial(" in line_text:
        return "VOICE_" + md6(text), "voice", None, "مفتاح مولّد تلقائياً (رد منطوق)"
    if rel.startswith("lib/screens/"):
        scr = SCREEN_OF_FILE.get(base, "app")
        return SCREEN_PREFIX.get(scr, "UI") + "_" + md6(text), "ui", scr, "مفتاح مولّد تلقائياً"
    if rel.startswith("lib/widgets/"):
        return "WIDGET_" + md6(text), "ui", "widgets", "مفتاح مولّد تلقائياً"
    if rel == "lib/main.dart":
        return "APP_" + md6(text), "ui", "app", "مفتاح مولّد تلقائياً"
    if rel.startswith("lib/services/"):
        if "deepseek_service" in rel or "ai_fallback" in rel:
            return "CHAT_" + md6(text), "ui", "chat", "برومبت/نص محادثة — لا يُعرض مباشرة"
        if "feedback_service" in rel:
            return "SET_" + md6(text), "ui", "settings", "مفتاح مولّد تلقائياً"
        if "doctor_report_service" in rel:
            return "REPORT_" + md6(text), "ui", "reports", "نص قالب تقرير الطبيب"
        return "APP_" + md6(text), "ui", "app", "مفتاح مولّد تلقائياً"
    if rel == "lib/state/alk_strings.dart":
        return "ALK_" + md6(text), "ui", "app", "مفتاح مولّد تلقائياً"
    return "UI_" + md6(text), "ui", "app", "مفتاح مولّد تلقائياً"

# ---------------------------------------------------------------------------
# 5) المسح والبناء
# ---------------------------------------------------------------------------

def main():
    entries = {}          # (category, screen, text) -> entry
    key_owner = {}        # key -> (category, screen, text) لضمان عدم تكرار المفاتيح
    files_read = []
    comment_only_files = []
    skipped = []
    warnings = []

    dart_files = sorted(LIB.rglob("*.dart"))
    total_literals = 0
    for path in dart_files:
        rel = rel_of(path)
        src = path.read_text(encoding="utf-8", errors="ignore")
        src_lines = src.splitlines()
        regex_lines = {i + 1 for i, ln in enumerate(src_lines) if "RegExp(" in ln}
        kept = []
        for raw, start in extract_all(src):
            text = raw.strip()
            if not text or not ARABIC_LETTER.search(text):
                continue
            line = src.count("\n", 0, start) + 1
            if rel.endswith("voice_intent.dart"):
                # أنماط الأوامر توثَّق في VOICE_COMMANDS — نتجاهل الأجزاء ذات صيغة regex
                if line in regex_lines or text.startswith("(") or "(?:" in text or "\\u" in text:
                    continue
            kept.append((text, line, src_lines[line - 1] if line - 1 < len(src_lines) else ""))
        files_read.append({"file": rel, "arabic_literals": len(kept)})
        total_literals += len(kept)
        if not kept and ARABIC_LETTER.search(src):
            comment_only_files.append(rel)
        for text, line, line_text in kept:
            key, cat, scr, note = classify(rel, text, line_text)
            gkey = (cat, scr or "", text)
            if gkey not in entries:
                # ضمان تفرد المفتاح داخل كل فئة
                if key in key_owner:
                    k2 = key + "_" + md6(text)[:2]
                    while k2 in key_owner:
                        k2 += "X"
                    key = k2
                key_owner[key] = gkey
                e = OrderedDict()
                e["key"] = key
                e["text"] = text
                e["v"] = 1
                e["sources"] = [f"{rel}:{line}"]
                if note:
                    e["note"] = note
                if cat == "medical":
                    e["requires_manual_review"] = True
                if "$" in text:
                    e["note"] = ((e["note"] + "؛ ") if e.get("note") else "") + "نص يحتوي متغيرات ديناميكية ($)"
                entries[gkey] = e
            else:
                e = entries[gkey]
                s = f"{rel}:{line}"
                if s not in e["sources"]:
                    e["sources"].append(s)

    # الأوامر الصوتية (منسّقة يدوياً من voice_intent.dart)
    for cmd in VOICE_COMMANDS:
        gkey = ("voice_commands", None, cmd["text"])
        if gkey in entries:
            continue
        e = OrderedDict()
        e["key"] = cmd["key"]
        e["text"] = cmd["text"]
        e["v"] = 1
        e["sources"] = [cmd["source"]]
        e["aliases"] = cmd["aliases"]
        if cmd.get("note"):
            e["note"] = cmd["note"]
        entries[gkey] = e

    # strings.xml (Android) — نستخدم اسم المفتاح الأصلي كما هو
    strings_xml = ROOT / "android/app/src/main/res/values/strings.xml"
    if strings_xml.exists():
        xml = strings_xml.read_text(encoding="utf-8", errors="ignore")
        xml_lines = xml.splitlines()
        found = 0
        for m in re.finditer(r'<string name="([^"]+)">([^<]*)</string>', xml):
            name, val = m.group(1), m.group(2).strip()
            if not ARABIC_LETTER.search(val):
                continue
            found += 1
            line_no = next((i for i, ln in enumerate(xml_lines, 1) if name in ln), 1)
            gkey = ("ui", "app", val)
            if gkey in entries:
                entries[gkey]["sources"].append(f"android/app/src/main/res/values/strings.xml:{line_no}")
                continue
            e = OrderedDict()
            e["key"] = name.upper()
            e["text"] = val
            e["v"] = 1
            e["sources"] = [f"android/app/src/main/res/values/strings.xml:{line_no}"]
            e["note"] = "اختصار المشغل في Android (اسم المفتاح الأصلي من strings.xml)"
            entries[gkey] = e
        files_read.append({"file": rel_of(strings_xml), "arabic_strings": found})

    # AndroidManifest.xml
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    if manifest.exists():
        mt = manifest.read_text(encoding="utf-8", errors="ignore")
        mm = re.search(r'android:label="([^"]*)"', mt)
        label = mm.group(1) if mm else ""
        files_read.append({
            "file": rel_of(manifest),
            "android_label": label,
            "arabic_strings": 1 if ARABIC_LETTER.search(label) else 0,
        })
        if label and not ARABIC_LETTER.search(label):
            warnings.append(f"android:label في AndroidManifest.xml هو '{label}' (لاتينية وليست عربية — لم تُدرج في القاموس)")
        if "<!--" in mt and ARABIC_LETTER.search(mt):
            warnings.append("يوجد نص عربي داخل تعليقات XML/شيفرة (مثل 'افتح المساعد الصوتي في ALK' في shortcuts/manifest) — تعليقات تطويرية لا تُعرض للمستخدم فلم تُدرج.")

    # ---- ملفات متجاهلة (تُوثَّق في التقرير) ----
    for p in sorted((ROOT / "test").rglob("*.dart")):
        skipped.append({"file": rel_of(p), "reason": "اختبارات مطوّر — لا تُعرض للمستخدم"})
    for p in sorted(ROOT.glob("tool_*.py")):
        skipped.append({"file": p.name, "reason": "أداة صيانة للمطور — ليست من التطبيق"})
    for name in ["APP_DOCUMENTATION_AR.md", "APP_DOCUMENTATION_EN.md", "APP_SALES_AR.md",
                 "APP_SALES_EN.md", "PROJECT_STATUS.md", "README.md",
                 "دليل-استخدام-ALK.md", "دليل-التحديث.md"]:
        if (ROOT / name).exists():
            skipped.append({"file": name, "reason": "توثيق خارج التطبيق"})
    for d in ["word", "update", "scripts", "tool"]:
        dp = ROOT / d
        if dp.exists():
            skipped.append({"file": d + "/", "reason": "مجلد أدوات/مستندات خارج كود التطبيق"})

    # ---- تجميع الفئات ----
    ui_screens = {}
    cats = {"voice": OrderedDict(), "voice_commands": OrderedDict(),
            "notifications": OrderedDict(), "errors": OrderedDict(),
            "medical": OrderedDict()}
    for gkey, e in entries.items():
        cat, scr, text = gkey
        if cat == "ui":
            ui_screens.setdefault(scr or "app", {})[e["key"]] = e
        else:
            cats[cat][e["key"]] = e
    for scr in ui_screens:
        ui_screens[scr] = OrderedDict(sorted(ui_screens[scr].items()))
    for c in cats:
        cats[c] = OrderedDict(sorted(cats[c].items()))

    categories = OrderedDict()
    categories["ui"] = OrderedDict()
    categories["ui"]["screens"] = OrderedDict(sorted(ui_screens.items()))
    categories["voice"] = cats["voice"]
    categories["voice_commands"] = cats["voice_commands"]
    categories["notifications"] = cats["notifications"]
    categories["errors"] = cats["errors"]
    categories["medical"] = cats["medical"]

    total = sum(len(s) for s in ui_screens.values()) + sum(len(c) for c in cats.values())
    by_cat = OrderedDict()
    by_cat["ui"] = OrderedDict((k, len(v)) for k, v in sorted(ui_screens.items()))
    by_cat["ui_total"] = sum(len(s) for s in ui_screens.values())
    for c in ["voice", "voice_commands", "notifications", "errors", "medical"]:
        by_cat[c] = len(cats[c])

    merged = []
    for gkey, e in entries.items():
        if len(e["sources"]) > 1:
            merged.append({"key": e["key"], "text": e["text"], "sources": e["sources"]})
    merged.sort(key=lambda m: m["key"])

    if comment_only_files:
        warnings.append(
            "ملفات عربية موجودة داخل التعليقات فقط (للتطوير): " + ", ".join(comment_only_files)
        )
    warnings.append("النصوص التي تحوي ($ ) متغيرات ديناميكية نُسخت حرفياً كما هي في الشيفرة، وقيم المتغيرات تُبنى وقت التشغيل.")
    warnings.append("أوامر المساعد الصوتي (voice_commands) موثقة بأنماط regex منسوخة حرفياً مع البدائل (aliases) المستخرجة من voice_intent.dart.")
    warnings.append("مفاتيح الصيغة PREFIX_<hash> مولّدة تلقائياً ويمكن إعادة تسميتها يدوياً دون المساس بالمصادر.")

    dictionary = OrderedDict()
    dictionary["meta"] = OrderedDict([
        ("version", VERSION),
        ("language", "ar"),
        ("app_name", APP_NAME),
        ("generated_at", datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")),
        ("total_strings", total),
        ("extractor", "tool_extract_dictionary.py"),
    ])
    dictionary["categories"] = categories
    dictionary["statistics"] = OrderedDict([
        ("total_strings", total),
        ("by_category", by_cat),
        ("total_raw_literals", total_literals),
        ("duplicates_merged", total_literals - total if total_literals > total else 0),
    ])
    dictionary["extraction_report"] = OrderedDict([
        ("files_read", files_read),
        ("files_skipped", skipped),
        ("duplicates_merged", merged),
        ("warnings", warnings),
    ])

    def dump(path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(dictionary, ensure_ascii=False, indent=2) + "\n",
                        encoding="utf-8")

    dump(OUT_ROOT)
    dump(OUT_ASSETS)

    # ---- تحقق: إعادة التحميل والتطابق ----
    for p in (OUT_ROOT, OUT_ASSETS):
        loaded = json.loads(p.read_text(encoding="utf-8"))
        assert loaded["meta"]["total_strings"] == total, f"عدم تطابق العدد في {p}"
    print(f"OK: source_dictionary.json — {total} مفردة")
    for c in ["voice", "voice_commands", "notifications", "errors", "medical"]:
        print(f"  {c}: {len(cats[c])}")
    print(f"  ui: {by_cat['ui_total']} عبر {len(ui_screens)} شاشة")
    print(f"  مكررات مدمجة: {len(merged)} | ملفات مقروءة: {len(files_read)}")


if __name__ == "__main__":
    main()














