import 'dart:io';

void main() {
  final f = File('C:/tabib2/word/document.xml');
  final xml = f.readAsStringSync();
  String body = xml;
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
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
      .replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
  final lines = body
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .toList();
  final clean = lines.join('\n');
  File('C:/tabib2/word/extracted.txt').writeAsStringSync(clean, flush: true);
  stdout.writeln('extracted ${clean.length} bytes');
}