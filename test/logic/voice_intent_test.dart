import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/logic/voice_intent.dart';

void main() {
  group('parseVoiceIntent — vitals', () {
    test('sugar with Arabic-Indic digits', () {
      final intent = parseVoiceIntent('سجل سكر ١٤٠');
      expect(intent, isA<VoiceAddVital>());
      final vital = intent as VoiceAddVital;
      expect(vital.kind, 'sugar');
      expect(vital.value, '140');
    });

    test('pressure "120 على 80" becomes 120/80', () {
      final intent = parseVoiceIntent('ضغط 120 على 80');
      final vital = intent as VoiceAddVital;
      expect(vital.kind, 'pressure');
      expect(vital.value, '120/80');
    });

    test('pulse', () {
      final intent = parseVoiceIntent('نبضي 90');
      final vital = intent as VoiceAddVital;
      expect(vital.kind, 'pulse');
      expect(vital.value, '90');
    });

    test('glucose synonym', () {
      final intent = parseVoiceIntent('الغلوكوز 155');
      final vital = intent as VoiceAddVital;
      expect(vital.kind, 'sugar');
      expect(vital.value, '155');
    });
  });

  group('parseVoiceIntent — navigation', () {
    test('open vitals', () {
      expect(
        parseVoiceIntent('افتح القياسات'),
        isA<VoiceOpenScreen>().having((i) => i.screen, 'screen', 'vitals'),
      );
    });
    test('open medications', () {
      expect(
        parseVoiceIntent('اعرض أدويتي'),
        isA<VoiceOpenScreen>().having((i) => i.screen, 'screen', 'medications'),
      );
    });
    test('open nutrition', () {
      expect(
        parseVoiceIntent('فتح التغذية'),
        isA<VoiceOpenScreen>().having((i) => i.screen, 'screen', 'nutrition'),
      );
    });
  });

  test('food logging', () {
    final intent = parseVoiceIntent('أكلت تفاحة');
    expect(intent, isA<VoiceAddFood>());
    expect((intent as VoiceAddFood).name, contains('تفاحة'));
  });

  test('medication with spoken hour', () {
    final intent = parseVoiceIntent('أضف دواء أسبيرين الساعة 8');
    expect(intent, isA<VoiceAddMedication>());
    final med = intent as VoiceAddMedication;
    expect(med.name, 'أسبيرين');
    expect(med.time, '08:00');
  });

  test('greeting', () {
    expect(parseVoiceIntent('مرحبا'), isA<VoiceGreeting>());
  });

  test('unknown command keeps original text', () {
    final intent = parseVoiceIntent('اشترِ لي قهوة');
    expect(intent, isA<VoiceUnknown>());
    expect((intent as VoiceUnknown).text, 'اشترِ لي قهوة');
  });

  test('labels', () {
    expect(vitalLabel('sugar'), 'السكر');
    expect(screenLabel('vitals'), 'القياسات');
  });
}
