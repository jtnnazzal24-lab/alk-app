"""Pass 4 — comment-aware sweep that routes visible Arabic literals through .tr.

Differences from pass 3: the file is tokenised first (strings / comments /
code), so apostrophes inside comments can no longer desynchronise quote pairing,
and the `const` that encloses a wrapped literal is removed by walking outward
from the literal instead of by a same-line heuristic.
"""
import pathlib, re

ARABIC = re.compile(r'[\u0600-\u06FF]')
INTERP = re.compile(r'\$\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}')

FILES = [
    'screens/chat_screen.dart', 'screens/emergency_screen.dart',
    'screens/home_screen.dart', 'screens/journals_screen.dart',
    'screens/lock_screen.dart', 'screens/medications_screen.dart',
    'screens/nutrition_screen.dart', 'screens/patient_screen.dart',
    'screens/reports_screen.dart', 'screens/settings_screen.dart',
    'screens/vitals_screen.dart', 'screens/voice_assistant_screen.dart',
    'screens/wellbeing_screen.dart', 'widgets/ai_mood_widgets.dart',
    'widgets/lock_gate.dart', 'widgets/mood_link.dart',
    'widgets/speak_button.dart',
]

SKIP = [
    r'^\s*//',
    r'_nameController\.text\s*=',   # food name handed to the advice engine
    r'channelLabel',                # report channel comparison
    r'\bcategory:',                 # stored medication category
    r'static const _phases',        # breathing phase data
    r'^\s*\w+\s*=\s*[^=]*;\s*$',    # simple local data assignment
    r'^\s*\d+\s*[=:]',              # numeric map key / switch case
    r'_languages',                  # language-name map
    r'^\s*const\s+Color',
    r'==\s*[\'"]',
    r'!=\s*[\'"]',
    r'\.contains\([\'"]',
    r'^\s*case\s',
    r"^\s*'[^']*'\s*:",
    r'^\s*(static\s+)?const\s+_[a-z]',   # private const tables
]


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


def tokenize(text):
    """Returns [(kind, start, end)] with kind in {'str','comment','code'}."""
    toks, i, n = [], 0, len(text)
    code_start = 0
    while i < n:
        c = text[i]
        if c == '/' and i + 1 < n and text[i + 1] in '/*':
            if i > code_start:
                toks.append(('code', code_start, i))
            if text[i + 1] == '/':
                j = text.find('\n', i)
                j = n if j == -1 else j
            else:
                j = text.find('*/', i)
                j = n if j == -1 else j + 2
            toks.append(('comment', i, j))
            i = code_start = j
            continue
        if c in '\'"':
            if i > code_start:
                toks.append(('code', code_start, i))
            e = literal_end(text, i)
            if e == -1:
                e = n
            toks.append(('str', i, e))
            i = code_start = e
            continue
        i += 1
    if n > code_start:
        toks.append(('code', code_start, n))
    return toks


def masked(text, toks, kind_to_blank):
    out = list(text)
    for kind, a, b in toks:
        if kind in kind_to_blank:
            for k in range(a, b):
                if out[k] != '\n':
                    out[k] = ' '
    return ''.join(out)


def enclosing_const(masked, pos):
    """Span of the `const` keyword whose scope covers `pos`, if any."""
    j = pos - 1
    while j >= 0:
        depth, k = 0, j
        while k >= 0:
            ch = masked[k]
            if ch in ')]}':
                depth += 1
            elif ch in '([{':
                if depth == 0:
                    break
                depth -= 1
            elif ch == ';' and depth == 0:
                return None
            k -= 1
        if k < 0:
            return None
        m2 = k - 1
        while m2 >= 0 and masked[m2].isspace():
            m2 -= 1
        while m2 >= 0 and (masked[m2].isalnum() or masked[m2] in '_.$'):
            m2 -= 1
        cm = re.search(r'\bconst\s*$', masked[:m2 + 1])
        if cm:
            return cm.span()
        j = k - 1
    return None


total = 0
for rel in FILES:
    p = pathlib.Path('c:/tabib2/lib') / rel
    text = p.read_text(encoding='utf-8')
    toks = tokenize(text)
    blank = masked(text, toks, {'comment'})
    walk = masked(text, toks, {'comment', 'str'})
    wraps = []
    for kind, a, b in toks:
        if kind != 'str':
            continue
        lit = text[a:b]
        if not ARABIC.search(INTERP.sub('', lit)):
            continue
        ce, k, n = b, b, len(text)
        while True:
            while k < n and text[k] in ' \t\r\n':
                k += 1
            if k < n and text[k] in '\'"':
                e = literal_end(text, k)
                if e == -1:
                    break
                ce, k = e, e
                continue
            break
        if re.match(r'\s*\.tr\b', text[ce:]):
            continue
        line_start = blank.rfind('\n', 0, a) + 1
        line_end = blank.find('\n', a)
        line = blank[line_start:len(blank) if line_end == -1 else line_end]
        if any(re.search(rx, line) for rx in SKIP):
            continue
        wraps.append((a, ce))
        total += 1
    # 1) drop the enclosing `const` (a getter call is not a constant)
    edits = []
    cuts = sorted(set(enclosing_const(walk, a) for a, ce in wraps) - {None})
    merged = []
    for s, e in cuts:
        if merged and s <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], e))
        else:
            merged.append((s, e))
    for s, e in merged:
        edits.append((s, e, ''))
    for a, ce in set(wraps):
        edits.append((ce, ce, '.tr'))
    for s, e, repl in sorted(edits, reverse=True):
        text = text[:s] + repl + text[e:]
    p.write_text(text, encoding='utf-8')
print('wrapped:', total)