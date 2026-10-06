import pathlib, re
root = pathlib.Path('c:/tabib2/lib')
files = list(root.rglob('*.dart'))
def literal_end(s, start):
    """Index past the closing quote of the literal opening at `start`."""
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


def comment_spans(text):
    """(start, end) of comments, ignoring markers inside string literals."""
    spans, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in '\'"':
            e = literal_end(text, i)
            i = n if e == -1 else e
            continue
        if c == '/' and i + 1 < n and text[i + 1] in '/*':
            if text[i + 1] == '/':
                j = text.find('\n', i)
                j = n if j == -1 else j
            else:
                j = text.find('*/', i)
                j = n if j == -1 else j + 2
            spans.append((i, j))
            i = j
            continue
        i += 1
    return spans


def chain_strings(text, a):
    """Joined source of the adjacent-literal chain starting at `a`."""
    parts, k = [], a
    while k < len(text):
        while k < len(text) and text[k] in ' \t\r\n':
            k += 1
        if k < len(text) and text[k] in '\'"':
            e = literal_end(text, k)
            if e == -1:
                break
            parts.append(text[k + 1:e - 1])
            k = e
            continue
        break
    return ''.join(parts), k
# 1) .tr sources: 'xxx'.tr and "xxx".tr — adjacent literals are concatenated
#    by Dart, so a wrapped string ('a ' 'b'.tr) counts as one source.
pat_tr = re.compile(r"""((?:(?:'[^'\n]*'|"[^"\n]*")\s*)+)\.tr\b""")
pat_chain = re.compile(r"""'([^'\n]*)'|"([^"\n]*)\"""")
# 2) const Text / Text / labelText / hintText / tooltip / title with Arabic literal (even without .tr)
pat_lit = re.compile(r"""['\"]([^'\"\n]*?[\u0600-\u06FF][^'\"\n]*?)['\"]""")
tr_sources=set()
all_lit=set()
where={}
for f in files:
    t=f.read_text(encoding='utf-8',errors='ignore')
    cspans = comment_spans(t)
    j = 0
    while j < len(t):
        if t[j] in '\'"':
            e = literal_end(t, j)
            if e == -1:
                break
            if not any(a <= j < b for a, b in cspans):
                joined, end = chain_strings(t, j)
                if re.match(r'\s*\.tr\b', t[end:]):
                    joined = joined.strip()
                    if re.search(r'[\u0600-\u06FF]', joined):
                        tr_sources.add(joined)
                        where.setdefault(joined, []).append(
                            '%s:%d' % (f.relative_to(root.parent).as_posix(),
                                       t[:j].count('\n') + 1))
                j = end
                continue
        j += 1
    for m in pat_lit.finditer(t):
        v=m.group(1).strip()
        if len(v)>=2:
            all_lit.add(v)
out=[]
out.append(f"TR_SOURCES={len(tr_sources)} LIT_TOTAL={len(all_lit)}")
pathlib.Path('c:/tabib2/all_tr.txt').write_text('\n'.join(sorted(tr_sources)),encoding='utf-8')
pathlib.Path('c:/tabib2/all_lit.txt').write_text('\n'.join(sorted(all_lit)),encoding='utf-8')
# check dict keys in app_strings (both `static const` and `static final` forms)
t=(root/'l10n/app_strings.dart').read_text(encoding='utf-8')
def keys_of(name):
    m=re.search(re.escape(name)+r'\s*=\s*<String,\s*String>\s*\{',t)
    if not m: m=re.search(re.escape(name)+r'\s*=\s*\{',t)
    sec=t[m.end():].split('\n  };')[0]
    return set(re.findall(r"""'((?:[^'\\]|\\.)+)'\s*:""",sec))
# 3) Arabic literals in UI files that are NOT routed through `.tr`
pat_chain_any = re.compile(r"""((?:(?:'[^'\n]*'|"[^"\n]*")\s*)+)""")
ui=[]
for f in files:
    rel=f.relative_to(root).as_posix()
    if not (rel.startswith('screens/') or rel.startswith('widgets/')):
        continue
    tf=f.read_text(encoding='utf-8',errors='ignore')
    for m in pat_chain_any.finditer(tf):
        if re.match(r'\s*\.tr\b', tf[m.end():]):
            continue
        v=''.join(a or b for a,b in pat_chain.findall(m.group(1))).strip()
        if not re.search(r'[\u0600-\u06FF]', v):
            continue
        line=tf[:m.start()].count('\n')+1
        ui.append('%s:%d: %s' % (rel, line, v))
