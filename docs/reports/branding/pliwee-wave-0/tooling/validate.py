"""Structural validation of the four masters, as installed in the repo."""
import hashlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

D = sys.argv[1]
NS = '{http://www.w3.org/2000/svg}'
names = ['pliwee-mark.svg', 'pliwee-mark-mono.svg', 'pliwee-wordmark.svg', 'pliwee-lockup.svg']
fail = 0
for n in names:
    p = f'{D}/{n}'
    raw = open(p, 'rb').read()
    s = raw.decode()
    x = subprocess.run(['xmllint', '--noout', p], capture_output=True)
    root = ET.fromstring(s)
    tags = {e.tag.replace(NS, '') for e in root.iter()}
    hrefs = re.findall(r'href="([^"]*)"', s)
    checks = {
        'xmllint': x.returncode == 0,
        'root svg': root.tag == NS + 'svg',
        'viewBox': 'viewBox' in root.attrib,
        'no base64/data:': 'base64' not in s and 'data:' not in s,
        'no <image>': 'image' not in tags,
        'no <text>/font': not ({'text', 'font', 'tspan'} & tags) and 'font-family' not in s,
        'no <filter>': 'filter' not in tags,
        'hrefs internal': all(h.startswith('#') for h in hrefs),
        'no external url': not re.search(r'https?://(?!www\.w3\.org/2000/svg)', s),
    }
    ok = all(checks.values())
    fail += not ok
    print(f'{n}: viewBox="{root.attrib.get("viewBox")}" width={root.attrib.get("width")} height={root.attrib.get("height")} '
          f'bytes={len(raw)} sha256={hashlib.sha256(raw).hexdigest()} elements={sorted(tags)} -> {"PASS" if ok else checks}')

geo = lambda s: re.findall(r'<path id="([^"]+)" d="([^"]+)"', s)
c = geo(open(f'{D}/pliwee-mark.svg').read())
m = geo(open(f'{D}/pliwee-mark-mono.svg').read())
l = geo(open(f'{D}/pliwee-lockup.svg').read())
print('geometry ids', [i for i, _ in c], 'chars', sum(len(d) for _, d in c))
print('mono geometry == colour geometry:', c == m)
print('lockup geometry == colour geometry:', c == l)
a, b = open(f'{D}/pliwee-mark.svg').read(), open(f'{D}/pliwee-mark-mono.svg').read()
da = a[a.index('<defs>'):a.index('</defs>')]
db = b[b.index('<defs>'):b.index('</defs>')]
print('mono <defs> byte-identical to colour <defs>:', da == db)
sys.exit(fail)
