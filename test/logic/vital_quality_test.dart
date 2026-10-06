import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/logic/vital_quality.dart';
import 'package:alk_flutter/models/sandy_data.dart';

void main() {
  group('VitalQualityPolicy.primaryValue', () {
    test('extracts systolic from pressure strings', () {
      expect(VitalQualityPolicy.primaryValue(VitalKind.pressure, '120/80'),
          120);
    });

    test('extracts the number from unit strings', () {
      expect(VitalQualityPolicy.primaryValue(VitalKind.sugar, '105 mg/dL'),
          105);
      expect(
          VitalQualityPolicy.primaryValue(VitalKind.pulse, '72 bpm'), 72);
      expect(
          VitalQualityPolicy.primaryValue(VitalKind.oxygen, '97%'), 97);
    });
  });

  group('VitalQualityPolicy.assess — plausible readings', () {
    test('accepts a normal pressure reading', () {
      final a = VitalQualityPolicy.assess(
          kind: VitalKind.pressure, value: '120/80');
      expect(a, isNotNull);
      expect(a!.quality, VitalQuality.ok);
    });

    test('accepts a normal sugar reading', () {
      final a = VitalQualityPolicy.assess(
          kind: VitalKind.sugar, value: '105 mg/dL');
      expect(a!.quality, VitalQuality.ok);
    });

    test('accepts a normal SpO2 reading', () {
      final a =
          VitalQualityPolicy.assess(kind: VitalKind.oxygen, value: '97%');
      expect(a!.quality, VitalQuality.ok);
    });
  });

  group('VitalQualityPolicy.assess — implausible readings are rejected', () {
    test('rejects an impossible pressure', () {
      expect(
        VitalQualityPolicy.assess(
            kind: VitalKind.pressure, value: '300/150'),
        isNull,
      );
    });

    test('rejects diastolic ≥ systolic', () {
      expect(
        VitalQualityPolicy.assess(kind: VitalKind.pressure, value: '120/130'),
        isNull,
      );
    });

    test('rejects an impossible sugar and pulse', () {
      expect(
        VitalQualityPolicy.assess(kind: VitalKind.sugar, value: '1000 mg/dL'),
        isNull,
      );
      expect(
        VitalQualityPolicy.assess(kind: VitalKind.pulse, value: '25 bpm'),
        isNull,
      );
    });
  });

  group('VitalQualityPolicy.assess — error-margin warnings', () {
    test('flags readings near the physiological boundary', () {
      final a = VitalQualityPolicy.assess(
          kind: VitalKind.pressure, value: '255/140');
      expect(a, isNotNull);
      expect(a!.quality, VitalQuality.check);
      expect(a.note, isNotNull);
    });

    test('flags readings deviating far from the recent trend', () {
      final a = VitalQualityPolicy.assess(
        kind: VitalKind.sugar,
        value: '220 mg/dL',
        recentValues: [100, 105, 98],
      );
      expect(a!.quality, VitalQuality.check);
    });

    test('does not flag a reading consistent with the trend', () {
      final a = VitalQualityPolicy.assess(
        kind: VitalKind.sugar,
        value: '108 mg/dL',
        recentValues: [100, 105, 98],
      );
      expect(a!.quality, VitalQuality.ok);
    });
  });

  test('uncertainty notes exist for every vital kind', () {
    for (final kind in VitalKind.all) {
      expect(VitalQualityPolicy.uncertaintyNote(kind), isNotEmpty);
    }
  });
}