pathlib.Path('c:/tabib2/ui_literals.txt').write_text('\n'.join(ui),encoding='utf-8')
out.append(f"UI_ARABIC_LITERALS_WITHOUT_TR={len(ui)}")

en_keys=keys_of('static final _en')
zh_keys=keys_of('static final _zh')
# duplicate keys inside a map would silently shadow an earlier translation
def dupes(name):
    mm=re.search(re.escape(name)+r'\s*=\s*<String,\s*String>\s*\{',t)
    sec=t[mm.end():].split('\n  };')[0]
    ks=re.findall(r"""'((?:[^'\\]|\\.)+)'\s*:""",sec)
    seen={}
    for k in ks:
        seen[k]=seen.get(k,0)+1
    return sorted(k for k,c in seen.items() if c>1)
out.append("DUP_EN=%d DUP_ZH=%d" % (len(dupes('static final _en')),len(dupes('static final _zh'))))
for k in dupes('static final _en'):
    out.append("DUP_EN_KEY: "+k)
for k in dupes('static final _zh'):
    out.append("DUP_ZH_KEY: "+k)
# common pre-translated strings (must exist in both tables)
m=re.search(r'static const List<String> _commonStrings\s*=\s*\[',t)
common=set(re.findall(r"""'((?:[^'\\]|\\.)+)'""", t[m.end():].split('\n  ];')[0]))
out.append(f"COMMON={len(common)}")
out.append(f"EN_KEYS={len(en_keys)} ZH_KEYS={len(zh_keys)}")
out.append(f"MISSING_EN_FROM_TR={len([s for s in tr_sources if s not in en_keys])}")
out.append(f"MISSING_ZH_FROM_TR={len([s for s in tr_sources if s not in zh_keys])}")
for s in sorted(tr_sources):
    if s not in en_keys:
        out.append("NO_EN: "+s+"   @ "+', '.join(where[s][:3]))
out.append("----")
for s in sorted(tr_sources):
    if s not in zh_keys:
        out.append("NO_ZH: "+s+"   @ "+', '.join(where[s][:3]))
# Sources that build their text at runtime (interpolation) cannot be matched by
# an exact-key table lookup - they are translated by AutoTranslateService.
def dyn(s):
    return re.search(r'\$\{|\$[A-Za-z_]', s) is not None
stat_en=[s for s in tr_sources if s not in en_keys and not dyn(s)]
stat_zh=[s for s in tr_sources if s not in zh_keys and not dyn(s)]
pathlib.Path('c:/tabib2/missing_en.txt').write_text('\n'.join(sorted(stat_en)),encoding='utf-8')
pathlib.Path('c:/tabib2/missing_zh.txt').write_text('\n'.join(sorted(stat_zh)),encoding='utf-8')
out.append("----")
out.append("STATIC_MISSING_EN=%d DYN_RUNTIME_EN=%d" % (
    len(stat_en), len([s for s in tr_sources if s not in en_keys and dyn(s)])))
out.append("STATIC_MISSING_ZH=%d DYN_RUNTIME_ZH=%d" % (
    len(stat_zh), len([s for s in tr_sources if s not in zh_keys and dyn(s)])))
out.append("----")
out.append(f"MISSING_EN_FROM_COMMON={len([s for s in common if s not in en_keys])}")
out.append(f"MISSING_ZH_FROM_COMMON={len([s for s in common if s not in zh_keys])}")
for s in sorted(common):
    if s not in en_keys or s not in zh_keys:
        out.append("NO_COMMON: %s   en=%s zh=%s" % (s, s in en_keys, s in zh_keys))
pathlib.Path('c:/tabib2/coverage_report.txt').write_text('\n'.join(out),encoding='utf-8')
print(out[0], out[1], out[2], out[3])
