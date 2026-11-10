import sqlite3, sys, re, uuid
src, dst = sys.argv[1], sys.argv[2]
import shutil; shutil.copy(src, dst)
c = sqlite3.connect(dst); c.execute('PRAGMA foreign_keys=OFF')
tables = [r[0] for r in c.execute("select name from sqlite_master where type='table' and name not like 'sqlite_%'")]
ids = {t: str(uuid.uuid5(uuid.NAMESPACE_URL, 'fieldos-fixture/'+t)) for t in tables}
def checks(sql):
    return sql or ''
ok, fail = [], []
for t in tables:
    sql = c.execute("select sql from sqlite_master where name=?", (t,)).fetchone()[0]
    cols = c.execute(f'pragma table_info("{t}")').fetchall()
    fks = {r[3]: r[2] for r in c.execute(f'pragma foreign_key_list("{t}")')}
    vals = {}
    for cid, name, typ, notnull, dflt, pk in cols:
        typ = (typ or '').upper()
        m = re.search(r'"?%s"?\s+[A-Z ]*?CHECK\s*\(\s*"?%s"?\s+IN\s*\(\s*\'([^\']*)\'' % (re.escape(name), re.escape(name)), sql)
        if m: vals[name] = m.group(1); continue
        if name in fks: vals[name] = ids.get(fks[name], 'x'); continue
        if pk and typ == 'INTEGER': continue
        if name == 'id': vals[name] = ids[t]; continue
        if 'INT' in typ:
            if re.search(r'"%s"\s+INTEGER[^,]*CHECK\s*\("%s"\s+IN\s*\(0,\s*1\)\)' % (name, name), sql): vals[name] = 1
            else: vals[name] = 1762732800
        elif 'REAL' in typ or 'NUM' in typ: vals[name] = 12.5
        elif name.endswith('_id'): vals[name] = str(uuid.uuid5(uuid.NAMESPACE_URL, 'ref/'+name))
        elif name.endswith('_on') or name.endswith('date') or name in ('day','week_start','week_of','month'): vals[name] = '2026-11-01'
        elif 'json' in name or name in ('payload','data','meta','lines','items'): vals[name] = '{}'
        else: vals[name] = f'{t}.{name}'
    names = ','.join(f'"{k}"' for k in vals); marks = ','.join('?' for _ in vals)
    try:
        c.execute(f'insert into "{t}" ({names}) values ({marks})', list(vals.values())); ok.append(t)
    except Exception as e:
        fail.append((t, str(e)))
c.commit(); c.execute('VACUUM'); c.close()
print('seeded', len(ok), 'of', len(tables))
for f in fail: print('FAIL', f)
