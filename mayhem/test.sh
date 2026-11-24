#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Upstream's own Qt Test suites (built by mayhem/build.sh with normal flags):
#   test-qsynedit   editor/highlighter/document tests, all suites
#   test-cppparser  C/C++ parser tests, one run per suite (suites as listed in
#                   RedPandaIDE/test/test-cppparser-main.cpp). Omitted/filtered:
#     - TestCppParserStandardLibrary, TestCppParserPublicApiBaseline: compiled empty
#       unless a Windows MinGW tree is configured (upstream CMake options).
#     - TestCppExpressionEvaluator::test_expression_evaluator_numeric_conversions:
#       expects the Windows LLP64 rule (long + unsigned int -> unsigned long); on Linux
#       (LP64) the parser answers "long", so it fails on every Linux build.
# Each QTest run prints "Totals: P passed, F failed, S skipped, ..."; a run that prints
# no Totals line (crash, or a neutered binary) counts as one failure.
export QT_QPA_PLATFORM=offscreen
PASSED=0 FAILED=0 SKIPPED=0
run_qtest() {  # <dir> <binary> [args...]
  local dir="$1" bin="$2"; shift 2
  if [ ! -x "$dir/$bin" ]; then
    echo "missing test runner $dir/$bin (mayhem/build.sh should have built it)" >&2
    FAILED=$((FAILED + 1)); return
  fi
  local out rc totals
  out=$(cd "$dir" && "./$bin" "$@" 2>&1); rc=$?
  totals=$(printf '%s\n' "$out" | grep -E '^Totals: [0-9]+ passed, [0-9]+ failed, [0-9]+ skipped' || true)
  printf '%s\n' "$out" | grep -E '^(FAIL!|Totals:|QFATAL)' || true
  if [ -z "$totals" ]; then
    echo "no QTest totals from $bin $* (rc=$rc)" >&2
    FAILED=$((FAILED + 1)); return
  fi
  while read -r _ p _ f _ s _; do
    PASSED=$((PASSED + p)); FAILED=$((FAILED + ${f%,})); SKIPPED=$((SKIPPED + ${s%,}))
  done <<< "$(printf '%s\n' "$totals" | tr -d ',')"
  if [ "$rc" -ne 0 ] && ! printf '%s\n' "$totals" | grep -qv ' 0 failed'; then
    echo "$bin $* exited $rc with no failed test reported" >&2
    FAILED=$((FAILED + 1))
  fi
}

QS_DIR="$SRC/build/tests/libs/qsynedit"
CP_DIR="$SRC/build/tests/RedPandaIDE"
run_qtest "$QS_DIR" test-qsynedit
for suite in TestCppPreprocessor TestCppPreprocessorInclude TestCppTokenizer \
             TestCppDeclarationParser TestCppStatementBuilder TestCppTypeResolver \
             TestTypeOperationRegistry TestPpTokenizer TestPpExpander TestCppParser \
             TestCppParserInvalidation TestCppParserSyntax; do
  run_qtest "$CP_DIR" test-cppparser --suite "$suite"
done
EVAL_FUNCS=()
if [ -x "$CP_DIR/test-cppparser" ]; then
  mapfile -t EVAL_FUNCS < <(cd "$CP_DIR" && ./test-cppparser --suite TestCppExpressionEvaluator -functions 2>/dev/null \
    | sed -n 's/^\(test_[A-Za-z0-9_]*\)()$/\1/p' | grep -vx 'test_expression_evaluator_numeric_conversions')
fi
if [ "${#EVAL_FUNCS[@]}" -gt 0 ]; then
  run_qtest "$CP_DIR" test-cppparser --suite TestCppExpressionEvaluator "${EVAL_FUNCS[@]}"
else
  echo "could not list TestCppExpressionEvaluator functions" >&2
  FAILED=$((FAILED + 1))
fi

emit_ctrf "qtest" "$PASSED" "$FAILED" "$SKIPPED"
