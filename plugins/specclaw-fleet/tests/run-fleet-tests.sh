#!/usr/bin/env bash
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
for case_file in "$TESTS_DIR"/cases/*.sh; do
  echo "== $(basename "$case_file")"
  bash "$case_file" || failed=$((failed + 1))
done
(( failed == 0 )) && echo "All specclaw-fleet tests passed." || echo "$failed case file(s) failed."
exit $(( failed > 0 ))
