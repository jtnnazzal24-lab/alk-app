import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/services/voice_service.dart';

void main() {
  group('VoiceService natural pacing', () {
    test('adds Arabic pronunciation hints without changing other languages',
        () {
      final arabic = VoiceService.pronunciationText(
        'مرحبًا، حان موعد دوائك. خذ الدواء؟',
        'ar-SA',
      );
      final english =
          VoiceService.pronunciationText('Hello, take it.', 'en-US');

      expect(arabic, contains('مَرْحَبًا'));
      expect(arabic, contains('دَوَائِكَ'));
      expect(english, 'Hello, take it.');
    });

    test('adds a longer pause after separators for important reminders', () {
      final result =
          VoiceService.naturalPaced('حان الوقت، خذ الدواء', slow: true);

      expect(result, 'حان الوقت،  خذ الدواء');
    });

    test('normalizes repeated whitespace and punctuation', () {
      expect(VoiceService.naturalPaced('  Hello...   take it  '),
          'Hello. take it');
    });

    test('maps language codes to valid speech locales', () {
      expect(VoiceService.speechLocaleFor('fr'), 'fr-FR');
      expect(VoiceService.speechLocaleFor('ja'), 'ja-JP');
      expect(VoiceService.speechLocaleFor('ko'), 'ko-KR');
      expect(VoiceService.speechLocaleFor('zh'), 'zh-CN');
    });
  });
}
