import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/logic/care_alerts.dart';
import 'package:alk_flutter/models/sandy_data.dart';

Medication _med(
  String name, {
  num? stock,
  num? threshold,
  String? endDate,
}) {
  return Medication(
    id: 'm-${name.hashCode}',
    name: name,
    time: '08:00',
    category: MedicationCategory.general,
    taken: false,
    updatedAt: '2026-10-04T08:00:00.000',
    reminderEnabled: false,
    stockRemaining: stock,
    stockThreshold: threshold,
    endDate: endDate,
  );
}

void main() {
  group('تنبيهات المخزون', () {
    test('تحذير عند بلوغ حدّ التجديد', () {
      final out = stockAlerts([
        _med('ميتفورمين 500', stock: 4, threshold: 5),
      ]);
      expect(out.single.kind, CareAlertKind.stock);
      expect(out.single.severity, 'medium');
      expect(out.single.detail, contains('4'));
    });

    test('خطورة مرتفعة عند نفاد الدواء', () {
      final out = stockAlerts([_med('أنسولين', stock: 0, threshold: 5)]);
      expect(out.single.severity, 'high');
    });

    test('لا تنبيه بلا حقول مخزون', () {
      expect(stockAlerts([_med('أسبرين')]), isEmpty);
    });

    test('لا تنبيه فوق الحد', () {
      expect(
        stockAlerts([_med('أسبرين', stock: 30, threshold: 5)]),
        isEmpty,
      );
    });
  });

  group('تحذير انتهاء الصلاحية', () {
    final now = DateTime(2026, 10, 4);

    test('تحذير قبل 10 أيام من الانتهاء', () {
      final out = expiryAlerts(
        [_med('شراب', endDate: '2026-10-14')],
        now: now,
      );
      expect(out.single.kind, CareAlertKind.expiry);
      expect(out.single.detail, contains('10'));
    });

    test('خطورة مرتفعة بعد مرور تاريخ الانتهاء', () {
      final out = expiryAlerts(
        [_med('شراب', endDate: '2026-09-01')],
        now: now,
      );
      expect(out.single.severity, 'high');
    });

    test('بلا تاريخ انتهاء لا يوجد تنبيه', () {
      expect(expiryAlerts([_med('أسبرين')], now: now), isEmpty);
    });
  });

  group('الفحوصات الدورية', () {
    test('مريض السكري يحصل على HbA1c وفحص العين', () {
      final ids = standardCheckups('سكري نوع 2').map((e) => e.id).toList();
      expect(ids, contains('hba1c'));
      expect(ids, contains('eye-exam'));
      expect(ids, contains('flu-vaccine'));
    });

    test('بلا حالة مرضية يبقى تطعيم الإنفلونزا فقط', () {
      final items = standardCheckups('');
      expect(items.single.id, 'flu-vaccine');
    });

    test('فحص لم يُسجَّل بعد يظهر كاقتراح', () {
      final out = dueCheckups(condition: '', lastDone: {});
      expect(out.single.severity, 'low');
    });

    test('فحص متأخر يظهر تنبيهه', () {
      final out = dueCheckups(
        condition: '',
        lastDone: {'flu-vaccine': '2025-01-01'},
        now: DateTime(2026, 10, 4),
      );
      expect(out, isNotEmpty);
      expect(out.any((e) => e.title.contains('تطعيم الإنفلونزا')), isTrue);
    });

    test('فحص أُنجز حديثاً لا يظهر', () {
      final out = dueCheckups(
        condition: '',
        lastDone: {'flu-vaccine': '2026-09-20'},
        now: DateTime(2026, 10, 4),
      );
      expect(out, isEmpty);
    });
  });

  group('الترتيب', () {
    test('الأعلى خطورة أولاً', () {
      final out = stockAlerts([
        _med('أ', stock: 1, threshold: 5),
        _med('ب', stock: 0, threshold: 5),
      ]);
      expect(out.first.severity, 'high');
      expect(out.last.severity, 'medium');
    });
  });
}
