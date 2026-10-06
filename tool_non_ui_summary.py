import pathlib, re
from collections import Counter
rows = pathlib.Path('c:/tabib2/non_ui_literals.txt').read_text(
    encoding='utf-8').splitlines()
c = Counter(r.split(':')[0] for r in rows)
out = []
for f, n in c.most_common():
    if f.startswith('locale/'):
        continue
    out.append('%s  (%d)' % (f, n))
    samples = [r.split(': ', 1)[1] for r in rows if r.startswith(f + ':')][:6]
    for s in samples:
        out.append('    ' + s)
pathlib.Path('c:/tabib2/non_ui_summary.txt').write_text(
    '\n'.join(out), encoding='utf-8')
print('\n'.join(out[:60]))