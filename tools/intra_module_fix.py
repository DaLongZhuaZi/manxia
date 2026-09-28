"""
Fix all intra-module deep-path self-references by replacing them
with correct relative paths. Preserves BOM and original quote char.
"""
import os, re

ROOT = r'F:\DevEcoStudioProject\manxia'

MODULES = {
    'manxia-core': 'manxia_core',
    'manxia-theme': 'manxia_theme',
    'manxia-novel': 'manxia_novel',
    'manxia-network': 'manxia_network',
    'manxia-source-engine': 'manxia_source_engine',
    'manxia-reader-ui': 'manxia_reader_ui',
    'manxia-features-ui': 'manxia_features_ui',
}

EXCLUDE_DIR = {'.git', 'node_modules', 'oh_modules', '.hvigor', '.idea', 'build', '.dsh-filess'}

# Match: from 'manxia_xxx/src/main/ets/...' or from "manxia_xxx/src/main/ets/..."
DEEP_PATH_RE = re.compile(r"""from\s+(['"])((manxia_\w+)/src/main/ets/[^'"]+)\1""")

fixed_count = 0
file_count = 0

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

            # Read with BOM detection
            with open(filepath, 'rb') as bf:
                raw = bf.read()
            has_bom = raw.startswith(b'\xef\xbb\xbf')
            content = raw.decode('utf-8-sig', errors='replace')

            counter = [0]

            def replacer(m):
                quote = m.group(1)
                full_path = m.group(2)   # manxia_network/src/main/ets/Framework/Network/Foo
                target_pkg = m.group(3)  # manxia_network

                # Only fix self-references (same module)
                if target_pkg != pkg_name:
                    return m.group(0)

                # Compute relative path from this file's dir to the target file
                target_subpath = full_path.split('src/main/ets/')[1]  # Framework/Network/Foo
                target_full = os.path.join(mod_ets_root, target_subpath)
                file_dir = os.path.dirname(filepath)
                rel_path = os.path.relpath(target_full, file_dir).replace(os.sep, '/')
                if not rel_path.startswith('.'):
                    rel_path = './' + rel_path

                counter[0] += 1
                return f"from {quote}{rel_path}{quote}"

            new_content = DEEP_PATH_RE.sub(replacer, content)

            if counter[0] > 0:
                # Write back, preserving BOM if original had it
                out = new_content.encode('utf-8')
                if has_bom:
                    out = b'\xef\xbb\xbf' + out
                with open(filepath, 'wb') as fh:
                    fh.write(out)
                fixed_count += counter[0]
                file_count += 1
                rel = os.path.relpath(filepath, ROOT).replace(os.sep, '/')
                print(f'  FIXED ({counter[0]}): {rel}')

print(f'\n=== DONE: {fixed_count} replacements in {file_count} files ===')
