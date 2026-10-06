import pathlib, re
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


text = (pathlib.Path('c:/tabib2/lib') / 'screens/patient_screen.dart').read_text(encoding='utf-8')
i, spans = 0, []
while i < len(text):
    if text[i] in '\'"':
        e = literal_end(text, i)
        if e == -1:
            i += 1
            continue
        spans.append((i, e))
        i = e
    else:
        i += 1
print('spans:', len(spans), 'arabic spans:',
      sum(1 for a, b in spans if ARABIC.search(INTERP.sub('', text[a:b]))))
for a, b in spans[:6]:
    print('  ', text[:a].count('\n') + 1, repr(text[a:b][:50]))

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

for rel in ['screens/patient_screen.dart', 'screens/wellbeing_screen.dart']:
    text = (pathlib.Path('c:/tabib2/lib') / rel).read_text(encoding='utf-8')
    found = []
    i = 0
    while i < len(text):
        if text[i] in '\'"':
            e = literal_end(text, i)
            if e == -1:
                i += 1
                continue
            lit = text[i:e]
            plain = INTERP.sub('', lit)
            if ARABIC.search(plain):
                found.append((text[:i].count('\n') + 1, lit[:40]))
            i = e
        else:
            i += 1
    print(rel, 'arabic literals:', len(found))
    for ln, lit in found[:8]:
        print('   ', ln, repr(lit))