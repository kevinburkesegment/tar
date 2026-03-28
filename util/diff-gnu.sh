#!/bin/bash
# Compare failing GNU tar tests between two testsuite.log files.
#
# Usage:
#   bash util/diff-gnu.sh <old-testsuite.log> <new-testsuite.log>
#
# Extracts test numbers/names from the "Failed tests:" section of each
# Autotest log, then compares the two lists.

set -eu

export LC_COLLATE=C

# Extract failed test identifiers (NUM: FILE-NAME) from testsuite.log.
# The "Failed tests:" section lists them as "  NUM: file.at:LINE  description".
failing_tests() {
    if [ -f "$1" ]; then
        sed -n '/^Failed tests:/,/^$/{ s/^ *\([0-9]*\): \([^ ]*\):.*/\1:\2/p; }' "$1" | sort
    fi
}

comm -3 <(failing_tests "$1") <(failing_tests "$2") | tr '\t' ',' | while IFS=, read -r old new _; do
    if [ -n "$old" ]; then
        echo "::warning ::Congrats! The GNU test $old is now passing!"
    fi
    if [ -n "$new" ]; then
        echo "::error ::GNU test failed: $new. $new is passing on 'main'. Maybe you have to rebase?"
    fi
done
