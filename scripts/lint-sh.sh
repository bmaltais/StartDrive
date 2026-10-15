#!/usr/bin/env bash
# Syntax-check every shell script of the project, and run shellcheck over them (rules in ../.shellcheckrc).
# `bash -n` catches a script that is broken before it is run against the live shell; shellcheck catches one that is wrong.
#
#   scripts/lint-sh.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
# scripts/devkit is a submodule: without it checked out its globs match nothing and are left out.
shopt -s nullglob
files=(bin/startdrive lib/*.sh scripts/*.sh scripts/reload scripts/sheet scripts/dev scripts/pointer.sh tests/*.sh scripts/tours/*.sh scripts/devkit/bin/* scripts/devkit/lib/*.sh .githooks/pre-commit)
for f in "${files[@]}"; do
  bash -n "$f"
done
if command -v shellcheck >/dev/null; then
  shellcheck -x -s bash "${files[@]}"
else
  echo "lint-sh: shellcheck is not installed, only the syntax was checked"
fi
echo "lint-sh: ok, ${#files[@]} scripts"
