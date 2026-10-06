"""One-off migration: route hardcoded Arabic UI literals through `.tr`.

Each entry lists the 1-based line numbers (from ui_literals.txt) that hold a
user-visible Arabic literal. Data keys / comparisons / comments were filtered
out by hand. A same-line `const` before the literal is dropped because a getter
call is not a const expression.
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
    """Index just past the closing quote of the literal opening at `start`."""
    q = s[start]
    i = start + 1
    while i < len(s):
        c = s[i]
        if c == '\\':
            i += 2
            continue
        if c == '$' and i + 1 < len(s) and s[i + 1] == '{':
            depth = 0
            j = i + 1
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


def wrap_line(line):
    """Appends `.tr` to every Arabic-bearing literal of `line`."""
    out = []
    i = 0
    while i < len(line):
        if line[i] not in '\'"':
            out.append(line[i])
            i += 1
            continue
        end = literal_end(line, i)
        if end == -1:
            out.append(line[i])
            i += 1
            continue
        text = line[i:end]
        plain = INTERP.sub('', text)
        after = line[end:]
        already = re.match(r'\s*\.tr\b', after)
        if ARABIC.search(plain) and not already:
            out.append(text + '.tr')
        else:
            out.append(text)
        i = end
    return ''.join(out)


changed = 0
sources = set()
for rel, lns in TARGETS.items():
    p = pathlib.Path('c:/tabib2/lib') / rel
    lines = p.read_text(encoding='utf-8').splitlines(keepends=True)
    for ln in lns:
        orig = lines[ln - 1]
        new = wrap_line(orig)
        if new == orig:
            print('NOCHANGE %s:%d' % (rel, ln))
            continue
        # drop the `const` that immediately precedes the wrapped expression
        first = min((new.find("'"), new.find('"'))) if "'" in new or '"' in new else -1
        if first > 0:
            idx = new.rfind('const ', 0, first)
            if idx != -1:
                new = new[:idx] + new[idx + 6:]
        for m in re.finditer(r"[\"'](.+?)[\"']\.tr", new):
            sources.add(m.group(1))
        lines[ln - 1] = new
        changed += 1
    p.write_text(''.join(lines), encoding='utf-8')
print('wrapped lines:', changed)