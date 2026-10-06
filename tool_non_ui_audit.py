"""Cross-references non-UI Arabic strings against the _en/_zh tables in app_strings.dart."""
import pathlib, re

ROOT = pathlib.Path('c:/tabib2/lib')
ARABIC = re.compile(r'[\u0600-\u06FF]')

def parse_keys(text, table_name):
    m = re.search(re.escape(table_name) + r'\s*=\s*<String,\s*String>\s*\{', text)
    if not m: return {}
    section = text[m.end():]
    end = section.find('\n  };')
    if end == -1: end = section.find('};')
    section = section[:end]
    keys = {}
    for km in re.finditer(r"'((?:[^'\\]|\\.)*)'\s*:\s*'((?:[^'\\\\]|\\.)*)'", section):
        keys[km.group(1)] = km.group(2)
    return keys

ast = (ROOT / 'l10n/app_strings.dart').read_text(encoding='utf-8', errors='ignore')
en_keys = parse_keys(ast, 'static final _en')
zh_keys = parse_keys(ast, 'static final _zh')

SKIP = {'locale/app_locale.dart', 'state/alk_strings.dart', 'services/reminder_content.dart'}
DATA_FILES = {'logic/fat_exercise_data.dart', 'logic/voice_intent.dart', 'services/ai_fallback.dart', 'services/voice_service.dart'}
CATEGORY_KEYS = {'سكري', 'ضغط', 'قلب', 'كبد', 'كوليسترول', 'بدانة'}
MEAL_TYPES = {'فطور', 'غداء', 'عشاء', 'وجبة خفيفة'}
MED_FORMS = {'حبة', 'كبسولة', 'سائل', 'شراب', 'إبرة', 'لصقة', 'قطرة'}

missing_en, missing_zh, in_both = set(), set(), set()

def check_str(val):
    in_en = val in en_keys
    in_zh = val in zh_keys
    if in_en and in_zh: in_both.add(val)
    if not in_en: missing_en.add(val)
    if not in_zh: missing_zh.add(val)

for scan_dir in ['services', 'logic', 'models', 'state']:
    for f in sorted((ROOT / scan_dir).rglob('*.dart')):
        rel = f.relative_to(ROOT).as_posix()
        if rel in SKIP: continue
        if rel in DATA_FILES: continue
        text = f.read_text(encoding='utf-8', errors='ignore')
        if 'voice_intent.dart' in f.name:
            for m in re.finditer(r"(?:=> '([^']*)')", text):
                val = m.group(1)
                if ARABIC.search(val): check_str(val)
        else:
            for m in re.finditer(r"'([^']*[\u0600-\u06FF][^']*)'", text):
                val = m.group(1)
                if val in CATEGORY_KEYS or val in MEAL_TYPES or val in MED_FORMS: continue
                if re.search(r'[\u0600-\u06FF|]', val) and '|' in val and not ARABIC.search(val.replace('|','')): continue
                check_str(val.strip())

print(f"Already in BOTH tables: {len(in_both)}")
print(f"Missing from _en: {len(missing_en)}")
print(f"Missing from _zh: {len(missing_zh)}")
print(f"Missing from BOTH: {len(missing_en & missing_zh)}")
print()
print("=== Missing from BOTH _en and _zh (need new translation entries) ===")
for s in sorted(missing_en & missing_zh):
    print(f'  | {s}')
print()
print("=== Missing from _zh only (in _en but not _zh) ===")
for s in sorted(missing_zh - missing_en):
    print(f'  | {s}')
print()
print("=== Missing from _en only (in _zh but not _en) ===")
for s in sorted(missing_en - missing_zh):
    print(f'  | {s}')
