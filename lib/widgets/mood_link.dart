import 'package:flutter/material.dart';

import '../logic/mood_wellbeing.dart';
import '../l10n/app_strings.dart';
import '../screens/wellbeing_screen.dart';
import 'speak_button.dart';

/// رابط صغير أسفل كل يومية: يفتح العافية المناسبة للمزاج.
class MoodLink extends StatelessWidget {
  final String mood;
  final String lang;
  const MoodLink({super.key, required this.mood, required this.lang});

  @override
  Widget build(BuildContext context) {
    final rec = wellbeingForMood(mood);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => WellbeingScreen(mood: mood))),
            icon: const Icon(Icons.spa, size: 18),
            label: Text('يناسبك: ${rec.exerciseTitle}'.tr,
                style: const TextStyle(fontSize: 12)),
          ),
        ),
        SpeakButton(
            text: 'حالتك $mood. ${rec.exerciseTitle}. ${rec.tip}'.tr,
            languageTag: lang,
            iconSize: 20),
      ],
    );
  }
}
