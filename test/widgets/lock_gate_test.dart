import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alk_flutter/services/lock_state.dart';
import 'package:alk_flutter/state/sandy_store.dart';
import 'package:alk_flutter/storage/sandy_repository.dart';
import 'package:alk_flutter/widgets/lock_gate.dart';

import '../helpers/notification_mocks.dart';
import '../helpers/platform_secrets.dart';

/// اختبارات قفل التطبيق: لا تظهر أي بيانات قبل التحقق بالبصمة، ويُعاد القفل
/// عند مغادرة التطبيق. قناة `local_auth` تُحاكى بالكامل هنا.
void main() {
  const authChannel = MethodChannel('plugins.flutter.io/local_auth');
  var authSucceeds = false;
  var deviceSupportsAuth = true;

  setUpAll(() {
    SandyRepository.forcePrefsMode = true;
    installNotificationChannelMocks();
    disableSecureStorageInTests();
  });
  tearDownAll(() {
    SandyRepository.forcePrefsMode = false;
    restoreSecureStorageAfterTests();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLockState.instance.resetForTesting();
    authSucceeds = false;
    deviceSupportsAuth = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authChannel, (call) async {
      switch (call.method) {
        case 'getAvailableBiometrics':
          return deviceSupportsAuth ? <String>['fingerprint'] : <String>[];
        case 'isDeviceSupported':
          return deviceSupportsAuth;
        case 'authenticate':
          return authSucceeds;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authChannel, null);
    AppLockState.instance.resetForTesting();
  });

  /// مخزن محمّل مع قفل التطبيق مُفعَّل.
  Future<SandyStore> lockedStore() async {
    final store = SandyStore(SandyRepository());
    await store.init();
    await store.setPatientLock(true);
    return store;
  }

  Widget gateFor(SandyStore store) => MaterialApp(
        home: LockGate(
          store: store,
          child: const Scaffold(
            body: Center(child: Text('بيانات المريض')),
          ),
        ),
      );

  testWidgets('القفل يُفعَّل عند تشغيل قفل التطبيق', (tester) async {
    final store = await lockedStore();
    await tester.pumpWidget(gateFor(store));
    await tester.pump();

    expect(AppLockState.instance.isLocked, isTrue);
  });

  testWidgets('لا يظهر أي محتوى قبل التحقق ويظهر بعده', (tester) async {
    final store = await lockedStore();
    await tester.pumpWidget(gateFor(store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // قبل المصادقة: شاشة القفل فقط، ولا بيانات.
    expect(find.text('بيانات المريض'), findsNothing);
    expect(find.text('ALK مقفل'), findsOneWidget);

    authSucceeds = true;
    await tester.tap(find.text('فتح'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('بيانات المريض'), findsOneWidget);
    expect(AppLockState.instance.isLocked, isFalse);
  });

  testWidgets('بلا قفل مُفعَّل لا يُطلب أي تحقق ويظهر المحتوى', (tester) async {
    final store = SandyStore(SandyRepository());
    await store.init();
    await tester.pumpWidget(gateFor(store));
    await tester.pump();

    expect(find.text('بيانات المريض'), findsOneWidget);
    expect(AppLockState.instance.isLocked, isFalse);
  });

  testWidgets('عند تفعيل القفل أثناء التشغيل العادي يُطلب المصادقة فوراً',
      (tester) async {
    final store = SandyStore(SandyRepository());
    await store.init();
    await tester.pumpWidget(gateFor(store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('بيانات المريض'), findsOneWidget);
    expect(AppLockState.instance.isLocked, isFalse);

    await store.setPatientLock(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ALK مقفل'), findsOneWidget);
    expect(find.text('بيانات المريض'), findsNothing);
    expect(AppLockState.instance.isLocked, isTrue);
  });

  testWidgets('عند عدم وجود بصمة أو قفل شاشة يظهر إدخال PIN داخل التطبيق',
      (tester) async {
    final store = SandyStore(SandyRepository());
    await store.init();
    deviceSupportsAuth = false;
    await store.setPatientLock(true);

    await tester.pumpWidget(gateFor(store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('أنشئ PIN'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(AppLockState.instance.isLocked, isFalse);
    expect(find.text('بيانات المريض'), findsOneWidget);
  });

  testWidgets('يظهر زر تغيير PIN عندما يكون هناك PIN محفوظ', (tester) async {
    final store = SandyStore(SandyRepository());
    await store.init();
    deviceSupportsAuth = false;
    await store.setPatientLock(true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alk.app.lock.pin', '1234');

    await tester.pumpWidget(gateFor(store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('تغيير PIN'), findsOneWidget);
  });

  testWidgets('يُعاد القفل تلقائياً عند مغادرة التطبيق', (tester) async {
    final store = await lockedStore();
    await tester.pumpWidget(gateFor(store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    authSucceeds = true;
    await tester.tap(find.text('فتح'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('بيانات المريض'), findsOneWidget);

    // المستخدم انتقل لتطبيق آخر / أطفأ الشاشة.
    Future<void> sendLifecycle(String state) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(state),
        (_) {},
      );
    }

    await sendLifecycle('AppLifecycleState.paused');

    // القفل يُفعَّل فور التوقف (بلا انتظار رجوع المستخدم).
    expect(AppLockState.instance.isLocked, isTrue);

    // وأثناء التوقف يُعطّل Flutter إطارات الرسم، فعند العودة لا يُرسم إلا
    // شاشة القفل ولا تظهر بيانات المريض ولو للحظة.
    await sendLifecycle('AppLifecycleState.inactive');
    await sendLifecycle('AppLifecycleState.resumed');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('بيانات المريض'), findsNothing);
    expect(find.text('ALK مقفل'), findsOneWidget);
  });

  testWidgets(
      'البدء البارد: يظهر القفل بعد تحميل الإعداد (LockGate في builder)',
      (tester) async {
    // جلسة سابقة فعّلت القفل.
    final first = SandyStore(SandyRepository());
    await first.init();
    await first.setPatientLock(true);

    // جلسة جديدة: المخزن لم يُحمَّل بعد، و LockGate داخل MaterialApp.builder
    // (كما في التطبيق الحقيقي: main → RootGate.initState).
    final store = SandyStore(SandyRepository());
    AppLockState.instance.resetForTesting();

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          LockGate(store: store, child: child ?? const SizedBox.shrink()),
      home: const Scaffold(body: Center(child: Text('بيانات المريض'))),
    ));

    // البيانات تُحمَّل بعد أول إطار.
    await store.init();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // لا بد أن يظهر القفل ولا تُعرض بيانات المريض إطلاقاً.
    expect(find.text('بيانات المريض'), findsNothing);
    expect(find.text('ALK مقفل'), findsOneWidget);
    expect(AppLockState.instance.isLocked, isTrue);
  });
}
