import 'package:flutter_test/flutter_test.dart';

import 'package:alk_flutter/l10n/app_strings.dart';

void main() {
  tearDown(() => AppStrings.current = 'ar');

  group('TranslationTable', () {
    test('يعرض الترجمة الدقيقة عند تفعيل الجدول', () {
      final table = TranslationTable()..language = 'fr';
      table.put('حفظ', 'Enregistrer');
      expect(table.active, isTrue);
      expect(table.size, 1);
      expect(table.lookup('حفظ'), 'Enregistrer');
    });

    test('يعيد النص نفسه عند غياب الترجمة', () {
      final table = TranslationTable()..language = 'fr';
      table.put('حفظ', 'Enregistrer');
      expect(table.lookup('نص غير مدرج في القاموس'), 'نص غير مدرج في القاموس');
    });

    test('العربية لغة المصدر — لا ترجمة تُعرض', () {
      final table = TranslationTable();
      table.put('حفظ', 'Enregistrer');
      expect(table.active, isFalse);
      expect(table.lookup('حفظ'), 'حفظ');
    });

    test('يُركّب القوالب ذات المتغيرات بقيمة العرض الحالية', () {
      final table = TranslationTable()..language = 'fr';
      table.put('تمت إضافة \$name إلى قائمة الطوارئ', 'Ajout [[0]] à la liste');
      expect(
        table.lookup('تمت إضافة أحمد إلى قائمة الطوارئ'),
        'Ajout أحمد à la liste',
      );
    });

    test('يدعم أكثر من متغير في النص الواحد', () {
      final table = TranslationTable()..language = 'fr';
      table.put('\$medicine — \$minutes دقيقة', '[[0]] — [[1]] minutes');
      expect(
        table.lookup('باراسيتامول — 30 دقيقة'),
        'باراسيتامول — 30 minutes',
      );
    });

    test('يوحّد المسافات داخل علامات المتغيرات', () {
      final table = TranslationTable()..language = 'fr';
      table.put('مرحبًا \$name', 'Bonjour [[ 0 ]]');
      expect(table.lookup('مرحبًا جمال'), 'Bonjour جمال');
    });

    test('يترجم القيم المُدرَجة داخل القالب (أسماء التمارين والأطعمة)', () {
      final table = TranslationTable()..language = 'fr';
      table.put('مرحبًا \$name', 'Bonjour [[0]]');
      table.put('جمال', 'Jamel');
      expect(table.lookup('مرحبًا جمال'), 'Bonjour Jamel');
    });

    test('يقبل القيم الفارغة داخل القالب', () {
      final table = TranslationTable()..language = 'fr';
      table.put('• \$a من \$b جرعات', '• [[0]] sur [[1]] doses');
      expect(table.lookup('• 0 من 0 جرعات'), '• 0 sur 0 doses');
      expect(table.lookup('• 2 من 3 جرعات'), '• 2 sur 3 doses');
    });

    test('يتجاهل القالب الذي هو متغير واحد فقط', () {
      final table = TranslationTable()..language = 'fr';
      table.put('\$anything', 'n\u2019importe quoi');
      expect(table.size, 0);
      expect(table.lookup('أي نص'), 'أي نص');
    });

    test('يُبقي النص العربي إذا فقدت الترجمة متغيرًا', () {
      final table = TranslationTable()..language = 'fr';
      table.put('مرحبًا \$name كيف حالك', 'Bonjour comment allez-vous');
      expect(
        table.lookup('مرحبًا جمال كيف حالك'),
        'مرحبًا جمال كيف حالك',
      );
    });

    test('يتجاهل الترجمة المطابقة للنص الأصلي', () {
      final table = TranslationTable()..language = 'fr';
      table.put('ALK', 'ALK');
      expect(table.size, 0);
    });

    test('تغيير اللغة يفرّغ الجدول حتى لا تُخلط لغتان', () {
      final table = TranslationTable()..language = 'fr';
      table.put('حفظ', 'Enregistrer');
      table.setLanguage('de');
      expect(table.size, 0);
      expect(table.language, 'de');
    });
  });

  group('واجهة .tr', () {
    test('تعرض المترجم ثم تعود للعربي عند تغيير اللغة', () {
      AppStrings.current = 'fr';
      AppStrings.table.load(<String, String>{'حفظ': 'Enregistrer'});
      AppStrings.table.generation = 2;
      expect('حفظ'.tr, 'Enregistrer');
      expect(AppStrings.table.generation, 2);

      AppStrings.current = 'ar';
      expect('حفظ'.tr, 'حفظ');
      expect(AppStrings.table.size, 0);
      expect(AppStrings.table.generation, 0);
    });

    test('تمرّر النص كما هو ما دام الجدول فارغاً (العربية الافتراضية)', () {
      expect('حفظ'.tr, 'حفظ');
      expect(AppStrings.table.active, isFalse);
    });
  });
}
