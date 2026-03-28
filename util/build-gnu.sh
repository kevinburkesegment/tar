#!/bin/bash
# Build and run the GNU tar test suite against the uutils tar implementation.
#
# Usage:
#   bash util/build-gnu.sh [TEST]
#
# If TEST is given, only that test is run (e.g. "TESTS=testsuite/create/basic.at").
# The GNU tar source is expected at ../tar.gnu (sibling directory).

set -e

GNU_DIR="../tar.gnu"

if test ! -d "$GNU_DIR"; then
    echo "Could not find $GNU_DIR"
    echo "git clone https://git.savannah.gnu.org/git/tar.git tar.gnu"
    exit 1
fi

# Build the Rust implementation
cargo build --release
cp target/release/tarapp "$GNU_DIR/tarapp.rust"

# Bootstrap and build upstream GNU tar (only once)
cd "$GNU_DIR"
if test ! -f Makefile; then
    if test ! -f configure; then
        ./bootstrap
    fi
    ./configure --quiet
    make -j "$(nproc)"
fi

# Replace the GNU tar binary with our Rust implementation.
# We must also touch src/tar so make does not relink it during "make check".
cp tarapp.rust src/tar
touch src/tar

# Test 1 (version.at) checks `tar --version` against the expected GNU tar
# version string. When it doesn't match, it creates a .badversion file which
# causes AT_XFAIL_IF to mark *every* subsequent test as "expected failure",
# hiding real results. We patch the generated testsuite script to neuter this.
sed 's|cat >$XFAILFILE|cat >/dev/null|' tests/testsuite > tests/testsuite.tmp
mv tests/testsuite.tmp tests/testsuite
chmod +x tests/testsuite

if test -n "$1"; then
    export RUN_TEST="TESTS=$1"
fi

rm -f tests/.badversion

# Run the test suite
# Use || : so the script doesn't exit on test failures
make -C tests check $RUN_TEST || :

# ---------------------------------------------------------------------------
# Parse results from tests/testsuite.log (Autotest format)
# ---------------------------------------------------------------------------
#
# The summary section looks like:
#   {OK|ERROR}: N tests were run,
#   N passed unexpectedly,            (optional - XPASS)
#   N failed unexpectedly.            (optional - FAIL, no expected failures)
#   N failed (M expected failures).   (optional - total_failed=N, XFAIL=M, FAIL=N-M)
#   N tests were skipped.             (optional - SKIP)

TOTAL=0
SKIP=0
FAIL=0
XFAIL=0
XPASS=0

LOG_FILE=./tests/testsuite.log
if test -f "$LOG_FILE"; then
    TOTAL=$(sed -En 's/^(OK|ERROR): ([0-9]+) tests were run,/\2/p' "$LOG_FILE" | head -n1)
    XPASS=$(sed -En 's/^([0-9]+) passed unexpectedly[,.]/\1/p' "$LOG_FILE" | head -n1)
    SKIP=$(sed -En 's/^([0-9]+) tests were skipped\./\1/p' "$LOG_FILE" | head -n1)

    # "N failed (M expected failures)." or "N failed unexpectedly."
    total_failed=$(sed -En 's/^([0-9]+) failed .*/\1/p' "$LOG_FILE" | head -n1)
    xfail_count=$(sed -En 's/^[0-9]+ failed \(([0-9]+) expected.*/\1/p' "$LOG_FILE" | head -n1)

    : "${TOTAL:=0}" "${SKIP:=0}" "${XPASS:=0}" "${total_failed:=0}" "${xfail_count:=0}"

    XFAIL=$xfail_count
    FAIL=$((total_failed - xfail_count))
fi

# TOTAL from Autotest = tests actually run (excludes skipped)
PASS=$((TOTAL - FAIL - XFAIL - XPASS))
if [ "$PASS" -lt 0 ]; then PASS=0; fi

if [ "$TOTAL" -le 1 ] 2>/dev/null; then
    echo "Error in the execution, failing early"
    exit 1
fi

output="GNU tests summary = TOTAL: $TOTAL / PASS: $PASS / FAIL: $FAIL / SKIP: $SKIP / XFAIL: $XFAIL / XPASS: $XPASS"
echo "${output}"
if [ "$FAIL" -gt 0 ]; then echo "::warning ::${output}"; fi

# Write JSON result for CI comparison
jq -n \
   --arg date "$(date --rfc-email 2>/dev/null || date)" \
   --arg sha "${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}" \
   --arg total "$TOTAL" \
   --arg pass "$PASS" \
   --arg skip "$SKIP" \
   --arg fail "$FAIL" \
   --arg xfail "$XFAIL" \
   --arg xpass "$XPASS" \
   --arg error "0" \
   '{($date): { sha: $sha, total: $total, pass: $pass, skip: $skip, fail: $fail, xfail: $xfail, xpass: $xpass, error: $error }}' > ../gnu-result.json
