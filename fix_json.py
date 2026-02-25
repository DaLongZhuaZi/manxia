import json, re

p = r'F:\DevEcoStudioProject\manxia\manxia-extensions-source\com.manxia.extension.zh.roumanwu\source.json'
s = open(p, 'r', encoding='utf-8').read()

# Find all invalid JSON escape sequences (single \ followed by non-standard char)
# Valid JSON escapes: " \ / b f n r t u
# We look for \x where x is NOT one of those

i = 0
n = len(s)
bad_positions = []

while i < n:
    if s[i] == '\\':
        if i + 1 < n:
            next_char = s[i+1]
            valid = set('"\\\/bfnrtu')
            if next_char not in valid:
                line_num = s.count('\n', 0, i) + 1
                bad_positions.append((i, line_num, next_char, s[max(0,i-20):i+20]))
        i += 2  # skip escape sequence
    else:
        i += 1

if bad_positions:
    print(f"Found {len(bad_positions)} invalid escape(s):")
    for pos, ln, ch, ctx in bad_positions:
        print(f"  line {ln} pos {pos}: \\{ch!r}  context: {ctx!r}")
else:
    print("No invalid escapes found. Trying full parse...")
    try:
        json.loads(s)
        print("JSON is valid!")
    except Exception as e:
        print("Still invalid:", e)
