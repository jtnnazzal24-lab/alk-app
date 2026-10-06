import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../state/sandy_store.dart';
import '../widgets/speak_button.dart';

/// شاشة سياسة الخصوصية — نص عربي ثابت داخل التطبيق يعمل دون إنترنت.
/// يطابق النص الكامل ملف `PRIVACY_POLICY_AR.md` في جذر المشروع.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});
  static const _s1t = 'ملخص سريع';
  static const _s1b = 'بياناتك الصحية تبقى على هاتفك فقط. لا حسابات ولا خوادم، '
      'ولا إعلانات ولا تتبع ولا بيع بيانات. أنت من يرسل تقريرك '
      'لطبيبك بيدك فقط عندما تختار ذلك، ويمكنك حذف كل بياناتك '
      'من الإعدادات في أي وقت.';
  static const _s2t = 'البيانات وأين تحفظ';
  static const _s2b = 'الاسم والهوية والحالة، الأدوية ومواعيدها وسجل التناول، '
      'القياسات (ضغط وسكر ونبض وأكسجين)، الوجبات مع تحليلها، اليوميات '
      'والمزاج وجهات الطوارئ — كلها في ملف داخل مجلد التطبيق الخاص '
      'على جهازك. والملف مشفَّر (AES-256-GCM) ومفتاحه في خزنة الجهاز '
      'الآمنة، ولا تُنسخ هذه البيانات في النسخ الاحتياطي السحابي ولا في '
      'نقل الجهاز. لا شيء يغادر جهازك إلا بنسخة تصدرها أو تقرير ترسله.';
  static const _s3t = 'الأذونات ولماذا نطلبها';
  static const _s3b = 'الإشعارات والمنبهات لتذكير الدواء وتنبيهات المستوى الغذائي '
      'الأول والثاني في وقتها حتى والتطبيق مغلق. البلوتوث لأجهزة القياس. '
      'الميكروفون لزر المايك فقط بلا تسجيل خلفية. الكاميرا لصورة الدواء '
      'والتقرير الطبي فقط. البصمة لقفل التطبيق. الاتصال لزر الإسعاف فقط. '
      'كل المهام اليومية تعمل دون إنترنت.';
  static const _s4t = 'الخدمات الخارجية (فقط عندما تطلبها)';
  static const _s4b = 'الذكاء الآلي لا يعمل إلا بمفتاحك الخاص ويرسل سؤالك فقط. '
      'ترجمة الواجهة للمفردات العامة مرة واحدة عبر خدمة ترجمة Google، '
      'ولا تُرسل بياناتك الصحية ولا يومياتك للترجمة.';
  static const _s5t = 'ما ترسله بنفسك فقط';
  static const _s5b = 'تقرير الطبيب لا يرسل تلقائيا أبدا. أنت تضغط واتساب أو بريد '
      'أو مشاركة ثم تؤكد بنفسك. النسخة الاحتياطية أنت من يصدرها ويحفظها.';
  static const _s6t = 'الأطفال والاحتفاظ والحذف';
  static const _s6b = 'التطبيق لكبار السن وليس للأطفال. الاحتفاظ الافتراضي 30 يوما '
      'ويمكن تعديله حتى للأبد. مسح كل البيانات يحذف الملف المحلي نهائيا.';
  static const _s7t = 'الأمان وحقوقك والاتصال';
  static const _s7b = 'البيانات مشفَّرة داخل مجلد التطبيق الخاص (AES-256-GCM). '
      'قفل اختياري بالبصمة أو الوجه يُعاد تلقائياً عند مغادرة التطبيق، '
      'وكل الشاشات — حتى المفتوحة من الإشعارات — تبقى خلف القفل. '
      'لقطات الشاشة ومعاينة التطبيقات الحديثة محجوبة، ومفتاح الذكاء الآلي '
      'يُحفظ في خزنة الجهاز ويُعرض مخفياً. '
      'كل بياناتك ظاهرة داخل الشاشات ويمكنك تعديلها أو حذفها. '
      'آخر تحديث: 29 سبتمبر 2026. اتصل بنا: الإعدادات ثم ملاحظات.';
  @override
  Widget build(BuildContext context) {
    final lang = context.read<SandyStore>().languageTag;
    const fullText = 'ملخص. بياناتك على هاتفك فقط. التفاصيل في الأقسام التالية.';
    final sections = <({String title, String body})>[
      (title: _s1t, body: _s1b),
      (title: _s2t, body: _s2b),
      (title: _s3t, body: _s3b),
      (title: _s4t, body: _s4b),
      (title: _s5t, body: _s5b),
      (title: _s6t, body: _s6b),
      (title: _s7t, body: _s7b),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('سياسة الخصوصية'.tr),
        actions: [SpeakButton(text: fullText, languageTag: lang)],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text('سياسة الخصوصية'.tr),
                subtitle: Text('آخر تحديث: 29 سبتمبر 2026'.tr),
                trailing: SpeakButton(text: fullText, languageTag: lang),
              ),
            );
          }
          final s = sections[index - 1];
          return Card(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.title.tr,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      SpeakButton(
                        text: s.title,
                        languageTag: lang,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(s.body.tr),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

