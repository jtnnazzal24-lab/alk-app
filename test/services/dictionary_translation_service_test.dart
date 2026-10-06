import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alk_flutter/l10n/app_strings.dart';
import 'package:alk_flutter/services/dictionary_translation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => AppStrings.current = 'ar');

  test('يقرأ القاموس العربي من حزمة التطبيق دون أخطاء', () async {
    final restored =
        await DictionaryTranslationService.instance.restoreCache('fr');
    // لا توجد ترجمة مخزَّنة بعد، لكن قراءة القاموس يجب أن تنجح.
    expect(restored, isFalse);
    expect(DictionaryTranslationService.instance.lastError, isNull);
    // أنماط الأوامر الصوتية ليست نصوص عرض — لا تُترجم أبداً.
    // (في القاموس مخزَّنة كبدائل مفصولة بـ | أو مفاتيح regex، لا نصوص مطابقة)
    expect(
      DictionaryTranslationService.translates('طوارئ|طوارى|اسعاف|إسعاف|نجدة'),
      isFalse,
      reason: 'voice_commands: أنماط مطابقة عربية في voice_intent.dart',
    );
    expect(
      DictionaryTranslationService.translates('أضف دواء'),
      isFalse,
      reason: 'غير موجود في القاموس أصلاً — الأوامر regex لا تُترجم',
    );
    // نصوص العرض كلها تُترجم: عناوين، رد المساعد، إشعار، خطأ، نص طبي.
    expect(DictionaryTranslationService.translates('حفظ'), isTrue);
    expect(
      DictionaryTranslationService.translates('هذه صفحة الأدوية. سأخبرك ببطء'),
      isFalse,
      reason: 'النص الكامل يشمل تتمة الجملة — يُطابَق كاملاً فقط',
    );
    expect(DictionaryTranslationService.translates('موعد دوائك'), isTrue);
    expect(DictionaryTranslationService.translates('ضغط الدم'), isTrue);
  });

  test('لغة الهاتف تُقرأ من النظام', () {
    final tag = DictionaryTranslationService.deviceLanguageTag();
    expect(tag, isNotEmpty);
    expect(tag, tag.toLowerCase());
  });

  test('العربية لغة المصدر: لا تشغيل لترجمة ولا تخزين', () async {
    await DictionaryTranslationService.instance.start(targetLanguage: 'ar');
    expect(DictionaryTranslationService.instance.running, isFalse);
    expect(AppStrings.current, 'ar');
    expect(AppStrings.table.active, isFalse);
  });

  test('يقرأ ترجمة مخزَّنة كاملة على الجهاز ويعرضها فوراً بلا شبكة', () async {
    final sourceRaw =
        await rootBundle.loadString('assets/source_dictionary.json');
    final decoded = jsonDecode(sourceRaw) as Map<String, dynamic>;
    final strings = <String, String>{};

    void collect(Object? node) {
      if (node is Map) {
        final text = node['text'];
        if (text is String) {
          final trimmed = text.trim();
          if (trimmed.isNotEmpty && !strings.containsKey(trimmed)) {
            strings[trimmed] = 'fr-$trimmed';
          }
          return;
        }
        for (final value in node.values) {
          collect(value);
        }
      } else if (node is List) {
        for (final value in node) {
          collect(value);
        }
      }
    }

    collect(decoded['categories']);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'alk.dictionary.target-language': 'fr',
      'alk.dictionary.source-version': '1.0.0',
      'alk.dictionary.payload': jsonEncode(<String, Object>{
        'meta': <String, Object>{'targetLanguage': 'fr'},
        'strings': strings,
      }),
    });

    final restored =
        await DictionaryTranslationService.instance.restoreCache('fr');
    expect(restored, isTrue);
    expect(AppStrings.current, 'fr');
    expect(AppStrings.table.active, isTrue);
    expect(AppStrings.table.generation, 2);
    expect('حفظ'.tr, startsWith('fr-'));
  });

  test('الترجمة الجزئية تُرفض حتى لا تظهر نصوص ناقصة', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'alk.dictionary.target-language': 'fr',
      'alk.dictionary.source-version': '1.0.0',
      'alk.dictionary.payload': jsonEncode(<String, Object>{
        'meta': <String, Object>{'targetLanguage': 'fr'},
        'strings': <String, String>{
          'حفظ': 'Enregistrer',
        },
      }),
    });

    final restored =
        await DictionaryTranslationService.instance.restoreCache('fr');
    expect(restored, isFalse);
    expect(AppStrings.table.active, isFalse);
    expect(AppStrings.table.size, 0);
  });

  test('التخزين يخصّ لغة واحدة: الترجمة تُطلب للغة الواجهة نفسها', () {
    // لغة الهاتف غير العربية تُمرَّر كما هي مُنقّاةً من منطقة اللغة.
    expect(
        DictionaryTranslationService.deviceLanguageTag(), isNot(contains('-')));
  });
}
