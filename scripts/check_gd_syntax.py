#!/usr/bin/env python3
"""Sanity check sintáctico de archivos .gd."""
import sys
from pathlib import Path

def check(path: Path):
    text = path.read_text(encoding='utf-8')
    stack = []
    pairs = {'(': ')', '[': ']', '{': '}'}
    in_string = False
    string_char = None
    in_line_comment = False
    in_block_comment = False
    line = 1
    col = 0
    errors = []
    i = 0
    while i < len(text):
        c = text[i]
        col += 1
        if c == '\n':
            line += 1
            col = 0
            in_line_comment = False
            i += 1
            continue
        if in_line_comment:
            i += 1
            continue
        if in_block_comment:
            if c == '*' and i + 1 < len(text) and text[i + 1] == '/':
                in_block_comment = False
                col += 1
                i += 2
                continue
            i += 1
            continue
        if in_string:
            if c == '\\' and i + 1 < len(text) and string_char in ('"', "'"):
                col += 1
                i += 2
                continue
            if c == string_char:
                in_string = False
            i += 1
            continue
        if c == '"' or c == "'":
            in_string = True
            string_char = c
            i += 1
            continue
        if c == '/' and i + 1 < len(text) and text[i + 1] == '/':
            in_line_comment = True
            i += 2
            continue
        if c == '/' and i + 1 < len(text) and text[i + 1] == '*':
            in_block_comment = True
            i += 2
            continue
        if c in pairs:
            stack.append((c, line, col))
            i += 1
            continue
        if c in pairs.values():
            if not stack:
                errors.append("linea {}:{} cierra {} sin abrir".format(line, col, c))
            else:
                open_c, open_line, open_col = stack.pop()
                if pairs[open_c] != c:
                    errors.append("linea {}:{} '{}' no cierra '{}' abierto en {}:{}".format(line, col, c, open_c, open_line, open_col))
            i += 1
            continue
        i += 1
    if stack:
        for open_c, open_line, open_col in stack:
            errors.append("{} abierto en {}:{} sin cerrar".format(open_c, open_line, open_col))
    return errors

if __name__ == '__main__':
    root = Path(sys.argv[1])
    only_plugin = '--only-plugin' in sys.argv
    files = sorted(root.rglob('*.gd'))
    failed = 0
    for f in files:
        if only_plugin and 'addons/heren' not in str(f):
            continue
        errs = check(f)
        if errs:
            print('\nFALLA:', f)
            for e in errs[:10]:
                print(' ', e)
            failed += 1
        else:
            print('OK', f)
    print('\n' + ('TODOS OK' if failed == 0 else '{} archivos con error'.format(failed)))
