"""Lists Arabic literals that never reach `.tr`, outside screens/widgets."""
import pathlib, re

root = pathlib.Path('c:/tabib2/lib')
ARABIC = re.compile(r'[\u0600-\u06FF]')
INTERP = re.compile(r'\$\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}')


def literal_end(s, start):
    q = s[start]
    i = start + 1
    while i < len(s):
        c = s[i]
        if c == '\\':
            i += 2
            continue
        if c == '$' and i + 1 < len(s) and s[i + 1] == '{':
            depth, j = 0, i + 1
            while j < len(s):
                if s[j] == '{':
                    depth += 1
                elif s[j] == '}':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            i = j + 1
            continue
        if c == q:
            return i + 1
        i += 1
    return -1


rows, per_dir = [], {}
for f in sorted(root.rglob('*.dart')):
    rel = f.relative_to(root).as_posix()
    if rel.startswith('screens/') or rel.startswith('widgets/') or \
            rel.startswith('l10n/'):
        continue
    text = f.read_text(encoding='utf-8', errors='ignore')
    i = 0
    while i < len(text):
        if text[i] in '\'"':
            e = literal_end(text, i)
            if e == -1:
                break
            lit = text[i:e]
            if ARABIC.search(INTERP.sub('', lit)) and \
                    not re.match(r'\s*\.tr\b', text[e:]):
                ln = text[:i].count('\n') + 1
                # ignore comments
                ls = text.rfind('\n', 0, i) + 1
                if not text[ls:i].lstrip().startswith('//'):
                    rows.append('%s:%d: %s' % (rel, ln, lit[:70]))
                    d = rel.split('/')[0]
                    per_dir[d] = per_dir.get(d, 0) + 1
            i = e
            continue
        i += 1
pathlib.Path('c:/tabib2/non_ui_literals.txt').write_text(
    '\n'.join(rows), encoding='utf-8')
print('total:', len(rows))
for d, c in sorted(per_dir.items()):
    print('  %-10s %d' % (d, c))