import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:alk_flutter/storage/data_cipher.dart';

/// اختبارات تشفير ملف بيانات المريض (AES-256-GCM) بلا أي قناة منصّة:
/// يُحقن مفتاح معروف مباشرةً عبر `useKeyForTesting`.
void main() {
  setUp(() {
    DataCipher.forceDisabled = false;
    DataCipher.instance.resetForTesting();
  });

  tearDown(() {
    DataCipher.forceDisabled = false;
    DataCipher.instance.resetForTesting();
  });

  test('يُشفَّر النص ببادئة ALKENC1 ولا يظهر المحتوى الأصلي', () async {
    await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 7));
    const secret = '{"patient":{"fullName":"محمد"},"vitals":[]}';

    final encrypted = await DataCipher.instance.encrypt(secret);

    expect(DataCipher.isEncrypted(encrypted), isTrue);
    expect(encrypted.startsWith(DataCipher.header), isTrue);
    expect(encrypted.contains('محمد'), isFalse);
    expect(encrypted.contains('patient'), isFalse);
    expect(await DataCipher.instance.decrypt(encrypted), secret);
  });

  test('فكّ التشفير بمفتاح مختلف يفشل (لا كشف للبيانات)', () async {
    await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 1));
    final encrypted = await DataCipher.instance.encrypt('{"medications":[]}');

    DataCipher.instance.resetForTesting();
    await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 2));

    expect(await DataCipher.instance.decrypt(encrypted), isNull);
  });

  test('التلاعب بالمحتوى المشفَّر يُكتشف (وسم GCM) ويعيد null', () async {
    await DataCipher.instance.useKeyForTesting(List<int>.filled(32, 3));
    final encrypted = await DataCipher.instance.encrypt('{"vitals":[]}');
    final bytes = base64Decode(encrypted.substring(DataCipher.header.length));
    bytes[bytes.length - 1] = bytes[bytes.length - 1] ^ 0xFF; // تلف وسم
    final tampered = '${DataCipher.header}${base64Encode(bytes)}';

    expect(await DataCipher.instance.decrypt(tampered), isNull);
  });

  test('عند غياب التخزين الآمن يبقى النص كما هو (بلا فقدان بيانات)', () async {
    DataCipher.forceDisabled = true;
    DataCipher.instance.resetForTesting();
    const plain = '{"foodEntries":[]}';

    final out = await DataCipher.instance.encrypt(plain);

    expect(DataCipher.instance.enabled, isFalse);
    expect(out, plain);
    // والنص غير المشفَّر يُقرأ كما هو.
    expect(await DataCipher.instance.decrypt(plain), plain);
  });

  test('نص غير مشفَّر لا يُعدّ ملفاً مشفَّراً', () {
    expect(DataCipher.isEncrypted('{"a":1}'), isFalse);
    expect(DataCipher.isEncrypted(''), isFalse);
  });
}
