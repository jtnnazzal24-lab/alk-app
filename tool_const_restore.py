"""Re-applies the `const` keywords the sweep had to drop around `.tr` calls.

Reads the analyzer's `prefer_const_constructors` positions from
analyze_now.txt (line:col points at the constructor name) and inserts
`const ` there.
"""
import pathlib, re

rows = []
for line in pathlib.Path('c:/tabib2/analyze_now.txt').read_text(
        encoding='utf-8').splitlines():
    m = re.search(r'([\w/\\]+\.dart):(\d+):(\d+) - prefer_const_constructors',
                  line)
    if m:
        rows.append((m.group(1).replace('\\', '/'), int(m.group(2)),
                     int(m.group(3))))

by_file = {}
for rel, ln, col in rows:
    by_file.setdefault(rel, []).append((ln, col))

for rel, positions in by_file.items():
    p = pathlib.Path('c:/tabib2') / rel
    lines = p.read_text(encoding='utf-8').splitlines(keepends=True)
    for ln, col in sorted(positions, reverse=True):
        line = lines[ln - 1]
        idx = col - 1
        if line[idx - 6:idx] == 'const ':
            continue
        lines[ln - 1] = line[:idx] + 'const ' + line[idx:]
    p.write_text(''.join(lines), encoding='utf-8')
    print('%s: %d const restored' % (rel, len(positions)))