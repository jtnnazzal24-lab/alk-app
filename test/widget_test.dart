import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alk_flutter/main.dart';
import 'package:alk_flutter/screens/home_screen.dart';
import 'package:alk_flutter/screens/medications_screen.dart';
import 'package:alk_flutter/screens/nutrition_screen.dart';
import 'package:alk_flutter/screens/chat_screen.dart';
import 'package:alk_flutter/screens/settings_screen.dart';
import 'package:alk_flutter/state/sandy_store.dart';
import 'package:alk_flutter/storage/sandy_repository.dart';
import 'package:alk_flutter/theme/alk_theme.dart';

import 'helpers/notification_mocks.dart';
import 'helpers/platform_secrets.dart';

void main() {
  setUpAll(() {
    SandyRepository.forcePrefsMode = true;
    // بلا محاكاة القنوات تتعليق كل `await` على إضافات الإشعارات/الصلاحيات
    // إلى الأبد (رسائل المنصة تُخزَّن بلا ردّ)، فيتعلّق init المخزن وشاشة
    // الإعدادات ولا يُفتح حوار حالة الإشعارات الخلفية.
    installNotificationChannelMocks();
    // لا قنوات Keystore/Keychain في اختبارات الوحدة (تشفير الملف يُختبر
    // مستقلاً)، فلا تُعلّق أي رسالة قناة بلا ردّ.
    disableSecureStorageInTests();
  });
  tearDownAll(() {
    SandyRepository.forcePrefsMode = false;
    restoreSecureStorageAfterTests();
  });

  group('ALK App Widget Tests', () {
    testWidgets('App shows loading screen initially', (tester) async {
      final store = SandyStore(SandyRepository());
      await tester.pumpWidget(AlkApp(store: store));
      
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('ALK'), findsOneWidget);
    });

    testWidgets('HomeScreen has bottom navigation', (tester) async {
      final store = SandyStore(SandyRepository());
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('الرئيسية'), findsOneWidget);
      expect(find.text('أدويتي'), findsOneWidget);
      expect(find.text('القياسات'), findsOneWidget);
      expect(find.text('يومياتي'), findsOneWidget);
      expect(find.text('المزيد'), findsOneWidget);
    });
  });

  group('ALK Medications Tab', () {
    /// A store preloaded with data (bypasses the notification plugin so unit
    /// tests stay free of platform channels).
    Future<SandyStore> storeWithMedication(String name) async {
      SharedPreferences.setMockInitialValues({
        SandyRepository.migrationDoneKey: true,
        SandyRepository.mainKey: jsonEncode({
          'medications': [
            {
              'id': 'med-test-1',
              'name': name,
              'time': '08:00',
              'category': 'عام',
              'taken': false,
              'updatedAt': '2026-09-04T08:00:00.000',
              'reminderEnabled': false,
            },
          ],
        }),
      });
      final store = SandyStore(SandyRepository());
      await store.init();
      return store;
    }

    Future<void> pumpMeds(
      WidgetTester tester,
      SandyStore store,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(home: MedicationsScreen()),
        ),
      );
    }

    testWidgets('lists stored medications with add/toggle actions',
        (tester) async {
      final store = await storeWithMedication('باراسيتامول');
      await pumpMeds(tester, store);

      // List renders the stored medication.
      expect(find.text('أدويتي'), findsOneWidget); // AppBar title
      expect(find.text('باراسيتامول'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);

      // Toggling the "confirm taken" button updates the row immediately.
      await tester.tap(find.byIcon(Icons.check_circle_outline));
      await tester.pumpAndSettle();
      expect(find.text('تم التناول ✓'), findsOneWidget);
      expect(store.medications.single.taken, isTrue);
    });

    testWidgets('shows the empty state when there are no medications',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        SandyRepository.migrationDoneKey: true,
        SandyRepository.mainKey: jsonEncode({'medications': []}),
      });
      final store = SandyStore(SandyRepository());
      await store.init();
      await pumpMeds(tester, store);

      expect(find.text('لا توجد أدوية بعد'), findsOneWidget);
      expect(find.text('أضف دواءً لمتابعة جرعاتك'), findsOneWidget);
    });
  });

  group('ALK Nutrition Tracker', () {
    Future<SandyStore> storeWithNutrition() async {
      SharedPreferences.setMockInitialValues({
        SandyRepository.migrationDoneKey: true,
        SandyRepository.mainKey: jsonEncode({
          'foodEntries': [
            {
              'id': 'food-test-1',
              'name': 'شاورما',
              'mealType': 'عشاء',
              'createdAt': DateTime.now().toIso8601String(),
            },
          ],
          'dataRetentionDays': 0,
          'vitals': [
            {
              'id': 'vital-test-1',
              'kind': 'sugar',
              'value': '135',
              'createdAt': DateTime.now().toIso8601String(),
            },
          ],
        }),
      });
      final store = SandyStore(SandyRepository());
      await store.init();
      return store;
    }

    testWidgets('lists foods and shows impact advice', (tester) async {
      final store = await storeWithNutrition();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(home: NutritionScreen()),
        ),
      );

      expect(find.text('التغذية'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();
      expect(find.text('شاورما'), findsWidgets);
      expect(find.text('سكر الدم'), findsWidgets);
      expect(find.textContaining('آخر قراءة سكر'), findsWidgets);
    });

    testWidgets('adds a food and persists it', (tester) async {
      final store = await storeWithNutrition();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(home: NutritionScreen()),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'برجر');
      await tester.pump();
      // Live analysis appears for the fast food.
      expect(find.text('هذا الطعام يؤثر على:'), findsOneWidget);

      await tester.ensureVisible(find.text('إضافة الوجبة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة الوجبة'));
      await tester.pumpAndSettle();

      // The added food appears as a tile (plus its quick chip suggestion).
      expect(find.text('برجر'), findsWidgets);
      expect(store.foodEntries.any((f) => f.name == 'برجر'), isTrue);
    });
  });

  group('ALK Chat (DeepSeek)', () {
    testWidgets('shows the AI-not-enabled banner when no key is stored',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: ChatScreen()));
      await tester.pump();
      expect(find.textContaining('الذكاء الآلي غير مفعّل'), findsOneWidget);
    });
  });

  group('ALK Settings', () {
    /// يرسم شاشة الإعدادات كاملة الارتفاع (سطح مرتفع) حتى تُبنى كل العناصر
    /// بما فيها بطاقة الإرشاد أسفل القائمة.
    Future<void> pumpSettings(WidgetTester tester, ThemeData theme) async {
      SharedPreferences.setMockInitialValues({
        SandyRepository.migrationDoneKey: true,
        SandyRepository.mainKey: '{}',
      });
      await tester.binding.setSurfaceSize(const Size(500, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = SandyStore(SandyRepository());
      await store.init();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            theme: theme,
            locale: const Locale('ar'),
            home: const SettingsScreen(),
          ),
        ),
      );
      // مؤشرات التحميل تدور باستمرار، لذا نضخّ إطارات محددة بدل pumpAndSettle.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// بطاقة الإرشاد الطبي أسفل قائمة الإعدادات.
    Card disclaimerCard(WidgetTester tester) => tester.widget<Card>(
          find.ancestor(
            of: find.textContaining('لا يقدم تشخيصًا طبيًا'),
            matching: find.byType(Card),
          ),
        );

    // في الوضع الداكن كانت البطاقة ثابتة فاتحة (Colors.amber.shade50) والنص
    // فاتحاً أيضاً، فتظهر كمربع أبيض فارغ لا يعرف المستخدم ما هو.
    testWidgets('disclaimer card follows the dark theme palette',
        (tester) async {
      await pumpSettings(tester, AlkTheme.dark());
      expect(disclaimerCard(tester).color, AlkColors.dark.goldSoft);
    });

    testWidgets('disclaimer card follows the light theme palette',
        (tester) async {
      await pumpSettings(tester, AlkTheme.light());
      expect(disclaimerCard(tester).color, AlkColors.light.goldSoft);
    });
  });

  group('ALK Home dashboard', () {
    Future<SandyStore> emptyStore() async {
      SharedPreferences.setMockInitialValues({
        SandyRepository.migrationDoneKey: true,
        SandyRepository.mainKey: '{}',
      });
      final store = SandyStore(SandyRepository());
      await store.init();
      return store;
    }

    Future<void> pumpHome(
      WidgetTester tester,
      ThemeData theme,
    ) async {
      final store = await emptyStore();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            theme: theme,
            locale: const Locale('ar'),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    /// بطاقة الالتزام بالأدوية أعلى اللوحة الرئيسية.
    Card adherenceCard(WidgetTester tester) => tester.widget<Card>(
          find.ancestor(
            of: find.text('الالتزام بالأدوية'),
            matching: find.byType(Card),
          ),
        );

    // بلا أدوية مسجلة تكون النسبة 0% فيُستخدم لون الخطأ: كان ثابتاً فاتحاً
    // (AlkColors.light) فيظهر باهتاً وغير مقروء في الوضع الداكن، والشفافية
    // تُرفع إلى 0.18 في الداكن حتى يظهر التظليل.
    testWidgets('adherence card follows the dark theme palette',
        (tester) async {
      await pumpHome(tester, AlkTheme.dark());
      expect(adherenceCard(tester).color,
          AlkColors.dark.error.withValues(alpha: 0.18));
    });

    testWidgets('adherence card follows the light theme palette',
        (tester) async {
      await pumpHome(tester, AlkTheme.light());
      expect(adherenceCard(tester).color,
          AlkColors.light.error.withValues(alpha: 0.1));
    });
  });

  group('ALK Background reminders', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        SandyRepository.migrationDoneKey: true,
        SandyRepository.mainKey: '{}',
      });
      final store = SandyStore(SandyRepository());
      await store.init();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(
            theme: AlkTheme.light(),
            locale: const Locale('ar'),
            home: const SettingsScreen(),
          ),
        ),
      );
      // بلا pumpAndSettle: بعض مؤشرات التحميل في الشاشة يدور باستمرار،
      // لذا نضخّ إطارات محددة. وننتظر حتى تنتهي بلاطة فحص الإشعارات من
      // فحصها (القنوات المُحاكاة تُجيب فوراً) قبل فتح الحوار.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text('جارٍ التحقق…').evaluate().isEmpty) break;
      }
    }

    // تذكيرات الخلفية تعتمد على ثلاث صلاحيات (إشعارات، تنبيهات دقيقة، استثناء
    // البطارية). الحوار سابقاً كان يعرض حالتين فقط وبلا أي وسيلة تحقّق عملية
    // للمستخدم — الاختبار يضمن ظهور الحالات الثلاث وزر «تنبيه تجريبي» معاً.
    testWidgets('status dialog shows all three permissions and a test button',
        (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('الإشعارات الخلفية'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('حالة الإشعارات الخلفية'), findsOneWidget);
      expect(find.textContaining('صلاحية الإشعارات'), findsOneWidget);
      expect(find.textContaining('استثناء من تحسين البطارية'), findsOneWidget);
      expect(find.textContaining('التنبيهات الدقيقة'), findsOneWidget);
      expect(find.text('إرسال تنبيه تجريبي الآن'), findsOneWidget);
    });

    testWidgets('test reminder button reports feedback instead of crashing',
        (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('الإشعارات الخلفية'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // بيئة الاختبار بلا قنوات إشعارات ⇒ تظهر رسالة «تعذّر/تجريبي» واضحة
      // بدل انهيار صامت — يثبت أن الزر موصول بالمتجر ويُظهر تغذية راجعة.
      await tester.tap(find.text('إرسال تنبيه تجريبي الآن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.textContaining('تجريبي'), findsWidgets);

      // تصفية شريط النتيجة (مؤقّت إخفائه 10 ثوانٍ) حتى لا يبقى مؤقّت معلّق
      // عند إنهاء الاختبار (فحص «A Timer is still pending»).
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
    });
  });
}
