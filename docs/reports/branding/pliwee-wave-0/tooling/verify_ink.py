"""Final-review check: only the wordmark's ink changed since 194f5bf."""
import re
import sys

OLD, NEW = sys.argv[1], sys.argv[2]
rd = lambda d, n: open(f'{d}/{n}').read()
for n in ('pliwee-mark.svg', 'pliwee-mark-mono.svg', 'pliwee-mark-tonal.svg'):
    print(f'{n}: byte-identical to 194f5bf: {rd(OLD, n) == rd(NEW, n)}')
for n in ('pliwee-wordmark.svg', 'pliwee-lockup.svg'):
    old, new = rd(OLD, n), rd(NEW, n)
    reverted = new.replace('<g id="wordmark" fill="#030D25"', '<g id="wordmark" fill="#0B1020"', 1)
    paths_old = re.findall(r'd="([^"]+)"', old)
    paths_new = re.findall(r'd="([^"]+)"', new)
    print(f'{n}: identical once the wordmark fill is reverted: {reverted == old}; '
          f'all {len(paths_new)} path d= identical: {paths_old == paths_new}; '
          f'viewBox {re.search(r"viewBox=\"([^\"]+)\"", new).group(1)} unchanged: '
          f'{re.search(r"viewBox=\"([^\"]+)\"", old).group(1) == re.search(r"viewBox=\"([^\"]+)\"", new).group(1)}')
    print(f'   group fills now: {re.findall(r"<g id=\"(\w+)\" fill=\"([^\"]+)\"", new)}')
lk_old, lk_new = rd(OLD, 'pliwee-lockup.svg'), rd(NEW, 'pliwee-lockup.svg')
print('lockup <use href="#mark"> placement unchanged:',
      re.findall(r'<use href="#mark"[^>]*>', lk_old) == re.findall(r'<use href="#mark"[^>]*>', lk_new))
print('lockup transforms unchanged:', re.findall(r'transform="[^"]+"', lk_old) == re.findall(r'transform="[^"]+"', lk_new))
g = re.findall(r'<path id="([^"]+)" d="([^"]+)"', rd(NEW, 'pliwee-mark.svg'))
h = 0xcbf29ce484222325
for i, d in g:
    for b in (i + '\n' + d + '\n').encode():
        h = ((h ^ b) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
print(f'mark geometry FNV-1a64: {h:#018x} (approved 0xd69183f798800e87: {h == 0xd69183f798800e87})')
mono = rd(NEW, 'pliwee-mark-mono.svg')
sym = re.search(r'<symbol id="markMono".*?</symbol>', mono, re.S).group(0)
print('mono paints:', set(re.findall(r'fill="([^"]+)"', sym)), '| gradients/masks in file:',
      bool(re.search(r'<linearGradient|<radialGradient|<mask', mono)))
