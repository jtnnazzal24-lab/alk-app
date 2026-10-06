import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/mood_wellbeing.dart';
import '../l10n/app_strings.dart';
import '../services/ai_fallback.dart';
import '../widgets/speak_button.dart';

/// زر مشترك: جلب شرح إضافي من الذكاء الآلي عند نقص المعلومات المحلية.
class AiHelp extends StatelessWidget {
  final String topic;
  final String lang;
  const AiHelp({super.key, required this.topic, required this.lang});

  Future<void> _fetch(BuildContext context) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final text = await AiFallback.fetch(topic: topic, languageTag: lang);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('شرح إضافي من الذكاء الآلي'.tr,
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                  if (text != null)
                    SpeakButton(text: text, languageTag: lang),
                ],
              ),
              const SizedBox(height: 8),
              Text(text ??
                  'الذكاء الآلي غير متاح حالياً. أضف مفتاح API من الإعدادات ثم أعد المحاولة. المعلومات المحلية أعلاه تكفي للاستخدام اليومي.'.tr),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: Text('معلومات غير كافية؟ اسأل الذكاء الآلي'.tr),
        subtitle: Text('يتطلب إضافة مفتاح API في الإعدادات'.tr),
        trailing: const Icon(Icons.arrow_forward),
        onTap: () => _fetch(context),
      ),
    );
  }
}

/// بطاقة التوصية حسب المزاج داخل شاشة العافية.
class MoodCard extends StatelessWidget {
  final String mood;
  const MoodCard({super.key, required this.mood});

  Future<void> _open(String q) async {
    final uri = Uri.parse(
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final rec = wellbeingForMood(mood);
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('حالتك: $mood'.tr,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(rec.exerciseTitle.tr,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(rec.exerciseSteps.tr),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text('🎵 ${rec.musicTitle}'.tr,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(rec.musicReason.tr),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note),
              title: Text('شغّل الموسيقى (يوتيوب)'.tr),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _open(rec.musicQuery),
            ),
            const SizedBox(height: 4),
            Text(rec.tip.tr),
          ],
        ),
      ),
    );
  }
}
