"""Audit non-UI Arabic strings: check against _en/_zh tables, output missing entries."""
import pathlib, re

ROOT = pathlib.Path('c:/tabib2/lib')
ARABIC = re.compile(r'[\u0600-\u06FF]')

def parse_table_keys(text, table_name):
    m = re.search(re.escape(table_name) + r'\s*=\s*<String,\s*String>\s*\{', text)
    if not m: return set()
    section = text[m.end():]
    end = section.find('\n  };')
    if end == -1: end = section.find('};')
    section = section[:end]
    keys = set()
    for km in re.finditer(r"'((?:[^'\\]|\\.)*)'\s*:\s*'", section):
        keys.add(km.group(1))
    return keys

ast = (ROOT / 'l10n/app_strings.dart').read_text(encoding='utf-8', errors='ignore')
en_keys = parse_table_keys(ast, 'static final _en')
zh_keys = parse_table_keys(ast, 'static final _zh')

# Strings that are data values or matching keys (NOT display)
DATA_VALUES = {
    'عام', 'قلب', 'سكري', 'ضغاط',  # MedicationCategory
    'حبة', 'كبسولة', 'سائل', 'شراب', 'إبرة', 'لصقة', 'قطرة',  # MedicationForm
    'فطور', 'غداء', 'عشاء', 'وجبة خفيفة',  # FoodMealType
    'active', 'quiet', 'unsupported', 'denied', 'disabled',  # ReminderStatus (English)
    'pressure', 'sugar', 'pulse', 'spo2',  # VitalKind (English)
    'sugar', 'pressure', 'heart',  # FoodImpactKind (English)
    'none', 'low', 'medium', 'high',  # MealRisk (English)
    'none', 'ok', 'warn', 'over',  # FatAdviceLevel (English)
    'taken', 'missed', 'as-needed',  # DoseEventType (English)
}

# Files to skip (already have own translation mechanism)
SKIP = {'locale/app_locale.dart', 'state/alk_strings.dart', 'services/reminder_content.dart'}

# Files to skip entirely (data keys, regex patterns, or AI prompts)
SKIP_ENTIRELY = {
    'logic/fat_exercise_data.dart',      # exercise/food names are MAP KEYS
    'services/ai_fallback.dart',          # AI prompts
    'services/voice_service.dart',        # TTS punctuation
}

# Per-file: extract user-visible Arabic string literals
def extract_from_file(text):
    """Extract Arabic string literals, handling multi-line adjacent chains."""
    results = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] in '\'"':
            q = text[i]
            j = i + 1
            parts = []
            while j < n:
                if text[j] == '\\':
                    if j + 1 < n:
                        parts.append(text[j:j+2])
                        j += 2
                    else:
                        j += 1
                    continue
                if text[j] == q:
                    j += 1
                    # Check for adjacent string literal
                    k = j
                    while k < n and text[k] in ' \t\r\n':
                        k += 1
                    if k < n and text[k] in '\'"':
                        # Adjacent string - continue collecting
                        q = text[k]
                        j = k + 1
                        continue
                    break
                parts.append(text[j])
                j += 1
            raw = ''.join(parts)
            # Check for interpolation
            if '$' in raw:
                # Extract just the Arabic parts for table lookup
                # The dynamic string itself will be handled by .tr fallback
                results.append(('DYNAMIC', raw))
            elif ARABIC.search(raw):
                val = raw.strip()
                if len(val) >= 2:  # skip very short fragments like '،'
                    results.append(('STATIC', val))
            i = j
        else:
            i += 1
    return results

all_static = set()
all_dynamic = set()

for scan_dir in ['services', 'logic', 'models', 'state']:
    for f in sorted((ROOT / scan_dir).rglob('*.dart')):
        rel = f.relative_to(ROOT).as_posix()
        if rel in SKIP or rel in SKIP_ENTIRELY: continue
        if 'voice_intent.dart' in f.name: continue  # handled separately
        text = f.read_text(encoding='utf-8', errors='ignore')
        for kind, val in extract_from_file(text):
            if val in DATA_VALUES: continue
            if '|' in val and not ARABIC.search(val.replace('|', '')): continue  # regex
            if kind == 'STATIC':
                all_static.add(val)
            else:
                all_dynamic.add(val)

# Handle voice_intent.dart separately (only screenLabel and vitalLabel returns)
vi_text = (ROOT / 'logic/voice_intent.dart').read_text(encoding='utf-8', errors='ignore')
for m in re.finditer(r"=>\s*'([^']*)'", vi_text):
    val = m.group(1)
    if ARABIC.search(val):
        all_static.add(val)

# Check which are already in the tables
missing_both = set()
missing_en = set()
missing_zh = set()
in_both = set()

for s in all_static:
    in_en = s in en_keys
    in_zh = s in zh_keys
    if in_en and in_zh:
        in_both.add(s)
    elif in_en and not in_zh:
        missing_zh.add(s)
    elif not in_en and in_zh:
        missing_en.add(s)
    else:
        missing_both.add(s)

print(f"Total unique static Arabic strings from non-UI: {len(all_static)}")
print(f"  Already in BOTH tables: {len(in_both)}")
print(f"  Missing from _en only: {len(missing_en)}")
print(f"  Missing from _zh only: {len(missing_zh)}")
print(f"  Missing from BOTH: {len(missing_both)}")
print(f"Total dynamic strings (need .tr fallback): {len(all_dynamic)}")
print()

print("=== Missing from _en only (add to _en table) ===")
for s in sorted(missing_en): print(f'  | {s}')
print()

print("=== Missing from _zh only (add to _zh table) ===")
for s in sorted(missing_zh): print(f'  | {s}')
print()

print("=== Missing from BOTH (need new EN/ZH entries) ===")
for s in sorted(missing_both): print(f'  | {s}')
