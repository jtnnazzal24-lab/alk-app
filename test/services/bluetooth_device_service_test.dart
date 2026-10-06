import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/services/bluetooth_device_service.dart';

void main() {
  group('decodeSfloat (IEEE-11073 16-bit)', () {
    test('decodes positive integers', () {
      expect(decodeSfloat(0x0078), 120); // 120 أ— 10^0
      expect(decodeSfloat(0x0048), 72);
    });

    test('decodes negative exponents', () {
      // 160 أ— 10^-1 = 16.0 (kPa encoding of 120 mmHg).
      expect(decodeSfloat(0xF0A0), closeTo(16.0, 0.0001));
      // 5 أ— 10^-3 = 0.005 kg/L (glucose â‰ˆ 500 mg/dL).
      expect(decodeSfloat(0xD005), closeTo(0.005, 0.000001));
    });

    test('decodes negative mantissas', () {
      // mantissa -10, exponent 0 â†’ -10.
      expect(decodeSfloat(0x0FF6), -10);
    });

    test('returns null for the reserved values', () {
      expect(decodeSfloat(0x07FF), isNull); // NaN
      expect(decodeSfloat(0x0800), isNull); // NRes
      expect(decodeSfloat(0x07FE), isNull); // +Inf
      expect(decodeSfloat(0x0802), isNull); // -Inf
    });
  });

  group('parseBloodPressureMeasurement (0x2A35)', () {
    test('parses a mmHg frame', () {
      // flags=0 (mmHg, no timestamp, no pulse), sys=120, dia=80, map=93.
      final bp = parseBloodPressureMeasurement(
          [0x00, 0x78, 0x00, 0x50, 0x00, 0x5D, 0x00]);
      expect(bp, isNotNull);
      expect(bp!.systolicMmHg, 120);
      expect(bp.diastolicMmHg, 80);
      expect(bp.pulseBpm, isNull);
    });

    test('parses the optional pulse rate', () {
      // flags=0x04 (pulse present), sys=120, dia=80, map=93, pulse=76.
      final bp = parseBloodPressureMeasurement(
          [0x04, 0x78, 0x00, 0x50, 0x00, 0x5D, 0x00, 0x4C, 0x00]);
      expect(bp!.pulseBpm, 76);
    });

    test('converts kPa frames to mmHg', () {
      // flags=0x01 (kPa), sys=16.0 kPa (0xF0A0), dia=10.7 kPa (0xF06B).
      final bp = parseBloodPressureMeasurement(
          [0x01, 0xA0, 0xF0, 0x6B, 0xF0, 0x00, 0x00]);
      expect(bp, isNotNull);
      expect(bp!.systolicMmHg, closeTo(120, 1));
      expect(bp.diastolicMmHg, closeTo(80, 2));
    });

    test('returns null for truncated frames', () {
      expect(parseBloodPressureMeasurement([0x00, 0x78, 0x00]), isNull);
    });
  });

  group('parseGlucoseMeasurement (0x2A18)', () {
    test('normalizes a kg/L concentration to mg/dL', () {
      // flags=0 (kg/L), seq=1, base time 2024-09-15 10:30:00, conc=0.005 kg/L.
      final data = [
        0x00,
        0x01, 0x00, // sequence
        0xE8, 0x07, // year 2024
        0x09, 0x0F, 0x0A, 0x1E, 0x00, // month day hour min sec
        0x05, 0xD0, // concentration 0.005 kg/L
      ];
      final glucose = parseGlucoseMeasurement(data);
      expect(glucose, isNotNull);
      expect(glucose!.mgDl, 500);
    });

    test('returns null for a reserved concentration', () {
      final data = [
        0x00,
        0x01, 0x00,
        0xE8, 0x07, 0x09, 0x0F, 0x0A, 0x1E, 0x00,
        0xFF, 0x07, // NaN sfloat
      ];
      expect(parseGlucoseMeasurement(data), isNull);
    });
  });

  group('parseHeartRateMeasurement (0x2A37)', () {
    test('parses 8-bit heart rate', () {
      expect(parseHeartRateMeasurement([0x00, 72])!.bpm, 72);
    });

    test('parses 16-bit heart rate', () {
      expect(parseHeartRateMeasurement([0x01, 72, 0x00])!.bpm, 72);
    });

    test('returns null for zero bpm', () {
      expect(parseHeartRateMeasurement([0x00, 0]), isNull);
    });
  });

  group('parsePlxSpotCheck (0x2A5E)', () {
    test('parses SpO2 and pulse rate', () {
      // flags=0, SpO2=97%, pulse=72 bpm.
      final plx =
          parsePlxSpotCheck([0x00, 0x61, 0x00, 0x48, 0x00]);
      expect(plx, isNotNull);
      expect(plx!.spo2Percent, 97);
      expect(plx.pulseBpm, 72);
    });

    test('returns null for truncated frames', () {
      expect(parsePlxSpotCheck([0x00, 0x61]), isNull);
    });
  });
}
