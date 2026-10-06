import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/mood_wellbeing.dart';
import '../l10n/app_strings.dart';
import '../state/sandy_store.dart';
import '../widgets/ai_mood_widgets.dart';
import '../widgets/mood_link.dart';
import '../widgets/speak_button.dart';
import 'wellbeing_screen.dart';

/// Journals tab - daily mood and note entries.
class JournalsScreen extends StatefulWidget {
  const JournalsScreen({super.key});

  @override
  State<JournalsScreen> createState() => _JournalsScreenState();
}

class _JournalsScreenState extends State<JournalsScreen> {
  String _mood = 'مرتاح'.tr;
  final _noteController = TextEditingController();

  final _moods = ['مرتاح'.tr, 'هادئ'.tr, 'متعب'.tr, 'حزين'.tr];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<SandyStore>();
    // الملاحظة اختيارية — يكفي اختيار المزاج لعرض اقتراح العافية.
    await store.addJournal(_mood, _noteController.text.trim());
    _noteController.clear();
    if (!mounted) return;
    // بعد حفظ الحالة النفسية: اعرض التمارين/الموسيقى المناسبة فوراً.
    _showMoodCare(_mood);
  }

  void _showMoodCare(String mood) {
    final rec = wellbeingForMood(mood);
    final lang = context.read<SandyStore>().languageTag;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
                    child: Text('حالتك: $mood — هذا ما يناسبك'.tr,
                        style: Theme.of(ctx).textTheme.titleMedium),
                  ),
                  SpeakButton(
                      text: 'حالتك $mood. أنصحك بـ ${rec.exerciseTitle}. ${rec.exerciseSteps}. ${rec.tip}'.tr,
                      languageTag: lang),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.fitness_center),
                  title: Text(rec.exerciseTitle.tr),
                  subtitle: Text(rec.exerciseSteps.tr),
                ),
              ),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🎵 ${rec.musicTitle}'.tr,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(rec.musicReason.tr),
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.music_note),
                      title: Text('شغّل الموسيقى (يوتيوب)'.tr),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _openQuery(rec.musicQuery),
                    ),
                  ],
                ),
              ),
              Text(rec.tip.tr),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => WellbeingScreen(mood: mood)));
                      },
                      icon: const Icon(Icons.spa),
                      label: Text('افتح العافية والحركة'.tr),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AiHelp(topic: 'الحالة النفسية: $mood'.tr, lang: lang),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openQuery(String q) async {
    final uri = Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<SandyStore>();
    final theme = Theme.of(context);
    final journals = store.journals;

    return Scaffold(
      appBar: AppBar(title: Text('يومياتي'.tr)),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('كيف كان يومك؟'.tr, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: _moods
                        .map((m) => ChoiceChip(
                              label: Text(m.tr),
                              selected: _mood == m,
                              onSelected: (_) => setState(() => _mood = m),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      labelText: 'اكتب ملاحظة بسيطة عن يومك...'.tr,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: Text('حفظ في يومياتي'.tr),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: journals.isEmpty
                ? Center(child: Text('ابدأ أول ملاحظة'.tr))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: journals.length,
                    itemBuilder: (context, index) {
                      final j = journals[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(j.mood.tr,
                                      style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold)),
                                  Text(j.createdAt,
                                      style: theme.textTheme.bodySmall),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(j.note.tr),
                              const SizedBox(height: 8),
                              MoodLink(mood: j.mood, lang: store.languageTag),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
