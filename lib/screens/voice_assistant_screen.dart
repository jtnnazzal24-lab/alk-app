import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/fat_exercise_advice.dart';
import '../logic/voice_intent.dart';
import '../models/sandy_data.dart';
import '../services/dictionary_translation_service.dart';
import '../services/notification_service.dart';
import '../services/voice_service.dart';
import '../l10n/app_strings.dart';
import '../state/sandy_store.dart';

/// ALK voice assistant — one large button for elderly users: they speak,
/// the app understands the intent (store data or navigate) and replies
/// aloud, so no typing is needed.
class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({super.key});

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  final VoiceService _voice = VoiceService.instance;
  bool _listening = false;
  bool _unavailable = false;
  String _transcript = '';
  String _reply = '';

  Future<void> _toggle() async {
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final locale = context.read<SandyStore>().languageTag;
    final ok = await _voice.startListening(
      localeId: locale.split('-').first,
      onResult: (text) {
        if (mounted) setState(() => _transcript = text);
      },
    );
    if (!ok) {
      if (mounted) setState(() => _unavailable = true);
      return;
    }
    setState(() {
      _listening = true;
      _transcript = '';
      _reply = '';
    });
    // Elderly-friendly: listen for a few seconds, then stop and execute.
    Future<void>.delayed(const Duration(seconds: 6), () async {
      if (!mounted || !_listening) return;
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      // محرّك الكلام ديناميكي: الاستماع بلغة الهاتف، والفهم بعد إرجاع الجملة
      // للعربية، والرد يُعرض ويُنطق بلغة الهاتف.
      await _execute(_transcript);
    });
  }

  Future<void> _respond(String text) async {
    if (!mounted) return;
    final language = context.read<SandyStore>().languageTag;
    if (!mounted) return;
    // الرد المكتوب/المنطوق بلغة الواجهة (محرّك النطق ديناميكي).
    setState(() => _reply = text);
    await _voice.speak(
      text,
      languageTag: language,
      slow: true,
    );
  }

  Future<void> _execute(String spoken) async {
    // محرّك التعرّف على الكلام ديناميكي فيرجّع النص بلغة الهاتف؛ تُرجَع الجملة
    // إلى العربية (لغة قواعد الفهم) قبل تحليل النية، ثم يُنطق الرد بلغة الهاتف.
    final normalized =
        await DictionaryTranslationService.instance.toSourceLanguage(spoken);
    if (!mounted) return;
    final intent = parseVoiceIntent(normalized);
    final store = context.read<SandyStore>();
    switch (intent) {
      case VoiceCallAmbulance():
        await _dial(store.ambulanceNumber, 'الإسعاف'.tr);
        return;
      case VoiceCallContact(:final name):
        // Fuzzy match: contact whose name starts with / contains spoken name.
        final match =
            store.emergencyContacts.cast<EmergencyContact?>().firstWhere(
                  (c) => c!.name.contains(name) || name.contains(c.name),
                  orElse: () => null,
                );
        if (match == null) {
          await _respond('لا يوجد جهة طوارئ باسم $name. أضفه من الإعدادات.'.tr);
          return;
        }
        await _dial(match.phone, match.name);
        return;
      case VoiceOpenScreen(:final screen):
        VoiceNavigator.open?.call(screen);
        await _respond('تم، فتحت ${screenLabel(screen)}.'.tr);
        return;
      case VoiceAddVital(:final kind, :final value):
        await store.addVital(kind, value);
        await _respond('تم تسجيل ${vitalLabel(kind)} بقيمة $value. أحسنت.'.tr);
        return;
      case VoiceAddFood(:final name, :final mealType):
        await store.addFood(name, mealType);
        // نفس تنبيه المستوى الأول/الثاني الصوتي كما في شاشة التغذية.
        final foodAdvice = adviceForDay(data: store.data);
        if (foodAdvice.level == FatAdviceLevel.over ||
            foodAdvice.level == FatAdviceLevel.warn) {
          final isOver = foodAdvice.level == FatAdviceLevel.over;
          final title = isOver
              ? 'تنبيه المستوى الأول: تجاوزت حد الدهون'.tr
              : 'تنبيه المستوى الثاني: اقتربت من حد الدهون'.tr;
          try {
            await NotificationService.instance.showFoodAlertNotification(
              level: foodAdvice.level,
              title: title,
              body: adviceSummaryText(foodAdvice).tr,
            );
          } catch (_) {}
          await _respond(
              'تم تسجيل وجبة $name. تنبيه غذائي: ${adviceSummaryText(foodAdvice)}. ${foodAdvice.conditionAdvice}'
                  .tr);
        } else {
          await _respond('تم تسجيل وجبة $name. بارك الله فيك.'.tr);
        }
        return;
      case VoiceAddMedication(:final name, :final time):
        await store.addMedication(
          name: name,
          time: time,
          // القيمة المخزّنة تبقى عربية (مفتاح منطق)؛ العرض يُترجم عبر .tr.
          category: MedicationCategory.general,
          reminderEnabled: true,
        );
        await _respond('تمت إضافة دواء $name على الساعة $time مع تذكير.'.tr);
        return;
      case VoiceGreeting():
        await _respond(
            'أهلًا وسهلًا! قل مثلاً: سجّل سكر ١٤٠، أو: افتح الأدوية.'.tr);
        return;
      case VoiceUnknown(:final text):
        await _respond(
          'لم أفهم: "$text". جرّب: "سجل ضغط 120 على 80" أو "افتح القياسات".'.tr,
        );
        return;
    }
  }

  /// Opens the dialer (and calls where CALL_PHONE is granted) for [phone].
  Future<void> _dial(String phone, String who) async {
    await _respond('جارٍ الاتصال بـ$who...'.tr);
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      // FIX: launch directly — `canLaunchUrl` fails for tel: on Android 11+
      // without <queries> package visibility for the dialer.
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        await _respond('تعذر فتح الاتصال على هذا الهاتف.'.tr);
      }
    } catch (_) {
      await _respond('تعذر فتح الاتصال على هذا الهاتف.'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('المساعد الصوتي'.tr)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_unavailable) ...[
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'المايك غير متاح. تأكد من إذن المايك في إعدادات الهاتف.'
                          .tr,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              _MicButton(listening: _listening, onTap: _toggle),
              const SizedBox(height: 16),
              Text(
                _listening ? 'أتحدث… تكلم الآن'.tr : 'اضغط وتحدّث معي'.tr,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              if (_transcript.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('${'قلت:'} $_transcript'),
                  ),
                ),
              if (_reply.isNotEmpty)
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_reply),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'أمثلة: "سجل سكر ١٤٠" • "سجل ضغط 120 على 80" • '
                        '"أكلت تفاحة" • "افتح الأدوية"'
                    .tr,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Large friendly pulsing microphone button.
class _MicButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onTap;

  const _MicButton({required this.listening, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: listening ? 170 : 140,
        height: listening ? 170 : 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              listening ? theme.colorScheme.error : theme.colorScheme.primary,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
              blurRadius: listening ? 32 : 12,
              spreadRadius: listening ? 8 : 2,
            ),
          ],
        ),
        child: Icon(
          listening ? Icons.mic : Icons.mic_none,
          size: 64,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}

/// Bridge used by the assistant to switch tabs on the home screen.
class VoiceNavigator {
  static void Function(String screen)? open;
}
