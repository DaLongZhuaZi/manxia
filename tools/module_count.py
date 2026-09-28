# -*- coding: utf-8 -*-
"""精确模块计数：只统计各模块 src/main/ets 下 git-tracked .ets（排除 oh_modules/build 镜像）"""
import subprocess
from collections import Counter

ROOT = r'F:\DevEcoStudioProject\manxia'

r = subprocess.run(['git', 'ls-files', '*.ets'], capture_output=True,
                   text=True, encoding='utf-8', errors='replace', cwd=ROOT)
c = Counter()
others = []
for line in r.stdout.splitlines():
    if '/oh_modules/' in line or line.startswith('oh_modules/'):
        continue
    if '/build/' in line:
        continue
    parts = line.split('/')
    if len(parts) > 2 and parts[1] == 'src':
        c[parts[0]] += 1
    else:
        others.append(line)

print('=== 各模块 src/ git-tracked .ets（排除 oh_modules/build）===')
total = 0
MODULES = ['entry', 'manxia-core', 'manxia-theme', 'manxia-novel', 'manxia-network',
           'manxia-source-engine', 'manxia-reader-ui', 'manxia-features-ui', 'manxia-native']
for m in MODULES:
    print(f'  {m:25s} {c[m]}')
    total += c[m]
print(f'  {"TOTAL":25s} {total}')
if others:
    print(f'  其他路径 ({len(others)}):')
    for o in others[:10]:
        print(f'    {o}')
