"""
Fix invalid JSON escape sequences in getMangaDetail and getChapterList code fields.
In JSON strings, \s \d \b are invalid (not recognised escape sequences).
They must be \\s \\d \\b so the JSON parser produces \s \d \b in the JS code.
"""

p = r'F:\DevEcoStudioProject\manxia\manxia-extensions-source\com.manxia.extension.zh.roumanwu\source.json'

s = open(p, 'r', encoding='utf-8').read()
original = s

# Helper: replace only within the "code" field of getMangaDetail (line 184)
# and getChapterList (line 207).
# Strategy: find the two code strings and fix them individually.

def fix_code_field(code_str):
    """Fix bare \s, \d, \b inside a JSON-string code value (already unquoted)."""
    import re
    # Replace \s, \d, \b, \w etc. (single backslash + letter that is not a valid JSON escape)
    # Valid JSON escapes after \: " \ / b f n r t u
    # But \b in JSON = backspace, NOT word boundary. For regex we want \\b.
    # So we fix: \s -> \\s, \d -> \\d, \b -> \\b (all single-backslash regex metaclasses)
    result = []
    i = 0
    n = len(code_str)
    while i < n:
        ch = code_str[i]
        if ch == '\\' and i + 1 < n:
            nch = code_str[i + 1]
            if nch in ('s', 'd', 'w', 'W', 'S', 'D', 'b', 'B', 'p', 'k'):
                # These are NOT valid JSON escapes - they're regex metaclasses
                # Need to double the backslash
                result.append('\\\\')
                result.append(nch)
                i += 2
                continue
        result.append(ch)
        i += 1
    return ''.join(result)

# Find getMangaDetail code field
import re

def fix_workflow_code(json_text, workflow_name):
    """Fix the code field(s) within a named workflow."""
    # Find the workflow block
    pattern = rf'("{workflow_name}"\s*:\s*\{{.*?\}}(?:\s*\}}))'
    # Actually easier: find each "code": "..." in the file and fix
    # We'll do it differently: parse line by line for the problem lines

    # Find all "code": "..." values and fix invalid escapes within them
    # Use a simple state machine to find JSON string values for "code" keys
    result = []
    i = 0
    n = len(json_text)
    
    while i < n:
        # Look for "code": "
        if json_text[i:i+8] == '"code": ':
            result.append(json_text[i:i+8])
            i += 8
            if i < n and json_text[i] == '"':
                # Start of JSON string value
                result.append('"')
                i += 1
                # Read until end of string, fixing escapes
                while i < n:
                    c = json_text[i]
                    if c == '\\' and i + 1 < n:
                        nc = json_text[i+1]
                        if nc == '"':
                            result.append('\\"')
                            i += 2
                        elif nc == '\\':
                            result.append('\\\\')
                            i += 2
                        elif nc in ('/', 'b', 'f', 'n', 'r', 't'):
                            result.append('\\' + nc)
                            i += 2
                        elif nc == 'u':
                            result.append('\\u')
                            i += 2
                        else:
                            # Invalid JSON escape - double the backslash
                            result.append('\\\\')
                            result.append(nc)
                            i += 2
                    elif c == '"':
                        result.append('"')
                        i += 1
                        break
                    else:
                        result.append(c)
                        i += 1
            continue
        result.append(json_text[i])
        i += 1
    
    return ''.join(result)

s_fixed = fix_workflow_code(s, 'any')

import json
try:
    json.loads(s_fixed)
    print("Fixed JSON is valid!")
    open(p, 'w', encoding='utf-8').write(s_fixed)
    print("File written successfully.")
    
    # Count changes
    changes = sum(1 for a, b in zip(s, s_fixed) if a != b)
    print(f"Characters changed: ~{len(s_fixed) - len(s)} net, pass-through differences exist")
except json.JSONDecodeError as e:
    print(f"Still invalid after fix: {e}")
    # Show context
    i = e.pos
    print('Context:', repr(s_fixed[i-40:i+40]))
