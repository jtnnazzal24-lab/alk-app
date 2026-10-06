import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/logic/food_advice.dart';
import 'package:alk_flutter/logic/vital_advice.dart';
import 'package:alk_flutter/models/sandy_data.dart';

void main() {
  group('adviseVital — ضغط الدم', () {
    test('118/78 طبيعي', () {
      final a = adviseVital(kind: VitalKind.pressure, value: '118/78');
      expect(a.level, VitalLevel.normal);
      expect(a.needsDoctor, isFalse);
      expect(a.emergency, isFalse);
    });

    test('128/82 حدي (تحتاج انتباهاً) وليس طبيعاً', () {
      final a = adviseVital(kind: VitalKind.pressure, value: '128/82');
      expect(a.level, VitalLevel.borderline);
      expect(a.needsDoctor, isFalse);
      expect(a.impactKind, FoodImpactKind.pressure);
    });

    test('150/95 غير مقبول ويطلب زيارة الطبيب مع تمارين وأغذية', () {
      final a = adviseVital(kind: VitalKind.pressure, value: '150/95');
      expect(a.level, VitalLevel.abnormal);
      expect(a.needsDoctor, isTrue);
      expect(a.emergency, isFalse);
      expect(a.exercises, isNotEmpty);
      expect(a.foods, isNotEmpty);
    });

    test('الحدي العالي وحده يكفي للتصنيف (135/92)', () {
      final a = adviseVital(kind: VitalKind.pressure, value: '135/92');
      expect(a.level, VitalLevel.abnormal);
    });

    test('190/125 خطر عاجل يتطلب الإسعاف', () {
      final a = adviseVital(kind: VitalKind.pressure, value: '190/125');
      expect(a.level, VitalLevel.emergency);
      expect(a.emergency, isTrue);
      expect(a.needsDoctor, isTrue);
      expect(a.spokenText, contains('الإسعاف'));
    });

    test('85/55 ضغط منخفض غير مقبول ودون رياضة', () {
      final a = adviseVital(kind: VitalKind.pressure, value: '85/55');
      expect(a.level, VitalLevel.abnormal);
      expect(a.needsDoctor, isTrue);
      expect(a.exercises, isEmpty, reason: 'مع الضغط المنخفض: راحة أولاً');
    });

    test('قراءة ناقصة الرقمين غير مفهومة', () {
      final a = adviseVital(kind: VitalKind.pressure, value: '150');
      expect(a.level, VitalLevel.unknown);
      expect(a.needsDoctor, isFalse);
    });
  });

  group('adviseVital — سكر الدم', () {
    test('95 صائم طبيعي', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '95 صائم');
      expect(a.level, VitalLevel.normal);
      expect(a.impactKind, FoodImpactKind.sugar);
    });

    test('110 صائم حدي (بين 100 و125)', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '110 صائم');
      expect(a.level, VitalLevel.borderline);
    });

    test('130 صائم غير مقبول (≥126)', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '130 صائم');
      expect(a.level, VitalLevel.abnormal);
      expect(a.needsDoctor, isTrue);
    });

    test('160 عشوائي حدي بينما صائم يكون غير مقبول', () {
      final random = adviseVital(kind: VitalKind.sugar, value: '160');
      expect(random.level, VitalLevel.borderline);

      final fasting = adviseVital(kind: VitalKind.sugar, value: '160 صائم');
      expect(fasting.level, VitalLevel.abnormal,
          reason: 'عتبة الصائم 126 وليست 140');
    });

    test('200 بعد الأكل غير مقبول مع تمارين وأغذية', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '200 بعد الأكل');
      expect(a.level, VitalLevel.abnormal);
      expect(a.needsDoctor, isTrue);
      expect(a.exercises, isNotEmpty);
      expect(a.foods, isNotEmpty);
    });

    test('260 خطر عاجل (≥250) دون رياضة', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '260');
      expect(a.level, VitalLevel.emergency);
      expect(a.emergency, isTrue);
      expect(a.exercises, isEmpty, reason: 'لا رياضة في الخطر');
    });

    test('65 هبوط غير مقبول مع إرشاد سكر سريع ودون رياضة', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '65');
      expect(a.level, VitalLevel.abnormal);
      expect(a.exercises, isEmpty);
      expect(a.foods, isNotEmpty);
      expect(a.foods.first, contains('تمر'));
    });

    test('48 هبوط خطير (أقل من 54) = خطر عاجل', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '48');
      expect(a.level, VitalLevel.emergency);
      expect(a.emergency, isTrue);
    });

    test('يقبل الوحدات (105 mg/dL)', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '105 mg/dL');
      expect(a.level, VitalLevel.normal);
    });
  });

  group('adviseVital — الأكسجين', () {
    test('97 طبيعي', () {
      expect(adviseVital(kind: VitalKind.oxygen, value: '97%').level,
          VitalLevel.normal);
    });

    test('94 حدي', () {
      expect(adviseVital(kind: VitalKind.oxygen, value: '94%').level,
          VitalLevel.borderline);
    });

    test('91 غير مقبول ويطلب زيارة الطبيب', () {
      final a = adviseVital(kind: VitalKind.oxygen, value: '91%');
      expect(a.level, VitalLevel.abnormal);
      expect(a.needsDoctor, isTrue);
      expect(a.exercises, isNotEmpty);
    });

    test('88 خطر عاجل', () {
      final a = adviseVital(kind: VitalKind.oxygen, value: '88%');
      expect(a.level, VitalLevel.emergency);
      expect(a.emergency, isTrue);
    });
  });

  group('adviseVital — النبض', () {
    test('72 طبيعي ومرتبط بالقلب غذائياً', () {
      expect(adviseVital(kind: VitalKind.pulse, value: '72 bpm').level,
          VitalLevel.normal);
      expect(adviseVital(kind: VitalKind.pulse, value: '72 bpm').impactKind,
          FoodImpactKind.heart);
    });

    test('55 و105 حدي', () {
      expect(adviseVital(kind: VitalKind.pulse, value: '55').level,
          VitalLevel.borderline);
      expect(adviseVital(kind: VitalKind.pulse, value: '105').level,
          VitalLevel.borderline);
    });

    test('45 و120 غير مقبولين', () {
      expect(adviseVital(kind: VitalKind.pulse, value: '45').level,
          VitalLevel.abnormal);
      expect(adviseVital(kind: VitalKind.pulse, value: '120').level,
          VitalLevel.abnormal);
    });

    test('35 و145 خطر عاجل', () {
      expect(adviseVital(kind: VitalKind.pulse, value: '35').emergency, isTrue);
      expect(adviseVital(kind: VitalKind.pulse, value: '145').emergency, isTrue);
    });
  });

  group('adviseVital — حالات خاصة', () {
    test('نص غير رقمي = غير مفهوم ولا يُسقط التطبيق', () {
      final a = adviseVital(kind: VitalKind.sugar, value: '----');
      expect(a.level, VitalLevel.unknown);
      expect(a.message, isNotEmpty);
    });

    test('نوع غير معروف = غير مفهوم', () {
      final a = adviseVital(kind: 'weight', value: '80');
      expect(a.level, VitalLevel.unknown);
    });

    test('ملاحظة الحالة المزمنة تظهر فقط عند الشدة', () {
      final normal = adviseVital(
          kind: VitalKind.pressure, value: '118/78', conditionName: 'سكري');
      expect(normal.conditionNote, isEmpty);

      final sick =
          adviseVital(kind: VitalKind.sugar, value: '200', conditionName: 'سكري');
      expect(sick.conditionNote, isNotEmpty);
      expect(sick.conditionNote, contains('سكريك'));
    });

    test('SugarContext يبني اللافقة والاكتشاف الصحيحين', () {
      expect(SugarContext.suffix(SugarContext.fasting), ' صائم');
      expect(SugarContext.suffix(SugarContext.afterMeal), ' بعد الأكل');
      expect(SugarContext.suffix(SugarContext.random), isEmpty);
      expect(SugarContext.of('160 بعد الأكل'), SugarContext.afterMeal);
      expect(SugarContext.of('90 صائم'), SugarContext.fasting);
      expect(SugarContext.of('90'), SugarContext.random);
    });

    test('vitalKindLabel يسمّي الأنواع الأربعة', () {
      expect(vitalKindLabel(VitalKind.pressure), isNotEmpty);
      expect(vitalKindLabel(VitalKind.sugar), isNotEmpty);
      expect(vitalKindLabel(VitalKind.pulse), isNotEmpty);
      expect(vitalKindLabel(VitalKind.oxygen), isNotEmpty);
    });
  });

  group('latestVitalAdvices', () {
    test('يعيد أحدث قراءة من كل نوع بالترتيب المعروض', () {
      final vitals = [
        const VitalReading(
            id: 'p2',
            kind: VitalKind.pressure,
            value: '150/95',
            createdAt: '2026-09-27T10:00:00'),
        const VitalReading(
            id: 's1',
            kind: VitalKind.sugar,
            value: '95',
            createdAt: '2026-09-27T09:00:00'),
        const VitalReading(
            id: 'p1',
            kind: VitalKind.pressure,
            value: '118/78',
            createdAt: '2026-09-26T10:00:00'),
      ];
      final advices = latestVitalAdvices(vitals);
      expect(advices.length, 2);
      expect(advices.first.kind, VitalKind.pressure);
      expect(advices.first.value, '150/95',
          reason: 'الأحدث حسب createdAt وليس الأقدم');
      expect(advices.first.level, VitalLevel.abnormal);
      expect(advices[1].kind, VitalKind.sugar);
      expect(advices[1].level, VitalLevel.normal);
    });

    test('يتجاهل القيم الفارغة ويعيد فارغاً للقائمة الفارغة', () {
      expect(latestVitalAdvices(const []), isEmpty);
      final vitals = [
        const VitalReading(
            id: 'x',
            kind: VitalKind.sugar,
            value: '  ',
            createdAt: '2026-09-27T10:00:00'),
      ];
      expect(latestVitalAdvices(vitals), isEmpty);
    });
  });
}

