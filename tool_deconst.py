"""Removes the `const` keywords that now wrap `.tr` getter calls."""
import pathlib

SITES = [
    ('screens/chat_screen.dart', 153, 'decoration: const InputDecoration('),
    ('screens/emergency_screen.dart', 74, 'child: const Padding('),
    ('screens/emergency_screen.dart', 96, 'decoration: const InputDecoration('),
    ('screens/emergency_screen.dart', 123, 'decoration: const InputDecoration('),
    ('screens/emergency_screen.dart', 150, 'const Padding('),
    ('screens/journals_screen.dart', 159, 'decoration: const InputDecoration('),
    ('screens/medications_screen.dart', 103, 'return const Padding('),
    ('screens/nutrition_screen.dart', 138, 'const Card('),
    ('screens/nutrition_screen.dart', 168, 'decoration: const InputDecoration('),
    ('screens/reports_screen.dart', 57, 'const Card('),
    ('screens/reports_screen.dart', 88, 'const Card('),
    ('screens/reports_screen.dart', 136, 'decoration: const InputDecoration('),
    ('screens/reports_screen.dart', 146, 'decoration: const InputDecoration('),
    ('screens/vitals_screen.dart', 66, 'showSnackBar(const SnackBar('),
    ('screens/vitals_screen.dart', 284, 'showSnackBar(const SnackBar('),
    ('screens/vitals_screen.dart', 297, 'showSnackBar(const SnackBar('),
    ('screens/vitals_screen.dart', 311, 'const Padding('),
    ('screens/vitals_screen.dart', 376, 'const Expanded('),
    ('widgets/ai_mood_widgets.dart', 35, 'const Expanded('),
]

base = pathlib.Path('c:/tabib2/lib')
for rel, ln, needle in SITES:
    p = base / rel
    lines = p.read_text(encoding='utf-8').splitlines(keepends=True)
    line = lines[ln - 1]
    if needle not in line:
        print('MISS %s:%d  %r' % (rel, ln, line.strip()[:60]))
        continue
    lines[ln - 1] = line.replace(needle, needle.replace('const ', '', 1), 1)
    p.write_text(''.join(lines), encoding='utf-8')
    print('ok   %s:%d' % (rel, ln))