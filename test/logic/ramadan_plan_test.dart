import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/logic/ramadan_plan.dart';
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

bool _has(List<RamadanTip> tips, String title) =>
    tips.any((t) => t.title == title);

void main() {
  group('خطة رمضان', () {
    test('أنسولين يرفع خطر الهبوط قبل الإفطار (خطورة عالية)', () {
      final tips = buildRamadanPlan(medications: [_med('لانتوس 100')]);
      expect(_has(tips, 'خطر هبوط السكر قبل الإفطار'), isTrue);
      expect(tips.first.severity, 'high');
    });

    test('أدوية السكري الفموية تُدرج في خطر الهبوط', () {
      final tips = buildRamadanPlan(medications: [_med('جليمبيز 5')]);
      expect(_has(tips, 'خطر هبوط السكر قبل الإفطار'), isTrue);
    });

    test('الليفوثيروكسين يُنصح بتوقيت السحور', () {
      final tips = buildRamadanPlan(medications: [_med('ليفوثيروكسين 50')]);
      expect(_has(tips, 'الليفوثيروكسين في السحور'), isTrue);
    });

    test('الميتفورمين يُنصح بتناوله مع الوجبة', () {
      final tips = buildRamadanPlan(medications: [_med('ميتفورمين 500')]);
      expect(_has(tips, 'الميتفورمين مع وجبة'), isTrue);
    });

    test('أدوية الضغط تُضيف نصيحة الجفاف', () {
      final tips = buildRamadanPlan(
        medications: [_med('لوسارتان 50', category: MedicationCategory.pressure)],
      );
      expect(_has(tips, 'أدوية الضغط والجفاف'), isTrue);
    });

    test('نصائح عامة دائماً + عرض الوقتين', () {
      final tips = buildRamadanPlan(
        medications: [],
        suhoorTime: '04:30',
        iftarTime: '18:15',
      );
      expect(_has(tips, 'نافذة الإفطار الآمنة'), isTrue);
      final window = tips.firstWhere((t) => t.title == 'نافذة الإفطار الآمنة');
      expect(window.detail, contains('04:30'));
      expect(window.detail, contains('18:15'));
    });

    test('لا يُصدر خطر هبوط لدواء عادي', () {
      final tips = buildRamadanPlan(medications: [_med('شراب كالسيوم')]);
      expect(_has(tips, 'خطر هبوط السكر قبل الإفطار'), isFalse);
    });

    test('الترتيب من الأعلى خطورة', () {
      final tips = buildRamadanPlan(medications: [
        _med('لانتوس 100'),
        _med('ميتفورمين 500'),
      ]);
      final ranks = tips
          .map((t) => t.severity == 'high'
              ? 0
              : (t.severity == 'medium' ? 1 : 2))
          .toList();
      final sorted = [...ranks]..sort();
      expect(ranks, sorted);
    });
  });
}
