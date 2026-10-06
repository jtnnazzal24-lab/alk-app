"""One-off migration, pass 3 — content based (immune to line shifts).

For the UI files that hold hardcoded Arabic, every Arabic literal is routed
through `.tr` except the ones that are data / logic / comments, matched by
line-content patterns.
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

# lines that must stay as-is (data keys, comparisons, pre-translated maps)
# key: file -> list of regexes matched against the whole line
SKIP = {
    '*': [
        r'^\s*//',                      # comments / doc comments
        r'_nameController\.text\s*=',   # food name fed to the advice engine
        r'channelLabel',                # report channel comparison
        r'\bcategory:',                 # stored medication category
        r'static const _phases',        # breathing phase data
        r"^\s*\w+\s*=\s*'[^']*';\s*$",  # simple local data assignments
        r'^\s*\d+\s*[=:]',              # map entry / switch case value
        r'_languages',                  # language-name map
        r'^\s*const\s+Color',           # colour constants
        r'==\s*[\'"]',                  # string comparisons
        r'!=\s*[\'"]',
        r'\.contains\([\'"]',
        r'^\s*case\s',
        r"^\s*'[^']*'\s*:",             # map entry with a string key
    ],
}


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


def chain_end(s, j):
    while True:
        k = j
        while k < len(s) and s[k] in ' \t\r\n':
            k += 1
        if k < len(s) and s[k] in '\'"':
            e = literal_end(s, k)
            if e == -1:
                return j
            j = e
            continue
        return j


base = pathlib.Path('c:/tabib2/lib')
added, kept = 0, 0
for rel in FILES:
    p = base / rel
    text = p.read_text(encoding='utf-8')
    # 1) drop every `'…'.tr` that follows an Arabic literal (restored below)
    text = re.sub(r"""(['"])((?:[^'"\n]|\\\n)*?[\u0600-\u06FF](?:[^'"\n])*?)\1\.tr\b""",
                  r'\1\2\1', text)
    pans = SKIP['*']
    out, i, line_start = [], 0, 0
    while i < len(text):
        if text[i] == '\n':
            line_start = i + 1
            out.append(text[i])
            i += 1
            continue
        if text[i] in '\'"':
            e = literal_end(text, i)
            if e == -1:
                out.append(text[i])
                i += 1
                continue
            line = text[line_start:text.find('\n', i) if '\n' in text[i:] else len(text)]
            skip = any(re.search(rx, line) for rx in pans)
            lit = text[i:e]
            if not skip and ARABIC.search(INTERP.sub('', lit)):
                ce = chain_end(text, e)
                if re.match(r'\s*\.tr\b', text[ce:]):
                    out.append(lit)
                    i = e
                    continue
                out.append(lit + '.tr')
                added += 1
                i = ce
                line_start = text.rfind('\n', 0, ce) + 1
                continue
            out.append(lit)
            i = e
            continue
        out.append(text[i])
        i += 1
    text = ''.join(out)
    # 2) drop a same-line `const` that would now wrap a getter call
    lines = text.splitlines(keepends=True)
    for idx, line in enumerate(lines):
        m = re.search(r"""(['"])(?:[^'"\n])*?[\u0600-\u06FF]""", line)
        if not m or '.tr' not in line:
            continue
        first = m.start()
        if re.search(r"[^\w.]\.tr\b", line[first:]) :
            c = line.rfind('const ', 0, first)
            if c != -1:
                lines[idx] = line[:c] + line[c + 6:]
    text = ''.join(lines)
    # 3) `.tr` needs the string-table import
    if 'l10n/app_strings.dart' not in text:
        ls = text.splitlines(keepends=True)
        anchor = None
        for idx, l in enumerate(ls):
            if re.match(r"^import '\.\./", l):
                anchor = idx + 1
                break
        if anchor is None:
            for idx, l in enumerate(ls):
                if re.match(r"^import '", l):
                    anchor = idx + 1
        ls.insert(anchor, "import '../l10n/app_strings.dart';\n")
        text = ''.join(ls)
    p.write_text(text, encoding='utf-8')
print('wrapped:', added)