#!/usr/bin/env python3
"""Fail on any qmllint warning that scripts/qmllint-baseline.txt does not list.

qmllint cannot see Quickshell's or the Omarchy shell's types, so the QML files carry hundreds of standing "unqualified
access" warnings; what matters is a new one, which is how a misspelt id, or a property that no longer exists, shows up before
the shell is restarted. An entry is the file, the warning's category and, for an unqualified access, the name itself, so
using a known name again adds nothing and a new name fails. (The same idea as StartBar's qmllint-check.js.)

  scripts/lint-qml.py            check
  scripts/lint-qml.py --update   rewrite the baseline

Some warnings are bugs, never noise: a property that shadows one of Item's own (`data`, `state`, `children`), an id that shadows
a property, a property bound twice. They are not baselineable: they fail the check even when the baseline lists them, and
--update refuses to write while one is present. (A property named `data` once got through a blind --update.)
"""
import json
import os
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(os.environ.get("LINT_QML_ROOT") or pathlib.Path(__file__).resolve().parent.parent)
baseline_path = root / "scripts" / "qmllint-baseline.txt"
files = sorted(p.name for p in root.glob("*.qml"))
NEVER_BASELINE = {"property-override", "id-shadows-member", "duplicate-property-binding"}


def find_qmllint():
    for candidate in ("qmllint", "qmllint6", "/usr/lib/qt6/bin/qmllint"):
        try:
            subprocess.run([candidate, "--version"], capture_output=True, check=True)
            return candidate
        except (OSError, subprocess.CalledProcessError):
            continue
    return None


def current_entries(qmllint):
    # qmllint exits non-zero when it has warnings; the report is still on stdout.
    out = subprocess.run([qmllint, "--json", "-", *files], cwd=root, capture_output=True, text=True).stdout
    report = json.loads(out)
    entries = set()
    for f in report["files"]:
        name = pathlib.Path(f["filename"]).name
        source = (root / name).read_text(encoding="utf-8")
        for w in f["warnings"]:
            if w["id"] == "unqualified":
                detail = source[w["charOffset"]:w["charOffset"] + w["length"]]
            else:
                detail = w["message"]
            entries.add("\t".join([name, w["id"], re.sub(r"\s+", " ", detail)]))
    return sorted(entries)


qmllint = find_qmllint()
if not qmllint:
    print("lint-qml: SKIPPED, qmllint not found (install qt6-declarative to run it)")
    sys.exit(0)

current = current_entries(qmllint)
bugs = [e for e in current if e.split("\t")[1] in NEVER_BASELINE]
if bugs:
    print("lint-qml: these are bugs, not noise, and cannot be baselined (file, category, message):", file=sys.stderr)
    for e in bugs:
        print("  " + "  |  ".join(e.split("\t")), file=sys.stderr)
    print("\nRename the property or id (a name Item already has, such as data, state, children or parent, hides its own).", file=sys.stderr)
    sys.exit(1)
if "--update" in sys.argv:
    baseline_path.write_text("\n".join(current) + "\n", encoding="utf-8")
    print(f"lint-qml: baseline rewritten with {len(current)} entries")
    sys.exit(0)

baseline = set(baseline_path.read_text(encoding="utf-8").split("\n")) - {""}
added = [e for e in current if e not in baseline]
gone = [e for e in baseline if e not in set(current)]
if added:
    print("lint-qml: new warnings (file, category, name or message):", file=sys.stderr)
    for e in added:
        print("  " + "  |  ".join(e.split("\t")), file=sys.stderr)
    print("\nA new unqualified name is usually a misspelt or removed id or property.", file=sys.stderr)
    print("If it is a real name from the shell (Color, Style, ...), accept it with:", file=sys.stderr)
    print("  scripts/lint-qml.py --update", file=sys.stderr)
    sys.exit(1)
tail = f"; {len(gone)} baseline entries no longer occur (scripts/lint-qml.py --update drops them)" if gone else ""
print(f"lint-qml: ok, {len(current)} known warnings, none new{tail}")
