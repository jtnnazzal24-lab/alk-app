import pathlib
import re

AR = re.compile(r'[\u0600-\u06FF]')
LIT = re.compile(r"'([^'\n]*)'|\"([^\"\n]*)\"")

rows = []
for p in sorted(pathlib.Path('lib').rglob('*.dart')):
    text = p.read_text(encoding='utf-8')
    lines = text.splitlines()
    for m in LIT.finditer(text):
        value = m.group(1) if m.group(1) is not None else m.group(2)
        if not value or not AR.search(value):
            continue
        line_no = text[:m.start()].count('\n') + 1
        if lines[line_no - 1].strip().startswith('//'):
            continue
        tail = text[m.end():m.end() + 300]
        cut = len(tail)
        for ch in ',;)\n':
            pos = tail.find(ch)
            if pos != -1 and pos < cut:
                cut = pos
        expr = tail[:cut]
        if '.tr' in expr:
            continue
        rows.append((str(p), line_no, value.strip()))

with open('.audit_report.txt', 'w', encoding='utf-8') as f:
    current = None
    for path, line, value in rows:
        if path != current:
            current = path
            f.write('\n===== %s\n' % current)
        f.write('  %4d | %s\n' % (line, value[:120]))
    f.write('\nTOTAL %d\n' % len(rows))
print('rows', len(rows))
