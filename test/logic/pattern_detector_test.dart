import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/logic/pattern_detector.dart';
import 'package:alk_flutter/models/sandy_data.dart';

VitalReading _v(String value, DateTime at, {String kind = VitalKind.pressure}) {
  return VitalReading(
    id: 'v-${at.microsecondsSinceEpoch}',
    kind: kind,
    value: value,
    createdAt: at.toIso8601String(),
  );
}

void main() {
  group('parseVitalNumber', () {
    test('يقرأ الضغط المزدوج ويعطي الانقباض', () {
      expect(parseVitalNumber('120/80'), 120);
    });

    test('يقرأ العدد العشري', () {
      expect(parseVitalNumber('98.5%'), 98.5);
    });

    test('يرجع null للنص الفارغ أو غير الرقمي', () {
      expect(parseVitalNumber(''), isNull);
      expect(parseVitalNumber('لا يوجد قياس'), isNull);
    });
  });

  group('trendPattern', () {
    test('يكشف اتجاهاً صاعداً في الضغط', () {
      final base = DateTime(2026, 9, 1, 8);
      final pts = <(double, DateTime)>[
        for (var i = 0; i < 6; i++) (110.0 + i * 6, base.add(Duration(days: i))),
      ];
      final p = trendPattern(VitalKind.pressure, pts);
      expect(p, isNotNull);
      expect(p!.kind, PatternKind.trend);
      expect(p.title, 'اتجاه ضغط الدم صاعد');
    });

    test('لا يُصدر تنبيهاً عند ثبات القراءات', () {
      final base = DateTime(2026, 9, 1, 8);
      final pts = <(double, DateTime)>[
        for (var i = 0; i < 6; i++) (120.0, base.add(Duration(days: i))),
      ];
      expect(trendPattern(VitalKind.pressure, pts), isNull);
    });

    test('يحتاج 5 قراءات على الأقل', () {
      final base = DateTime(2026, 9, 1, 8);
      final pts = <(double, DateTime)>[
        for (var i = 0; i < 4; i++) (110.0 + i * 10, base.add(Duration(days: i))),
      ];
      expect(trendPattern(VitalKind.pressure, pts), isNull);
    });
  });

  group('weekdayPatterns', () {
    test('يكشف أن قراءات الاثنين أعلى من بقية الأيام', () {
      final pts = <(double, DateTime)>[
        (150, DateTime(2026, 9, 7, 8)), // الاثنين
        (152, DateTime(2026, 9, 14, 8)), // الاثنين
        (120, DateTime(2026, 9, 8, 8)),
        (122, DateTime(2026, 9, 9, 8)),
        (119, DateTime(2026, 9, 10, 8)),
        (121, DateTime(2026, 9, 11, 8)),
      ];
      final out = weekdayPatterns(VitalKind.pressure, pts);
      expect(out, isNotEmpty);
      expect(out.first.title, 'ضغط الدم أعلى يوم الاثنين');
      expect(out.first.detail, contains('الاثنين'));
    });

    test('لا شيء عند تقارب متوسطات الأيام', () {
      final pts = <(double, DateTime)>[
        (120, DateTime(2026, 9, 7, 8)),
        (121, DateTime(2026, 9, 8, 8)),
        (119, DateTime(2026, 9, 9, 8)),
        (122, DateTime(2026, 9, 10, 8)),
        (120, DateTime(2026, 9, 11, 8)),
      ];
      expect(weekdayPatterns(VitalKind.pressure, pts), isEmpty);
    });
  });

  group('detectVitalPatterns', () {
    test('يجمع الاتجاه والانقطاع معاً', () {
      final base = DateTime(2026, 9, 1, 8);
      final readings = <VitalReading>[
        for (var i = 0; i < 6; i++)
          _v('${110 + i * 6}/70', base.add(Duration(days: i))),
      ];
      final out = detectVitalPatterns(
        readings,
        now: DateTime(2026, 9, 20, 9),
      );
      final kinds = out.map((e) => e.kind).toSet();
      expect(kinds, contains(PatternKind.trend));
      expect(kinds, contains(PatternKind.streak));
    });

    test('يرجع قائمة فارغة عند نقص القراءات', () {
      expect(
        detectVitalPatterns([
          _v('120/80', DateTime(2026, 9, 1)),
        ]),
        isEmpty,
      );
    });

    test('ينظّم النتائج من الأعلى أهمية', () {
      final base = DateTime(2026, 9, 1, 8);
      final readings = <VitalReading>[
        for (var i = 0; i < 6; i++)
          _v('${110 + i * 8}/70', base.add(Duration(days: i))),
      ];
      final out = detectVitalPatterns(readings, now: base);
      expect(out, isNotEmpty);
      final ranks = out
          .map((e) => PatternSeverity.rank(e.severity))
          .toList();
      final sorted = [...ranks]..sort();
      expect(ranks, sorted);
    });
  });
}
