import 'package:alk_flutter/services/secure_store.dart';
import 'package:alk_flutter/storage/data_cipher.dart';

/// يعطّل قنوات المنصّة الخاصة بالأسرار (Android Keystore / iOS Keychain) في
/// اختبارات الوحدة: لا محرك إضافات في بيئة الاختبار، فتظل رسائل القناة بلا ردّ
/// وتُعلّق أي `await`. بهذا يعمل التطبيق في الاختبارات بالمسار البديل
/// (تخزين عادي بلا تشفير)، ويُختبر التشفير مستقلاً في `data_cipher_test.dart`
/// عبر `DataCipher.useKeyForTesting`.
void disableSecureStorageInTests() {
  SecureStore.forceUnavailable = true;
  DataCipher.forceDisabled = true;
}

/// يُعيد الحالة الافتراضية بعد انتهاء الاختبارات.
void restoreSecureStorageAfterTests() {
  SecureStore.forceUnavailable = false;
  SecureStore.debugMemory = null;
  DataCipher.forceDisabled = false;
  DataCipher.instance.resetForTesting();
}
