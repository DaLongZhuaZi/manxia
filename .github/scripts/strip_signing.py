#!/usr/bin/env python3
"""Strip signingConfigs from build-profile.json5 so CI can build an UNSIGNED hap.

背景: DevEco Studio 在本机自动签名后, 会把 signingConfigs 写进
build-profile.json5, 其中 certpath/profile/storeFile 指向开发者本机绝对路径。
CI 容器内这些文件不存在, 构建会直接失败。

本脚本原地移除:
  1. app.signingConfigs 数组(整个键值对);
  2. products[*].signingConfig 字段引用。
剥离后 hvigor 会产出 entry-default-unsigned.hap 等未签名产物。
仅修改 CI 工作副本, 不影响开发者本机的签名构建。

用法: python3 strip_signing.py <build-profile.json5> [--check]
  --check 只检测不落盘, 供本地预览将发生的变更。

实现说明: JSON5 允许注释/尾逗号, 因此不用 json 解析器重建(会丢注释),
而是做"字符串/注释感知"的括号配平删除, 保持其余内容逐字节不变。
"""

import sys


def scan_spans(text):
    """扫描 JSON5 文本, 返回 (code_mask, string_spans, comment_spans)。

    code_mask[i] 为 True 表示下标 i 处于代码位(不在任何字符串字面量或注释内)。
    string_spans 为每个字符串字面量的 (起始下标, 结束下标+1), 含两侧引号。
    """
    n = len(text)
    mask = [True] * n
    str_spans = []
    com_spans = []
    i = 0
    while i < n:
        c = text[i]
        if c in '"\'':
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == c:
                    j += 1
                    break
                j += 1
            j = min(j, n)
            str_spans.append((i, j))
            for k in range(i, j):
                mask[k] = False
            i = j
        elif c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            j = n if j < 0 else j + 1
            com_spans.append((i, j))
            for k in range(i, j):
                mask[k] = False
            i = j
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            com_spans.append((i, j))
            for k in range(i, j):
                mask[k] = False
            i = j
        else:
            i += 1
    return mask, str_spans, com_spans


def value_end(text, mask, colon):
    """colon 指向 ':', 返回该键对应值的结束下标(含闭合括号/引号)。

    从冒号向后跳过空白与注释后, 落点必是 token 起点: 括号(代码位)、字符串
    字面量(引号处 mask 为 False, 但它是合法值)或裸字面量, 均为有效值。
    """
    n = len(text)
    i = colon + 1
    while i < n:
        c = text[i]
        if c in ' \t\r\n':
            i += 1
        elif c == '/' and i + 1 < n and text[i + 1] == '/':
            j = text.find('\n', i)
            i = n if j < 0 else j + 1
        elif c == '/' and i + 1 < n and text[i + 1] == '*':
            j = text.find('*/', i + 2)
            if j < 0:
                raise ValueError('unterminated comment after colon')
            i = j + 2
        else:
            break
    if i >= n:
        raise ValueError('missing value after colon')
    c = text[i]
    if c in '[{':
        depth = 0
        while i < n:
            if not mask[i]:
                i += 1
                continue
            ch = text[i]
            if ch in '[{':
                depth += 1
            elif ch in ']}':
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        raise ValueError('unbalanced brackets in value')
    if c in '"\'':
        j = i + 1
        while j < n:
            if text[j] == '\\':
                j += 2
                continue
            if text[j] == c:
                return j + 1
            j += 1
        raise ValueError('unterminated string value')
    while i < n and text[i] not in ',]}\r\n':
        i += 1
    return i


def tidy_join(text, pos):
    """删除拼接点产生的悬空逗号(,, 或 ,} / ,])。保守处理, 只看紧邻非空白字符。"""
    n = len(text)
    p = pos - 1
    while p >= 0 and text[p] in ' \t\r\n':
        p -= 1
    q = pos
    while q < n and text[q] in ' \t\r\n':
        q += 1
    if p >= 0 and q < n and text[p] == ',' and text[q] in ',}]':
        return text[:p] + text[p + 1:]
    return text


def strip_key(text, key):
    """删除对象层中 "key": <value>(连同尾逗号与前导行缩进)。返回 (新文本, 是否删除)。

    命中条件: 键名是一个完整的字符串字面量 token —— 即命中位置恰好是某个
    string span 的起点且 span 长度等于 marker。注释或字符串值内部出现的同名
    子串(如 "signingConfigs")不会被误命中。
    """
    marker = '"%s"' % key
    n = len(text)
    mask, str_spans, _ = scan_spans(text)
    span_end = {}
    for (s, e) in str_spans:
        span_end[s] = e
    search = 0
    while True:
        k = text.find(marker, search)
        if k < 0:
            return text, False
        e = span_end.get(k)
        if e is not None and e - k == len(marker):
            # 键名之后必须紧跟(仅空白分隔的)冒号, 且冒号位于代码位
            i = e
            colon = -1
            while i < n:
                if mask[i] and text[i] == ':':
                    colon = i
                    break
                if mask[i] and text[i] not in ' \t\r\n':
                    colon = -1
                    break
                i += 1
            if colon >= 0:
                vend = value_end(text, mask, colon)
                j = vend
                while j < n and text[j] in ' \t\r\n':
                    j += 1
                if j < n and text[j] == ',':
                    vend = j + 1
                line_start = text.rfind('\n', 0, k) + 1
                seg_start = line_start if text[line_start:k].strip() == '' else k
                if seg_start == line_start and vend < n and text[vend] == '\n':
                    vend += 1  # 整行删除时连同行尾换行, 避免残留空行
                return tidy_join(text[:seg_start] + text[vend:], seg_start), True
        search = k + 1


def has_key_token(text, key):
    """键名是否仍以完整字符串 token 形式存在(忽略注释与字符串值内的同名子串)。"""
    marker = '"%s"' % key
    _, str_spans, _ = scan_spans(text)
    for (s, e) in str_spans:
        if text[s:e] == marker:
            return True
    return False


def check_balanced(text):
    """括号配平自检(忽略字符串与注释)。"""
    mask, _, _ = scan_spans(text)
    depth = 0
    for idx, c in enumerate(text):
        if not mask[idx]:
            continue
        if c in '[{':
            depth += 1
        elif c in ']}':
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


def main():
    argv = sys.argv[1:]
    check_only = '--check' in argv
    paths = [a for a in argv if a != '--check']
    if not paths:
        print(__doc__)
        return 2
    path = paths[0]
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()

    removed = []
    for key, label in (('signingConfigs', 'app.signingConfigs'),
                       ('signingConfig', 'products[].signingConfig')):
        text, changed = strip_key(text, key)
        if changed:
            removed.append(label)

    if not removed:
        print('strip_signing: nothing to strip (no signing config found) - ok')
        return 0
    if not check_balanced(text):
        print('strip_signing: ERROR - brackets unbalanced after strip, aborting')
        return 1
    if has_key_token(text, 'signingConfigs') or has_key_token(text, 'signingConfig'):
        print('strip_signing: ERROR - signing config still referenced after strip')
        return 1

    if not check_only:
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    print('strip_signing: removed %s -> CI will build UNSIGNED hap' % ', '.join(removed))
    return 0


if __name__ == '__main__':
    sys.exit(main())
