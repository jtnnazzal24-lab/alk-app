import 'dart:io';

/// استخراج نصّ ملف Word (.docx) إلى نص عادي (فواصل فقرات/جداول).
/// الاستخدام: dart run tool/extract_docx_file.dart <input.xml> <output.txt>
void main(List<String> args) {
  final input = args.isNotEmpty ? args[0] : 'C:/tabib2/word/document.xml';
  final output = args.length > 1 ? args[1] : 'C:/tabib2/word/extracted.txt';
  final xml = File(input).readAsStringSync();
  var body = xml;
  body = body.replaceAll('<w:p ', '\n<w:p ').replaceAll('<w:p>', '\n<w:p>');
  body = body.replaceAll('</w:p>', '\n');
  body = body.replaceAll('</w:tc>', '\t');
  body = body.replaceAll('</w:tr>', '\n');
  body = body.replaceAllMapped(RegExp(r'<[^>]+>'), (_) => '');
  body = body
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(
          RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
      .replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'),
          (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
  final clean = body
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .toList()
      .join('\n');
  File(output).writeAsStringSync(clean, flush: true);
  stdout.writeln('extracted ${clean.length} bytes -> $output');
}
