import pathlib, re
root = pathlib.Path('c:/tabib2/lib')
rows=[]
cur=None
for line in pathlib.Path('c:/tabib2/ui_literals.txt').read_text(encoding='utf-8').splitlines():
    m=re.match(r'([^:]+):(\d+): (.*)$', line)
    if not m: continue
    f,ln,val=m.group(1),int(m.group(2)),m.group(3)
    if f!=cur:
        rows.append('\n===== '+f+' =====')
        cur=f
    src=(root/f).read_text(encoding='utf-8').splitlines()
    prev=' | '.join(s.strip() for s in src[max(0,ln-3):ln-1])
    here=src[ln-1].strip()
    nxt=' | '.join(s.strip() for s in src[ln:ln+2])
    rows.append('%d  VAL=%s\n     PREV: %s\n     HERE: %s\n     NEXT: %s' % (ln,val,prev,here,nxt))
pathlib.Path('c:/tabib2/ui_context.txt').write_text('\n'.join(rows),encoding='utf-8')
print('rows',len(rows))