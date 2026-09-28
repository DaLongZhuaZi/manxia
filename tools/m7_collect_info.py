# -*- coding: utf-8 -*-
"""M7 收尾信息采集：远端同步 / 模块计数 / .bak / 临时文件"""
import subprocess, os
from collections import Counter

ROOT = r'F:\DevEcoStudioProject\manxia'
os.chdir(ROOT)

def git(*args):
    r = subprocess.run(['git'] + list(args), capture_output=True,
                       text=True, encoding='utf-8', errors='replace')
    return r.stdout.strip()

print('=== 远端同步状态 ===')
head = git('rev-parse', '--short', 'HEAD')
print(f'本地 HEAD: {head}')
for remote in ['origin', 'nas-backup']:
    count = git('rev-list', '--count', f'{remote}/agent/supporters-json..HEAD')
    print(f'{remote}: 落后 {count} 个提交' if count.isdigit() and int(count) > 0 else f'{remote}: 已同步')

print('\n=== 模块 tracked .ets 计数（git ls-files）===')
r = subprocess.run(['git', 'ls-files', '*.ets'], capture_output=True,
                   text=True, encoding='utf-8', errors='replace')
modules = Counter()
for line in r.stdout.splitlines():
    for m in ['entry', 'manxia-core', 'manxia-theme', 'manxia-novel', 'manxia-network',
              'manxia-source-engine', 'manxia-reader-ui', 'manxia-features-ui', 'manxia-native']:
        if line.startswith(m + '/'):
            modules[m] += 1
            break
    else:
        modules['other'] += 1
for m in sorted(modules):
    print(f'  {m:25s} {modules[m]}')
print(f'  {"合计":25s} {sum(modules.values())}')

print('\n=== git tracked .bak* 文件（排除 oh_modules）===')
r2 = subprocess.run(['git', 'ls-files', '*.bak*'], capture_output=True,
                    text=True, encoding='utf-8', errors='replace')
tracked_baks = [l for l in r2.stdout.splitlines() if l.strip() and 'oh_modules' not in l]
print(f'数量: {len(tracked_baks)}')
for b in tracked_baks:
    print(f'  {b}')

print('\n=== .bak 目录（gitignored，文件系统）===')
EXCLUDE = {'.git', 'node_modules', 'oh_modules', '.hvigor', '.idea', 'build', '.preview', '.dsh-filess'}
bak_dirs = []
bak_untracked = []
for dp, dirs, fns in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in EXCLUDE]
    for d in list(dirs):
        if 'bak' in d.lower():
            rel = os.path.relpath(os.path.join(dp, d), ROOT).replace(os.sep, '/')
            if rel not in bak_dirs:
                bak_dirs.append(rel)
    for fn in fns:
        if fn.lower().endswith('.bak') or fn.lower().endswith('.bak_harmod'):
            rel = os.path.relpath(os.path.join(dp, fn), ROOT).replace(os.sep, '/')
            if 'oh_modules' not in rel and 'build' not in rel and rel not in tracked_baks:
                bak_untracked.append(rel)
print(f'.bak 目录: {len(bak_dirs)}')
for d in sorted(bak_dirs):
    print(f'  {d}/')
print(f'未跟踪 .bak 文件: {len(bak_untracked)}')
for b in sorted(bak_untracked):
    print(f'  {b}')

print('\n=== 临时/stage2 文件 ===')
temps = []
for dp, dirs, fns in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in EXCLUDE]
    for fn in fns:
        if fn.startswith('.tmp_') or fn == 'cleanup-staged-removals.txt' or fn.startswith('stage2-'):
            rel = os.path.relpath(os.path.join(dp, fn), ROOT).replace(os.sep, '/')
            temps.append(rel)
print(f'数量: {len(temps)}')
for t in sorted(temps):
    print(f'  {t}')

print('\n=== KNOWN_ISSUES 状态 ===')
print('#1 FTP/WebDAV ANR: 暂缓（非模块化引入）')
print('#2 EPUB 划线: 已修复（M47 门禁确认）')
print('#3 MOBI: 已修复（M48），release 编译通过 -> 门禁确认')
print('#4 传书鉴权: 已修复，release 编译通过 -> 门禁确认')
