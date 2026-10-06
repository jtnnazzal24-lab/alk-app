import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/logic/medication_times.dart';
import 'package:alk_flutter/models/sandy_data.dart';

Medication _med({
  required String id,
  required String name,
  String time = '08:00',
  List<String> doseTimes = const [],
  bool reminderEnabled = true,
  bool asNeeded = false,
}) {
  return Medication(
    id: id,
    name: name,
    time: time,
    doseTimes: doseTimes,
    category: MedicationCategory.general,
    taken: false,
    updatedAt: '2026-09-22T08:00:00.000',
    reminderEnabled: reminderEnabled,
    asNeeded: asNeeded,
  );
}

void main() {
  group('nextDoseOccurrence', () {
    final now = DateTime(2026, 9, 22, 12, 0);

    test('returns null when there are no reminder medications', () {
      expect(nextDoseOccurrence(const [], now), isNull);
      expect(
        nextDoseOccurrence(
            [_med(id: 'm1', name: 'أ', reminderEnabled: false)], now),
        isNull,
      );
      expect(
        nextDoseOccurrence([_med(id: 'm2', name: 'ب', asNeeded: true)], now),
        isNull,
      );
    });

    test('picks the nearest upcoming dose among all times', () {
      final result = nextDoseOccurrence([
        _med(id: 'm1', name: 'صباحي', doseTimes: ['08:00']),
        _med(id: 'm2', name: 'مسائي', doseTimes: ['14:00', '20:00']),
      ], now);
      expect(result, isNotNull);
      expect(result!.medication.name, 'مسائي');
      expect(result.at, DateTime(2026, 9, 22, 14, 0));
    });

    test('rolls to tomorrow when every dose time has passed', () {
      final result = nextDoseOccurrence([_med(id: 'm1', name: 'صباحي')], now);
      // 08:00 مضى ظهراً ⇒ غداً 08:00.
      expect(result!.at, DateTime(2026, 9, 23, 8, 0));
    });

    test('falls back to the primary time when doseTimes is empty', () {
      final result = nextDoseOccurrence(
          [_med(id: 'm1', name: 'دواء', time: '18:30')], now);
      expect(result!.at, DateTime(2026, 9, 22, 18, 30));
    });

    test('ignores invalid times instead of throwing', () {
      final result = nextDoseOccurrence(
          [_med(id: 'm1', name: 'دواء', time: '8:0')], now);
      expect(result, isNull);
    });
  });
}
