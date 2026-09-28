"""校验所有 HAR 模块内相对导入（from './...' / '../...'）的目标文件真实存在。
151 处 deep-path self-ref 修复后的回归护栏。
用法: python tools/validate_rel_paths.py
"""
import os
import re

MODULES = [
    'manxia-core', 'manxia-theme', 'manxia-novel', 'manxia-network',
    'manxia-source-engine', 'manxia-reader-ui', 'manxia-features-ui',
]
ROOT = r'F:\DevEcoStudioProject\manxia'
EXCLUDE_DIR = {'.git', 'node_modules', 'oh_modules', '.hvigor', '.idea', 'build', '.dsh-filess'}
FROM_RE = re.compile(r"""from\s+['"]([^'"]+)['"]""")

bad = []
total = 0
for mod in MODULES:
    ets_root = os.path.join(ROOT, mod, 'src', 'main', 'ets')
    if not os.path.isdir(ets_root):
        continue
    for dp, dirs, fns in os.walk(ets_root):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIR and not d.startswith('.bak')]
        for fn in fns:
            if not fn.endswith('.ets') or '.bak' in fn:
                continue
            p = os.path.join(dp, fn)
            try:
                with open(p, encoding='utf-8-sig', errors='replace') as f:
                    lines = f.readlines()
            except OSError:
                continue
            for idx, line in enumerate(lines, 1):
                stripped = line.strip()
                if stripped.startswith('//') or stripped.startswith('*'):
                    continue
                for m in FROM_RE.finditer(line):
                    target = m.group(1)
                    if not target.startswith('.'):
                        continue
                    total += 1
                    resolved = os.path.normpath(os.path.join(os.path.dirname(p), target))
                    if os.path.isfile(resolved + '.ets'):
                        continue
                    if os.path.isfile(os.path.join(resolved, 'index.ets')):
                        continue
                    rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
                    bad.append(f'{rel}:{idx} -> {target}')

print(f'Relative imports checked: {total}')
print(f'BROKEN: {len(bad)}')
for b in bad[:60]:
    print(f'  {b}')
if len(bad) > 60:
    print(f'  ... and {len(bad) - 60} more')
