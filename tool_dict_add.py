"""Adds the missing English/Chinese entries to the static string tables.

Translations are paired *by index* with the sorted missing-source lists written
by tool_collect.py, so the Arabic keys are copied from the source files rather
than retyped. The script aborts if the lists no longer match.
"""
import pathlib

EN = [
    'Oxygen',
    'Quick examples:',
    'Welcome! For example say: log sugar 140, or: open medications.',
    'Add the meal',
    'Condition name',
    'Food or drink name',
    'Unlock ALK to access your health data',
    'Oxygen',
    'Ambulance',
    'Full name',
    'AI is unavailable right now. Add an API key in settings and try again. '
    'The local information above is enough for daily use.',
    'Value',
    'Burger',
    'Meals analysis with the morning medication',
    'Could not open the call on this phone.',
    'Food interaction with the morning medication',
    'Suggested compensating exercises:',
    'White bread',
    'Fried chicken',
    'ID number',
    'Sugar',
    'Pressure',
    'Soda drink',
    'If you feel you are losing control, tell the voice assistant:',
    'Authenticate to unlock ALK',
    'Authenticate to view your health data.',
    'No readings yet',
    'No meals recorded yet',
    'No contacts yet — add one above',
    'No morning medication recorded — add a medication scheduled before '
    '12 noon',
    'This food has no known clear effect on blood sugar, blood pressure or '
    'the heart.',
    'What did you eat today?',
    'Example: white rice, pickles, soda...',
    'Pickles',
    'Relaxed',
    'Hello. I will speak slowly and clearly. Can you hear me well?',
    'Hello! I am ALK, your health companion. How can I help you?',
    "Doctor's notes",
    'Pulse',
    'Calm',
    'This report is an organizational summary of data you entered yourself; '
    'it does not interpret the readings or provide a diagnosis.',
    'This food affects:',
    'These exercises are general and do not replace consulting your doctor.',
    'This is your medications page. I will read the medication names and '
    'times slowly. Tap the speaker button next to any medication to hear it.',
    'This is the nutrition page. I will slowly tell you how breakfast, lunch '
    'and dinner affect the morning medication, with the right amount and a '
    'substitute.',
    'This is the vitals page. Record your blood pressure, sugar or pulse '
    'here. I will read the result slowly and clearly.',
    '• Drink enough water.',
    '• Move every hour, even for a few minutes.',
    '• Get enough sleep.',
    '• Keep your medications at fixed times.',
]

ZH = [
    '快速示例：',
    '欢迎！例如说：记录血糖 140，或者说：打开药物。',
    '添加餐食',
    '病情名称',
    '食物或饮料名称',
    '解锁 ALK 以访问您的健康数据',
    '氧气',
    '救护车',
    '全名',
    '人工智能当前不可用。请在设置中添加 API 密钥后重试。'
    '上面的本地信息足以满足日常使用。',
    '数值',
    '脉搏',
    '汉堡',
    '餐食与早晨药物的分析',
    '无法在此手机上拨打电话。',
    '食物与早晨药物的相互作用',
    '建议的补偿运动：',
    '白面包',
    '炸鸡',
    '身份证号',
    '血糖',
    '血压',
    '碳酸饮料',
    '当您感到将要失控时，请对语音助手说：',
    '请验证以解锁 ALK',
    '请验证以查看您的健康数据。',
    '还没有读数',
    '还没有记录餐食',
    '还没有联系人 — 请在上方添加',
    '没有记录早晨药物 — 请添加中午 12 点前服用的药物',
    '尚不清楚该食物对血糖、血压或心脏有明显影响。',
    '您今天吃了什么？',
    '疲倦',
    '例如：白米饭、泡菜、碳酸饮料……',
    '泡菜',
    '放松',
    '您好。我会慢慢地、清楚地说。您能听清吗？',
    '您好！我是 ALK，您的健康伙伴。我能帮您什么？',
    '平静',
    '本报告是对您自行输入数据的整理摘要，不解释读数也不提供诊断。',
    '这种食物影响：',
    '这些运动是一般性的，不能替代咨询您的医生。',
    '这是您的药物页面。我会慢慢地朗读药物名称和时间。'
    '点击任何药物旁的喇叭按钮即可收听。',
    '这是营养页面。我会慢慢地告诉您早餐、午餐和晚餐如何影响早晨的药物，'
    '以及合适的用量和替代品。',
    '这是测量页面。请在此记录您的血压、血糖或脉搏。我会缓慢清晰地读出结果。',
    '• 喝足够的水。',
    '• 每小时活动一下，哪怕几分钟。',
    '• 保证充足的睡眠。',
    '• 按时规律服药。',
]


def dart(value):
    return "'" + value.replace('\\', '\\\\').replace("'", "\\'") + "'"


def append_entries(text, marker, keys, values):
    head = text.index(marker) + len(marker)
    end = text.index('\n  };', head)
    block = ''.join('    %s: %s,\n' % (dart(k), dart(v))
                    for k, v in zip(keys, values))
    return text[:end] + '\n' + block.rstrip('\n') + text[end:]


base = pathlib.Path('c:/tabib2')
en_keys = base.joinpath('missing_en.txt').read_text(
    encoding='utf-8').splitlines()
zh_keys = base.joinpath('missing_zh.txt').read_text(
    encoding='utf-8').splitlines()
assert len(en_keys) == len(EN), 'EN list drifted: %d vs %d' % (
    len(en_keys), len(EN))
assert len(zh_keys) == len(ZH), 'ZH list drifted: %d vs %d' % (
    len(zh_keys), len(ZH))

p = base / 'lib/l10n/app_strings.dart'
text = p.read_text(encoding='utf-8')
text = append_entries(text, 'static final _en = <String, String>{',
                      en_keys, EN)
text = append_entries(text, 'static final _zh = <String, String>{',
                      zh_keys, ZH)
p.write_text(text, encoding='utf-8')
print('added EN=%d ZH=%d' % (len(EN), len(ZH)))