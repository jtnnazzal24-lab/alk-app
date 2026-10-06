"""One-off migration, pass 2.

Pass 1 wrongly appended `.tr` in the middle of wrapped string chains
(`'a '\n'b'` is one literal in Dart) and left files without the
`app_strings.dart` import. This pass reverts the pass-1 insertions on the
curated lines and re-applies them at the real end of each literal chain.
"""
import pathlib, re

ARABIC = re.compile(r'[\u0600-\u06FF]')
INTERP = re.compile(r'\$\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}')

TARGETS = {
    'screens/chat_screen.dart': [20, 57, 61, 83, 98, 154],
    'screens/emergency_screen.dart': [33, 43, 54, 67, 76, 89, 98, 105, 120, 125,
                                      132, 138, 146, 153],
    'screens/home_screen.dart': [65, 146, 158, 164, 211, 227],
    'screens/journals_screen.dart': [58, 62, 86, 105, 111, 133, 143, 159, 168,
                                     177],
    'screens/lock_screen.dart': [38, 50, 54, 84, 90, 114],
    'screens/medications_screen.dart': [84, 110, 111, 162],
    'screens/nutrition_screen.dart': [38, 59, 60, 80, 85, 98, 116, 119, 134,
                                      140, 162, 168, 169, 184, 217, 221, 228,
                                      267, 282, 286, 297, 320, 333, 334, 335,
                                      338, 354, 355, 391, 504, 514, 524],
    'screens/patient_screen.dart': [64, 74, 82, 90, 99, 107, 116, 137, 144,
                                    145, 154, 164, 175],
    'screens/reports_screen.dart': [25, 38, 45, 53, 59, 76, 92, 127, 136, 146,
                                    157, 161, 198, 218, 226, 239, 247, 259, 270,
                                    297, 298, 314, 315],
    'screens/settings_screen.dart': [151],
    'screens/vitals_screen.dart': [38, 66, 79, 80, 87, 89, 91, 93, 107, 110,
                                   125, 127, 129, 131, 137, 144, 159, 169, 194,
                                   219, 221, 222, 230, 284, 298, 312, 319, 322,
                                   340, 341, 348, 350, 352, 354, 376, 384, 397,
                                   399, 400, 403, 424, 425],
    'screens/voice_assistant_screen.dart': [87, 97, 104, 108, 112, 121, 125,
                                            129, 137, 144, 147],
    'screens/wellbeing_screen.dart': [61, 101, 106, 128, 139, 164, 177, 193,
                                      198, 203, 213, 214, 226, 229, 230, 231,
                                      232, 243],
    'widgets/ai_mood_widgets.dart': [35, 43, 56, 57, 88, 104],
    'widgets/lock_gate.dart': [37, 70, 76, 86],
    'widgets/mood_link.dart': [23, 28],
    'widgets/speak_button.dart': [44, 65, 66],
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
    """End of the adjacent-literal chain that starts at `j` (which is `j`)."""
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
total = 0
for rel, lns in TARGETS.items():
    p = base / rel
    text = p.read_text(encoding='utf-8')

    # 1) add the missing import for `.tr`
    if 'l10n/app_strings.dart' not in text:
        ls = text.splitlines(keepends=True)
        anchor = None
        for i, l in enumerate(ls):
            if re.match(r"^import '\.\./", l):
                anchor = i + 1
                break
        if anchor is None:
            for i, l in enumerate(ls):
                if re.match(r"^import '", l):
                    anchor = i + 1
        ls.insert(anchor, "import '../l10n/app_strings.dart';\n")
        text = ''.join(ls)
        total += 1

    # 2) revert pass-1 insertions on the curated lines only
    ls = text.splitlines(keepends=True)
    offs, pos = [], 0
    for l in ls:
        offs.append(pos)
        pos += len(l)
    for ln in lns:
        idx = ln - 1
        ls[idx] = re.sub(r"(['\"])\.tr\b", r"\1", ls[idx])
    text = ''.join(ls)

    lines = text.splitlines(keepends=True)
    offs, pos = [], 0
    for l in lines:
        offs.append(pos)
        pos += len(l)

    inserts = []
    for ln in lns:
        s0 = offs[ln - 1]
        s1 = s0 + len(lines[ln - 1])
        i = s0
        while i < s1:
            if text[i] in '\'"':
                e = literal_end(text, i)
                if e == -1:
                    break
                if ARABIC.search(INTERP.sub('', text[i:e])):
                    ce = chain_end(text, e)
                    if not re.match(r'\s*\.tr\b', text[ce:]):
                        inserts.append(ce)
                    i = ce
                    continue
                i = e
                continue
            i += 1
    for pos in sorted(set(inserts), reverse=True):
        text = text[:pos] + '.tr' + text[pos:]
        total += 1
    p.write_text(text, encoding='utf-8')
print('imports added + wraps:', total)