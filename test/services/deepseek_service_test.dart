import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alk_flutter/services/deepseek_service.dart';
import 'package:alk_flutter/services/secure_store.dart';

void main() {
  group('DeepSeekService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      // بلا قنوات منصّة: يُستخدم التخزين العادي في هذه المجموعة.
      DeepSeekService.forcePrefsMode = true;
      DeepSeekService.instance.resetForTesting();
    });

    tearDown(() {
      DeepSeekService.forcePrefsMode = false;
      DeepSeekService.instance.resetForTesting();
      SecureStore.debugMemory = null;
    });

    test('no key by default', () async {
      final svc = DeepSeekService.instance;
      await svc.load();
      expect(svc.hasKey, isFalse);
      expect(svc.apiKey, isNull);
    });

    test('saves the API key with a masked view', () async {
      final svc = DeepSeekService.instance;
      await svc.load();
      await svc.saveKey('sk-test-this-is-my-key-1234');
      expect(svc.hasKey, isTrue);
      expect(svc.apiKey, 'sk-test-this-is-my-key-1234');
      expect(svc.maskedKey, endsWith('1234'));
    });

    test('clear removes the key', () async {
      final svc = DeepSeekService.instance;
      await svc.saveKey('sk-clear-me');
      expect(svc.hasKey, isTrue);
      await svc.saveKey('');
      expect(svc.hasKey, isFalse);
    });

    // الأمان: المفتاح لا يبقى نصاً صريحاً في SharedPreferences.
    test('key goes to secure storage, never to plaintext prefs', () async {
      final memory = <String, String>{};
      SecureStore.debugMemory = memory;
      DeepSeekService.forcePrefsMode = false;

      await DeepSeekService.instance.saveKey('sk-secure-4321');

      expect(memory['alk.deepseek.api-key'], 'sk-secure-4321');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('alk.deepseek.api-key'), isNull);
    });

    test('legacy plaintext key migrates into secure storage', () async {
      SharedPreferences.setMockInitialValues({
        'alk.deepseek.api-key': 'sk-legacy-9999',
      });
      final memory = <String, String>{};
      SecureStore.debugMemory = memory;
      DeepSeekService.forcePrefsMode = false;
      DeepSeekService.instance.resetForTesting();

      await DeepSeekService.instance.load();

      expect(DeepSeekService.instance.apiKey, 'sk-legacy-9999');
      expect(memory['alk.deepseek.api-key'], 'sk-legacy-9999');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('alk.deepseek.api-key'), isNull);
    });
  });
}
