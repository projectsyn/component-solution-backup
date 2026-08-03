#!/usr/bin/env bash
# ponytail: render every input through the compiled defaults ManagedResource and
# write the output over its committed expected file. The caller checks for drift
# with `git diff --exit-code tests/render/expected/` — same golden-file model as
# `make golden-diff`, no hand-rolled assertions.
#
# Run `bash tests/render/run.sh && git diff --exit-code tests/render/expected/`
# locally; CI does the same. Regenerate the expected files after an intentional
# template change with `bash tests/render/run.sh` then commit them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/compiled/defaults/solution-backup/managedResource.yaml"
INPUTS="$ROOT/tests/render/inputs"
EXPECTED="$ROOT/tests/render/expected"

if ! command -v espejote >/dev/null 2>&1; then
  echo "espejote not found on PATH — install it from https://github.com/vshn/espejote releases (not vendored in this repo)" >&2
  exit 77
fi

if [ ! -f "$MANIFEST" ]; then
  make test -e instance=defaults >/dev/null
fi
if [ ! -f "$MANIFEST" ]; then
  echo "FAIL: compiled ManagedResource not found at $MANIFEST" >&2
  exit 1
fi

mkdir -p "$EXPECTED"
for input in "$INPUTS"/*.yaml; do
  name="$(basename "$input" .yaml)"
  espejote render "$MANIFEST" --input "$input" >"$EXPECTED/$name.rendered.yaml"
done
echo "rendered $(ls -1 "$INPUTS"/*.yaml | wc -l) scenarios into $EXPECTED"
