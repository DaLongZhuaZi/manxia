"""
Scan ALL HAR modules for intra-module deep-path self-references.
Files within the same HAR module must use relative imports, not
manxia_<module>/src/main/ets/... deep paths.

Reports each hit with the correct relative path it should be.
"""
import os, re
from collections import defaultdict, Counter

ROOT = r'F:\DevEcoStudioProject\manxia'

# module dir name -> package underscore name
MODULES = {
    'manxia-core': 'manxia_core',
    'manxia-theme': 'manxia_theme',
    'manxia-novel': 'manxia_novel',
    'manxia-network': 'manxia_network',
    'manxia-source-engine': 'manxia_source_engine',
    'manxia-reader-ui': 'manxia_reader_ui',
    'manxia-features-ui': 'manxia_features_ui',
}

# Reverse map: package name -> module dir
PKG_TO_DIR = {v: k for k, v in MODULES.items()}

EXCLUDE_DIR = {'.git', 'node_modules', 'oh_modules', '.hvigor', '.idea', 'build', '.dsh-filess'}

# Match: from 'manxia_xxx/src/main/ets/...'
DEEP_PATH_RE = re.compile(r"""from\s+['"]((manxia_\w+)/src/main/ets/[^'"]+)['"]""")

self_refs = []
total_hits = 0

for mod_dir, pkg_name in MODULES.items():
    mod_ets_root = os.path.join(ROOT, mod_dir, 'src', 'main', 'ets')
    if not os.path.isdir(mod_ets_root):
        continue

    for dp, dirs, fns in os.walk(mod_ets_root):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIR and not d.startswith('.bak')]
        for fn in fns:
            if not fn.endswith('.ets') or '.bak' in fn:
                continue
            filepath = os.path.join(dp, fn)
            rel = os.path.relpath(filepath, ROOT).replace(os.sep, '/')

            try:
                with open(filepath, 'r', encoding='utf-8', errors='replace') as fh:
                    lines = fh.readlines()
            except Exception:
                continue

            for idx, line in enumerate(lines, 1):
                stripped = line.strip()
                if stripped.startswith('//') or stripped.startswith('*'):
                    continue
                m = DEEP_PATH_RE.search(line)
                if m:
                    import_path = m.group(1)
                    target_pkg = m.group(2)
                    # Self-reference: file in module X imports module X via deep path
                    if target_pkg == pkg_name:
                        # Compute the correct relative path
                        # import_path = manxia_network/src/main/ets/Framework/Network/Foo
                        target_subpath = import_path.split('src/main/ets/')[1]  # Framework/Network/Foo
                        # Current file's dir relative to module ets root
                        file_dir_rel = os.path.relpath(os.path.dirname(filepath), mod_ets_root).replace(os.sep, '/')
                        if file_dir_rel == '.':
                            file_dir_rel = ''
                        # Compute relative path from file dir to target
                        # e.g. file in Framework/Debug, target in Framework/Network
                        # relative = ../Network/Foo
                        rel_to_target = os.path.relpath(
                            os.path.join(mod_ets_root, target_subpath),
                            os.path.dirname(filepath)
                        ).replace(os.sep, '/')
                        if not rel_to_target.startswith('.'):
                            rel_to_target = './' + rel_to_target

                        self_refs.append({
                            'file': rel,
                            'line': idx,
                            'import': import_path,
                            'should_be': rel_to_target,
                            'text': stripped[:160],
                        })
                        total_hits += 1

print(f'=== INTRA-MODULE DEEP-PATH SELF-REFERENCES: {total_hits} ===\n')

by_module = Counter(r['file'].split('/')[0] for r in self_refs)
print('By module:', dict(by_module))
print()

for r in self_refs:
    print(f"{r['file']}:{r['line']}")
    print(f"  current:  {r['import']}")
    print(f"  should:   {r['should_be']}")
    print(f"  text:     {r['text']}")
    print()

if not self_refs:
    print('(none found)')
