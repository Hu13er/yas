#!/usr/bin/env python3

import sys

for line in sys.stdin:
    line = line.rstrip("\n")

    # Keep leading whitespace exactly as-is (spaces or tabs).
    i = 0
    while i < len(line) and line[i] in " \t":
        i += 1

    whitespace = line[:i]

    # Input format: <whitespace>\\<text>
    text = line[i + 2:]

    print(f"{line}")
    print(f"{whitespace}// " + "  ".join(text))
    print(f"{whitespace}// " + " ".join(f"{i:02d}" for i in range(len(text))))
