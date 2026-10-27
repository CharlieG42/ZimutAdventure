#!/bin/sh
# Lance tous les tests headless de ZimutAdventure.
# Usage : ./tests/run_all.sh [chemin_vers_godot]
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
FAILED=0
for test in tests/test_*.gd; do
	echo "=== $test ==="
	if ! "$GODOT" --headless --path . -s "$test"; then
		FAILED=1
	fi
done
if [ "$FAILED" -eq 0 ]; then
	echo "ALL TESTS PASSED"
else
	echo "SOME TESTS FAILED"
fi
exit $FAILED
