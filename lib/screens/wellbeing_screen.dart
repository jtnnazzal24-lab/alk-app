import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/mood_wellbeing.dart';
import '../l10n/app_strings.dart';
import '../state/sandy_store.dart';
import '../theme/alk_theme.dart';
import '../widgets/ai_mood_widgets.dart';
import '../logic/fat_exercise_advice.dart';
import '../widgets/speak_button.dart';

/// Wellbeing screen — breathing exercise, calming tips and music links.
/// Port of the RN app's `wellbeing.tsx` (offline variant).
class WellbeingScreen extends StatefulWidget {
  final String? mood;
  const WellbeingScreen({super.key, this.mood});

  @override
  State<WellbeingScreen> createState() => _WellbeingScreenState();
}

class _WellbeingScreenState extends State<WellbeingScreen> {
  int _breathePhase = 0; // 0 inhale, 1 hold, 2 exhale
  int _cycles = 0;
  bool _running = false;

  static const _phases = ['شهيق', 'احتفظ', 'زفير'];
  static const _durations = [Duration(seconds: 4), Duration(seconds: 4),
      Duration(seconds: 6)];

  Future<void> _tick() async {
    while (_running) {
      await Future<void>.delayed(_durations[_breathePhase]);
      if (!_running) return;
      if (!mounted) return;
      setState(() {
        _breathePhase = (_breathePhase + 1) % 3;
        if (_breathePhase == 0) _cycles++;
      });
    }
  }

  void _toggle() {
    setState(() => _running = !_running);
    if (_running) _tick();
  }

  Future<void> _openMusic() async {
    final store = context.read<SandyStore>();
    final mood = widget.mood?.isNotEmpty == true
        ? widget.mood!
        : (store.lastMood.isNotEmpty ? store.lastMood : null);
    final q = mood == null
        ? 'calming+relaxation+music'
        : Uri.encodeComponent(wellbeingForMood(mood).musicQuery);
    final uri = Uri.parse('https://www.youtube.com/results?search_query=$q');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الرابط'.tr)),
        );
      }
    }
  }

  @override
  void dispose() {
    _running = false;
    super.dispose();
  }

  /// بطاقة توازن الدهون اليومي: تجمّع دهون وجبات اليوم وتقترح تمارين تعويضية
  /// مناسبة للمرض المزمن (تُبنى من قائمة التغذية تلقائياً).
  Widget _buildFatBalance(SandyStore store, ThemeData theme) {
    final advice = adviceForDay(data: store.data);
    if (advice.level == FatAdviceLevel.none) {
      return const SizedBox.shrink();
    }
    Color c;
    switch (advice.level) {
      case FatAdviceLevel.over:
        c = Colors.red;
        break;
      case FatAdviceLevel.warn:
        c = Colors.orange;
        break;
      default:
        c = Colors.green;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('توازن الدهون اليومي'.tr,
                      style: theme.textTheme.titleMedium),
                ),
                SpeakButton(
                  text:
                      'توازن الدهون. ${adviceSummaryText(advice)}. ${advice.conditionAdvice}'.tr,
                  languageTag: store.languageTag,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                FatAdviceLevel.label(advice.level).tr,
                style: TextStyle(color: c, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Text(adviceSummaryText(advice).tr,
                style: theme.textTheme.bodySmall),
            if (advice.suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('تمارين تعويضية مقترحة:'.tr,
                  style: theme.textTheme.bodySmall),
              for (final s in advice.suggestions)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_walk, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${s.exercise} — ${s.minutes.toStringAsFixed(0)} دقيقة'.tr,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(advice.conditionAdvice.tr,
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<SandyStore>();
    // أولوية للمزاج المُمرَّر، ثم آخر مزاج سُجّل في اليوميات.
    final effectiveMood = widget.mood?.isNotEmpty == true
        ? widget.mood!
        : (store.lastMood.isNotEmpty ? store.lastMood : null);
    return Scaffold(
      appBar: AppBar(title: Text('العافية والحركة'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (effectiveMood != null)
            MoodCard(mood: effectiveMood),
          _buildFatBalance(store, theme),
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('تمرين التنفس'.tr,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
                  const SizedBox(height: 20),
                  AnimatedContainer(
                    duration: _durations[_breathePhase],
                    width: _breathePhase == 0 ? 160 : 100,
                    height: _breathePhase == 0 ? 160 : 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary
                          .withValues(alpha: 0.25),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _running ? _phases[_breathePhase].tr : 'ابدأ'.tr,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('الدورات المكتملة: $_cycles'.tr),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _toggle,
                    icon: Icon(_running ? Icons.stop : Icons.play_arrow),
                    label: Text(_running ? 'إيقاف'.tr : 'ابدأ التمرين'.tr),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: Text('موسيقى هادئة للاسترخاء'.tr),
              subtitle: Text('فتح قائمة تشغيل خارجية'.tr),
              trailing: const Icon(Icons.open_in_new),
              onTap: _openMusic,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('نصائح يومية'.tr,
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('• اشرب كمية كافية من الماء.'.tr),
                  Text('• تحرك كل ساعة ولو لدقائق قليلة.'.tr),
                  Text('• نظّم أدويتك في أوقات ثابتة.'.tr),
                  Text('• خذ قسطًا من النوم الكافي.'.tr),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            // بطاقة إرشادية: الخلفية تتبع سطوع الثيم (تظهر كمربع أبيض فارغ
            // في الوضع الداكن لو بقيت فاتحة ثابتة).
            color: AlkPalette.of(context).goldSoft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'هذه التمارين عامة ولا تُغني عن استشارة طبيبك.'.tr,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
