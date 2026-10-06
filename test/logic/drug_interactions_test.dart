import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/logic/drug_interactions.dart';
import 'package:alk_flutter/models/sandy_data.dart';

Medication _med(String name, {String category = MedicationCategory.general}) {
  return Medication(
    id: 'm-${name.hashCode}',
    name: name,
    time: '08:00',
    category: category,
    taken: false,
    updatedAt: '2026-10-04T08:00:00.000',
    reminderEnabled: false,
  );
}

bool _has(List<DrugInteraction> list, String title) =>
    list.any((e) => e.title == title);

void main() {
  group('قاعدة التفاعلات — دواء مع دواء', () {
    test('وارفارين + أسبرين = خطورة مرتفعة', () {
      final out = findDrugInteractions(medications: [
        _med('وارفارين 5'),
        _med('أسبرين 100'),
      ]);
      expect(_has(out, 'الأسبرين مع الوارفارين'), isTrue);
      expect(out.first.severity, InteractionSeverity.high);
    });

    test('إيبوبروفين مع لوسارتان يُصنَّف كتفاعل دواء–دواء', () {
      final out = findDrugInteractions(medications: [
        _med('لوسارتان 50'),
        _med('إيبوبروفين 400'),
      ]);
      expect(_has(out, 'دواء الضغط مع مسكن الالتهاب'), isTrue);
    });

    test('ليفوثيروكسين + حديد يحتاج فصلاً بـ4 ساعات', () {
      final out = findDrugInteractions(medications: [
        _med('ليفوثيروكسين 50'),
        _med('فروسلفات'),
      ]);
      expect(_has(out, 'الليفوثيروكسين مع مكملات الحديد'), isTrue);
    });

    test('دواء واحد بلا تفاعلات دوائية لا يولّد إنذاراً زائفاً', () {
      final out = findDrugInteractions(medications: [_med('أوميبرازول 20')]);
      expect(out.where((e) => e.kind == InteractionKind.drugDrug), isEmpty);
      // يبقى تنبيه التوقيت فقط.
      expect(_has(out, 'مانح حمض قبل الأكل'), isTrue);
    });
  });

  group('قاعدة التفاعلات — دواء مع طعام', () {
    final levo = [_med('ليفوثيروكسين 50')];

    test('الحليب يفعّل تنبيه الليفوثيروكسين', () {
      final out =
          findDrugInteractions(medications: levo, foods: ['حليب كامل الدسم']);
      expect(_has(out, 'الألبان مع الليفوثيروكسين'), isTrue);
    });

    test('بدون وجبات لا يظهر تنبيه غذائي', () {
      final out = findDrugInteractions(medications: levo, foods: []);
      expect(out.where((e) => e.kind == InteractionKind.drugFood), isEmpty);
    });

    test('السبانخ تفعّل تنبيه الوارفارين', () {
      final out = findDrugInteractions(
        medications: [_med('وارفارين 5')],
        foods: ['سلطة سبانخ'],
      );
      expect(_has(out, 'الخضار الورقية مع الوارفارين'), isTrue);
    });

    test('جريب فروت مع أتورفاستاتين', () {
      final out = findDrugInteractions(
        medications: [_med('أتورفاستاتين 20')],
        foods: ['عصير جريب فروت'],
      );
      expect(_has(out, 'جريب فروت مع مثبّتات الكوليسترول'), isTrue);
    });
  });

  group('قاعدة التفاعلات — دواء مع الحالة المرضية', () {
    test('إيبوبروفين لمريض الضغط', () {
      final out = findDrugInteractions(
        medications: [_med('إيبوبروفين 400')],
        condition: 'ارتفاع ضغط الدم',
      );
      expect(_has(out, 'مسكن الالتهاب مع الضغط'), isTrue);
    });

    test('كورتيزون لمريض السكري', () {
      final out = findDrugInteractions(
        medications: [_med('بريدنيزولون 5')],
        condition: 'سكري نوع 2',
      );
      expect(_has(out, 'الكورتيزون مع السكري'), isTrue);
    });

    test('حالة عامة لا تُفعّل قواعد الحالة', () {
      final out = findDrugInteractions(
        medications: [_med('إيبوبروفين 400')],
        condition: 'صداع',
      );
      expect(out.where((e) => e.kind == InteractionKind.drugCondition), isEmpty);
    });
  });

  group('ترتيب النتائج', () {
    test('الخطورة الأعلى أولاً ودون تكرار', () {
      final out = findDrugInteractions(medications: [
        _med('وارفارين 5'),
        _med('أسبرين 100'),
        _med('إيبوبروفين 400'),
      ]);
      expect(out.length, greaterThan(1));
      final severities = out.map((e) => e.severity).toList();
      expect(severities.first, InteractionSeverity.high);
      final titles = out.map((e) => e.title).toSet();
      expect(titles.length, out.length);
    });

    test('قائمة فارغة عند غياب الأدوية', () {
      expect(findDrugInteractions(medications: []), isEmpty);
    });
  });
}
