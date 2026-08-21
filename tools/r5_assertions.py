#!/usr/bin/env python3
"""R5 static assertions: core out-edge=0, dangling deep paths, module counts."""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MODULE_MAP = {
    'manxia_core': os.path.join(ROOT, 'manxia-core', 'src', 'main', 'ets'),
    'manxia_theme': os.path.join(ROOT, 'manxia-theme', 'src', 'main', 'ets'),
    'manxia_novel': os.path.join(ROOT, 'manxia-novel', 'src', 'main', 'ets'),
    'manxia_network': os.path.join(ROOT, 'manxia-network', 'src', 'main', 'ets'),
    'manxia_source_engine': os.path.join(ROOT, 'manxia-source-engine', 'src', 'main', 'ets'),
    'manxia_reader_ui': os.path.join(ROOT, 'manxia-reader-ui', 'src', 'main', 'ets'),
    'manxia_features_ui': os.path.join(ROOT, 'manxia-features-ui', 'src', 'main', 'ets'),
}

ENTRY_ETS = os.path.join(ROOT, 'entry', 'src', 'main', 'ets')

def collect_ets(d):
    result = []
    for dirpath, dirs, files in os.walk(d):
        dirs[:] = [x for x in dirs if not x.startswith('.')]
        for fn in files:
            if fn.endswith('.ets') and '.bak' not in fn:
                result.append(os.path.join(dirpath, fn))
    return result

# --- Assertion 1: core out-edge = 0 ---
# core must not import from any other manxia_* module (deep or barrel) or from entry via relative paths
UPPER_MODS = ['manxia_theme', 'manxia_novel', 'manxia_network', 'manxia_source_engine',
              'manxia_reader_ui', 'manxia_features_ui']
core_dir = MODULE_MAP['manxia_core']
core_files = collect_ets(core_dir)
core_out_edges = []
# Match deep-path imports to upper modules: from 'manxia_theme/src/main/ets/...'
deep_import_re = re.compile(r"""from\s+['"](?:@manxia/)?(manxia_\w+)/src/main/ets/(.+?)['"]""")
# Match barrel imports: from 'manxia_theme' or from '@manxia/theme'
barrel_import_re = re.compile(r"""from\s+['"]@?manxia/(theme|novel|network|source[_-]engine|reader[_-]ui|features[_-]ui)['"]""")
# Match relative imports to entry: from '../../entry/...' etc.
rel_entry_re = re.compile(r"""from\s+['"](\.\./)+entry/""")

for fpath in core_files:
    with open(fpath, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            for m in deep_import_re.finditer(line):
                mod = m.group(1)
                if mod != 'manxia_core':
                    core_out_edges.append((os.path.relpath(fpath, ROOT), line_num, mod, m.group(0)))
            if barrel_import_re.search(line):
                core_out_edges.append((os.path.relpath(fpath, ROOT), line_num, 'barrel-upper', line.strip()[:120]))
            if rel_entry_re.search(line):
                core_out_edges.append((os.path.relpath(fpath, ROOT), line_num, 'entry(rel)', line.strip()[:120]))

print("=== ASSERTION 1: core out-edge ===")
print(f"core .ets files: {len(core_files)}")
print(f"core out-edges (imports to upper modules/entry): {len(core_out_edges)}")
if core_out_edges:
    for e in core_out_edges:
        print(f"  VIOLATION: {e[0]}:{e[1]} -> {e[2]} | {e[3] if len(e)>3 else ''}")
    print("RESULT: FAIL")
else:
    print("RESULT: PASS (core out-edge = 0)")

# --- Assertion 2: dangling deep paths across entire repo ---
all_ets = collect_ets(ENTRY_ETS)
for mod, d in MODULE_MAP.items():
    all_ets.extend(collect_ets(d))

dangling = []
deep_count = 0
for fpath in all_ets:
    with open(fpath, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            for m in deep_import_re.finditer(line):
                deep_count += 1
                mod = m.group(1)
                rel_path = m.group(2)
                base = MODULE_MAP.get(mod)
                if not base:
                    continue
                target = os.path.join(base, rel_path)
                target_ets = target if target.endswith('.ets') else target + '.ets'
                if not os.path.exists(target_ets) and not os.path.exists(target):
                    dangling.append((os.path.relpath(fpath, ROOT), line_num, mod, rel_path))

print("\n=== ASSERTION 2: dangling deep paths ===")
print(f"Total .ets scanned: {len(all_ets)}")
print(f"Deep-path imports found: {deep_count}")
print(f"Dangling count: {len(dangling)}")
if dangling:
    for d in dangling[:30]:
        print(f"  DANGLING: {d[0]}:{d[1]} -> {d[2]}/{d[3]}")
    print("RESULT: FAIL")
else:
    print("RESULT: PASS (no dangling deep paths)")

# --- Assertion 3: module .ets counts ---
print("\n=== ASSERTION 3: module counts ===")
counts = {}
counts['entry'] = len(collect_ets(ENTRY_ETS))
for mod, d in MODULE_MAP.items():
    counts[mod] = len(collect_ets(d))
for k, v in counts.items():
    print(f"  {k}: {v}")

# --- Summary ---
print("\n=== SUMMARY ===")
all_pass = (len(core_out_edges) == 0) and (len(dangling) == 0)
print(f"ALL PASS: {all_pass}")
sys.exit(0 if all_pass else 1)
