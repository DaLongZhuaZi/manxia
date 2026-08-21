"""Check whether the 3 broken-relative-path files in core are orphans
(not imported by anything, not exported from index.ets, not needed for compilation)."""
import os, subprocess

ROOT = r'F:\DevEcoStudioProject\manxia'
CORE = os.path.join(ROOT, 'manxia-core', 'src', 'main', 'ets')

targets = [
    'PreviewerEnvironmentManager',
    'ImageDescramblerInitializer',
    'ImageInterceptor',
    'JinmantiantangDescrambler',
]

# 1) Check who imports these within core
for t in targets:
    hits = []
    for dp, dirs, fns in os.walk(CORE):
        dirs[:] = [d for d in dirs if d not in {'.git', 'oh_modules', '.hvigor', '.idea', 'build', '.preview'}]
        for fn in fns:
            if not fn.endswith('.ets'):
                continue
            p = os.path.join(dp, fn)
            if fn == t + '.ets':
                continue  # skip self
            try:
                with open(p, encoding='utf-8', errors='replace') as f:
                    for idx, line in enumerate(f, 1):
                        if t in line:
                            rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
                            hits.append((rel, idx, line.strip()[:100]))
            except Exception:
                pass
    print(f'=== core refs to {t}: {len(hits)} ===')
    for h in hits[:8]:
        print(f'  {h[0]}:{h[1]}: {h[2]}')

# 2) Check if core index.ets mentions them
idx = os.path.join(CORE, 'index.ets')
if os.path.isfile(idx):
    with open(idx, encoding='utf-8', errors='replace') as f:
        content = f.read()
    for t in ['ImageProcessing', 'Previewer', 'ImageDescrambler', 'ImageInterceptor', 'GlobalAnimation']:
        found = 'YES' if t in content else 'no'
        print(f'CORE INDEX mentions {t}: {found}')

# 3) Check git-tracked status
r = subprocess.run(
    ['git', 'ls-files',
     'manxia-core/src/main/ets/Framework/ImageProcessing/',
     'manxia-core/src/main/ets/Framework/Managers/PreviewerEnvironmentManager.ets'],
    capture_output=True, text=True, cwd=ROOT, encoding='utf-8', errors='replace'
)
print('=== git-tracked core ImageProcessing + Previewer ===')
print(r.stdout.strip() if r.stdout.strip() else '(none)')

# 4) Check if GlobalAnimationSystem exists anywhere in core source
gas = os.path.join(CORE, 'Framework', 'Animation', 'GlobalAnimationSystem.ets')
print(f'\nGlobalAnimationSystem.ets in core: {"EXISTS" if os.path.isfile(gas) else "MISSING"}')
# Check entry copy
gas_entry = os.path.join(ROOT, 'entry', 'src', 'main', 'ets', 'Framework', 'Animation', 'GlobalAnimationSystem.ets')
print(f'GlobalAnimationSystem.ets in entry: {"EXISTS" if os.path.isfile(gas_entry) else "MISSING"}')

# 5) Check ImageDescramblerRegistry
idr = os.path.join(CORE, 'Framework', 'ImageProcessing', 'ImageDescramblerRegistry.ets')
print(f'ImageDescramblerRegistry.ets in core: {"EXISTS" if os.path.isfile(idr) else "MISSING"}')
idr_entry = os.path.join(ROOT, 'entry', 'src', 'main', 'ets', 'Framework', 'ImageProcessing', 'ImageDescramblerRegistry.ets')
idr_bak = os.path.join(ROOT, 'entry', 'src', 'main', 'ets', 'Framework', 'ImageProcessing.bak', 'ImageDescramblerRegistry.ets')
print(f'ImageDescramblerRegistry.ets in entry (active): {"EXISTS" if os.path.isfile(idr_entry) else "MISSING"}')
print(f'ImageDescramblerRegistry.ets in entry (.bak): {"EXISTS" if os.path.isfile(idr_bak) else "MISSING"}')
