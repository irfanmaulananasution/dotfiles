#!/usr/bin/env python3
"""Validate skills against the Agent Skills spec as OpenCode enforces it.

OpenCode (and agentskills.io) require, among other things, that a skill's
frontmatter `name` MATCHES the directory that holds its SKILL.md. Hermes is more
lenient, so a skill can work in Hermes and be silently ignored by OpenCode.

Usage: validate-skills.py [library_dir]   (default: ../library next to this script)
Exit:  0 = all valid, 1 = at least one problem (details on stdout)
"""
import os
import re
import sys

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
DEFAULT_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "library")


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    return m.group(1) if m else ""


def scalar(fm, key):
    """Read a top-level scalar, joining folded/quoted continuation lines."""
    lines = fm.splitlines()
    for i, line in enumerate(lines):
        if line.startswith(key + ":"):
            val = line.split(":", 1)[1].strip().strip('"').strip("'")
            j = i + 1
            while j < len(lines) and lines[j][:1] in (" ", "\t"):
                val += " " + lines[j].strip()
                j += 1
            return val
    return ""


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LIB
    root = os.path.normpath(root)
    if not os.path.isdir(root):
        print(f"  [WARN] library dir not found: {root}")
        return 1

    skills = []
    for entry in sorted(os.listdir(root)):
        d = os.path.join(root, entry)
        if os.path.isdir(d) and os.path.isfile(os.path.join(d, "SKILL.md")):
            skills.append((entry, d))

    if not skills:
        print("  [ OK ] library is empty (nothing to validate)")
        return 0

    problems = 0
    for dirname, d in skills:
        text = open(os.path.join(d, "SKILL.md"), encoding="utf-8", errors="replace").read()
        fm = frontmatter(text)
        name = scalar(fm, "name")
        desc = scalar(fm, "description")

        errs = []
        if not fm:
            errs.append("no YAML frontmatter")
        else:
            if name != dirname:
                errs.append(f"frontmatter name is '{name}' — must equal the directory name")
            elif not NAME_RE.match(name):
                errs.append(f"name '{name}' is not valid (^[a-z0-9]+(-[a-z0-9]+)*$)")
            if not desc:
                errs.append("missing description")
            elif len(desc) > 1024:
                errs.append(f"description is {len(desc)} chars (max 1024)")

        if errs:
            problems += len(errs)
            for e in errs:
                print(f"  [FAIL] {dirname}: {e}")
        else:
            print(f"  [ OK ] {dirname}")

    if problems:
        print(f"  [WARN] {problems} problem(s) — OpenCode would ignore these skills")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
