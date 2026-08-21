import os, re, sys

ROOT = r'F:\DevEcoStudioProject\manxia'
EXCLUDE_DIR = {'.git', 'node_modules', 'oh_modules', '.hvigor', '.idea', 'build', '.dsh-filess'}
EXCLUDE_FILE_SUB = ('.bak',)

patterns = {
    'inline_obj_type': re.compile(r'\?\s*:\s*\{$'),
    'destruct_decl': re.compile(r'\b(?:const|let)\s+\{[^}]+\}\s*=\s*'),
    'obj_spread': re.compile(r'\.\.\.\w+[,;}]\s*$'),
    'dataReceiveErr': re.compile(r"['\"]dataReceiveErr['\"]"),
}

hits = {k: [] for k in patterns}
total_files = 0
for dp, dirs, fns in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in EXCLUDE_DIR and not d.startswith('.bak')]
    for fn in fns:
        if not fn.endswith('.ets') or any(s in fn for s in EXCLUDE_FILE_SUB):
            continue
        p = os.path.join(dp, fn)
        rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
        if '/oh_modules/' in rel or '/.bak/' in rel:
            continue
        total_files += 1
        try:
            with open(p, 'r', encoding='utf-8', errors='replace') as fh:
                lines = fh.readlines()
        except Exception:
            continue
        for idx, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith('//') or stripped.startswith('*'):
                continue
            for name, rx in patterns.items():
                if rx.search(line):
                    hits[name].append((rel, idx, stripped[:120]))

for name, lst in hits.items():
    print(f'=== {name}: {len(lst)} ===')
    for rel, idx, txt in lst[:40]:
        print(f'  {rel}:{idx}: {txt}')
    if len(lst) > 40:
        print(f'  ... and {len(lst)-40} more')
print(f'\nScanned {total_files} .ets files (excl. oh_modules/.bak)')
