import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// يحاكي قنوات الإضافات في بيئة الاختبار (لا محرك ولا سجّل إضافات فيها).
///
/// بدونه تبقى رسائل المنصة بلا ردّ (ChannelBuffers تخزنها بلا مستمع) فتتعليق
/// كل `await` على القناة إلى الأبد: `store.init()` يتعلّق عند إعادة جدولة
/// التذكيرات، وحوار «الإشعارات الخلفية» لا يُفتح لأن بلاطته تبقى في حالة
/// «جارٍ التحقق…».
///
/// القيم تعكس جهازاً بصلاحيات ممنوحة: `initialize` = true و
/// `areNotificationsEnabled` = true و `checkPermissionStatus` = granted(1)؛
/// وأي استدعاء آخر (جدولة/إلغاء/إنشاء قناة/طلب صلاحية) يُجاب بلا قيمة.
void installNotificationChannelMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notifications = MethodChannel('dexterous.com/flutter/local_notifications');
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(notifications, (call) async {
    switch (call.method) {
      case 'initialize':
        return true;
      case 'areNotificationsEnabled':
        return true;
      default:
        // createNotificationChannel / zonedSchedule / show / cancel /
        // requestNotificationsPermission / canScheduleExactNotifications…
        return null;
    }
  });

  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(permissions, (call) async {
    switch (call.method) {
      case 'checkPermissionStatus':
        return 1; // PermissionStatus.granted
      default:
        return 0;
    }
  });
}
