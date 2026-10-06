import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:alk_flutter/services/notification_service.dart';
import 'package:alk_flutter/services/reminder_content.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('localizedPreDoseReminderMessage', () {
    test('Arabic mentions the medication and the minutes left', () {
      final message = localizedPreDoseReminderMessage(
        medicationId: 'med-1',
        medicationName: 'ميتفورمين',
        language: 'ar',
        minutes: 15,
      );
      expect(message.title, contains('اقترب موعد'));
      expect(message.body, contains('ميتفورمين'));
      expect(message.body, contains('15'));
      expect(message.spokenText, message.body);
      expect(message.languageTag, 'ar-SA');
    });

    test('English and Chinese are supported', () {
      final en = localizedPreDoseReminderMessage(
        medicationId: 'med-1',
        medicationName: 'Metformin',
        language: 'en',
        minutes: 20,
      );
      expect(en.title, 'Dose time is near');
      expect(en.body, contains('20'));
      expect(en.body, contains('Metformin'));
      expect(en.languageTag, 'en-US');

      final zh = localizedPreDoseReminderMessage(
        medicationId: 'med-1',
        medicationName: '二甲双胍',
        language: 'zh',
        minutes: 30,
      );
      expect(zh.body, contains('30'));
      expect(zh.body, contains('二甲双胍'));
      expect(zh.languageTag, 'zh-CN');
    });

    test('unknown language falls back to English (never Arabic)', () {
      final message = localizedPreDoseReminderMessage(
        medicationId: 'med-1',
        medicationName: 'Aspirin',
        language: 'de',
        minutes: 15,
      );
      expect(message.languageTag, 'en-US');
      expect(message.body, contains('Aspirin'));
    });

    test('the variant (wording) is deterministic per medication id', () {
      final first = localizedPreDoseReminderMessage(
        medicationId: 'med-1',
        medicationName: 'دواء',
        language: 'ar',
        minutes: 15,
      );
      final second = localizedPreDoseReminderMessage(
        medicationId: 'med-1',
        medicationName: 'دواء',
        language: 'ar',
        minutes: 15,
      );
      expect(first.variant, reminderVariant('med-1'));
      expect(first.body, second.body);
    });
  });

  group('NotificationService.nextPreDoseOccurrence', () {
    test('uses today when the head-up time has not passed', () {
      final now = tz.TZDateTime(tz.UTC, 2026, 9, 22, 7, 50);
      final occurrence = NotificationService.nextPreDoseOccurrence(
        now: now,
        hour: 8,
        minute: 0,
        leadMinutes: 15,
      );
      expect(occurrence, tz.TZDateTime(tz.UTC, 2026, 9, 22, 7, 45));
    });

    test('rolls to tomorrow once the head-up time passed', () {
      final now = tz.TZDateTime(tz.UTC, 2026, 9, 22, 8, 30);
      final occurrence = NotificationService.nextPreDoseOccurrence(
        now: now,
        hour: 8,
        minute: 0,
        leadMinutes: 15,
      );
      expect(occurrence, tz.TZDateTime(tz.UTC, 2026, 9, 23, 7, 45));
    });

    test('handles a dose just after midnight (heads-up on the previous day)',
        () {
      // جرعة 00:10 وتذكير قبلها 15 دقيقة ⇒ 23:55 من اليوم السابق.
      final now = tz.TZDateTime(tz.UTC, 2026, 9, 22, 22, 0);
      final occurrence = NotificationService.nextPreDoseOccurrence(
        now: now,
        hour: 0,
        minute: 10,
        leadMinutes: 15,
      );
      expect(occurrence, tz.TZDateTime(tz.UTC, 2026, 9, 22, 23, 55));
    });

    test('the default lead is 15 minutes', () {
      expect(NotificationService.preDoseLeadMinutes, 15);
    });
  });

  group('ReminderTapPayload.parse', () {
    test('parses a dose notification payload', () {
      final payload = ReminderTapPayload.parse('med-1|باراسيتامول|ar-SA|2');
      expect(payload, isNotNull);
      expect(payload!.isPreDose, isFalse);
      expect(payload.medicationId, 'med-1');
      expect(payload.medicationName, 'باراسيتامول');
      expect(payload.languageTag, 'ar-SA');
      expect(payload.variant, 2);
    });

    test('parses a pre-dose notification payload', () {
      final payload =
          ReminderTapPayload.parse('predose|med-2|ميتفورمين|ar-SA|1');
      expect(payload, isNotNull);
      expect(payload!.isPreDose, isTrue);
      expect(payload.medicationId, 'med-2');
      expect(payload.medicationName, 'ميتفورمين');
      expect(payload.variant, 1);
    });

    test('rejects empty or incomplete payloads', () {
      expect(ReminderTapPayload.parse(null), isNull);
      expect(ReminderTapPayload.parse(''), isNull);
      expect(ReminderTapPayload.parse('med-1|name'), isNull);
      expect(ReminderTapPayload.parse('med-1||ar-SA|0'), isNull);
    });
  });
}
