import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alk_flutter/logic/vital_advice.dart';
import 'package:alk_flutter/screens/vitals_screen.dart';
import 'package:alk_flutter/state/sandy_store.dart';
import 'package:alk_flutter/storage/sandy_repository.dart';

import '../helpers/notification_mocks.dart';
import '../helpers/platform_secrets.dart';

void main() {
  // نفس ضوابط `widget_test.dart`: التخزين عبر SharedPreferences بلا ملف،
  // ومحاكاة قنوات الإشعارات/الصلاحيات حتى لا يعلّق `store.init()` إلى الأبد.
  setUpAll(() {
    SandyRepository.forcePrefsMode = true;
    installNotificationChannelMocks();
    disableSecureStorageInTests();
  });
  tearDownAll(() {
    SandyRepository.forcePrefsMode = false;
    restoreSecureStorageAfterTests();
  });

  Future<SandyStore> storeWithVitals(
      List<Map<String, dynamic>> vitals) async {
    SharedPreferences.setMockInitialValues({
      SandyRepository.migrationDoneKey: true,
      SandyRepository.mainKey: jsonEncode({
        'vitals': vitals,
        // ملف صغير للتجربة: مريض له رقم طبيب ليظهر زر الاتصال.
        'patient': {
          'conditionName': 'سكري',
          'doctorPhone': '0591234567',
        },
        'dataRetentionDays': 0,
      }),
    });
    final store = SandyStore(SandyRepository());
    await store.init();
    return store;
  }

  Widget wrap(SandyStore store) => ChangeNotifierProvider<SandyStore>.value(
        value: store,
        child: const MaterialApp(home: VitalsScreen()),
      );

  test('ألوان ورموز المستويات موحّدة لكل نتيجة', () {
    expect(vitalLevelColor(VitalLevel.normal), isNot(vitalLevelColor(VitalLevel.abnormal)));
    expect(vitalLevelColor(VitalLevel.emergency),
        isNot(vitalLevelColor(VitalLevel.abnormal)));
    expect(vitalLevelColor(VitalLevel.unknown), Colors.grey);
    expect(vitalLevelIcon(VitalLevel.normal), Icons.check_circle_outline);
    expect(vitalLevelIcon(VitalLevel.emergency),
        Icons.local_hospital_outlined);
  });

  testWidgets('يعرض بطاقة النتيجة بتفصيل أسوأ قياس وأزرارها', (tester) async {
    final store = await storeWithVitals([
      {
        'id': 'v1',
        'kind': 'pressure',
        'value': '150/95',
        'createdAt': '2026-09-27T10:00:00',
      },
      {
        'id': 'v2',
        'kind': 'sugar',
        'value': '95',
        'createdAt': '2026-09-27T09:00:00',
      },
      {
        'id': 'v3',
        'kind': 'spo2',
        'value': '97%',
        'createdAt': '2026-09-27T08:00:00',
      },
      {
        'id': 'v4',
        'kind': 'pulse',
        'value': '72',
        'createdAt': '2026-09-27T07:00:00',
      },
    ]);
    await tester.pumpWidget(wrap(store));
    await tester.pump();

    // رأس البطاقة: العنوان + صف لكل قياس من الأنواع الأربعة.
    expect(find.text('نتيجة قياساتك'), findsOneWidget);
    expect(find.text('ضغط الدم'), findsWidgets);
    expect(find.text('سكر الدم'), findsWidgets);
    expect(find.text('الأكسجين'), findsWidgets);
    expect(find.text('النبض'), findsWidgets);
    expect(find.text('غير مقبولة'), findsOneWidget);
    expect(find.text('طبيعية'), findsWidgets);

    // تفصيل أسوأ نتيجة (ضغط 150/95): رسالة + تمارين + أغذية.
    expect(find.textContaining('ضغطك مرتفع'), findsWidgets);
    expect(find.textContaining('تمارين مقترحة لك'), findsOneWidget);
    expect(find.textContaining('أغذية تساعدك على التحسين'), findsOneWidget);

    // زر الاتصال (له رقم طبيب) + تنويه الإرشاد التثقيفي.
    expect(find.widgetWithText(FilledButton, 'اتصل بطبيبك'), findsOneWidget);
    expect(find.textContaining('إرشاد تثقيفي فقط'), findsOneWidget);
  });

  testWidgets('يخفي بطاقة النتيجة عند غياب القياسات', (tester) async {
    final store = await storeWithVitals([]);
    await tester.pumpWidget(wrap(store));
    await tester.pump();

    expect(find.text('نتيجة قياساتك'), findsNothing);
    expect(find.text('لا توجد قراءات بعد'), findsOneWidget);
  });

  testWidgets('يعرض نتيجة السكر مع سياقها المحفوظ (بعد الأكل)',
      (tester) async {
    final store = await storeWithVitals([
      {
        'id': 's1',
        'kind': 'sugar',
        'value': '200 بعد الأكل',
        'createdAt': '2026-09-27T10:00:00',
      },
    ]);
    await tester.pumpWidget(wrap(store));
    await tester.pump();

    expect(find.text('سكر الدم'), findsWidgets);
    expect(find.text('200 بعد الأكل'), findsWidgets);
    expect(find.textContaining('سكرك مرتفع'), findsWidgets);
    // مع ارتفاع السكر تظهر نصائح الأكل مع رابط شاشة التغذية.
    expect(find.textContaining('أغذية تساعدك على التحسين'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'افتح نصائح التغذية'),
        findsOneWidget);
  });
}

