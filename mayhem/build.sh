#!/usr/bin/env bash
#
# mayhem/build.sh — build RedPanda-CPP's fuzz harnesses and its own Qt Test suites.
#
# Runs inside the commit image as `mayhem` in /mayhem. Two CMake trees, both under the
# gitignored build/ directory:
#   build/fuzz   upstream's CMake project + the fuzz targets from mayhem/fuzz.cmake (hooked in
#                with CMAKE_PROJECT_Red_Panda_CPP_INCLUDE; upstream files untouched), compiled
#                with $SANITIZER_FLAGS + libFuzzer coverage + DWARF 3. Debug config so Qt's
#                Q_ASSERT stays live (upstream's parser fixes are for debug-mode asserts).
#   build/tests  upstream's own test-cppparser and test-qsynedit, project's normal flags.
# Qt 5 comes from the image's apt packages; nothing is fetched, so a re-run is offline.
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS SRC

cd "$SRC"

# Coverage instrumentation for the project code; only with sanitizers, whose runtime
# provides the sancov callbacks the run-once -standalone binaries need.
COV_FLAGS=""
[ -n "$SANITIZER_FLAGS" ] && COV_FLAGS="-fsanitize=fuzzer-no-link"
FUZZ_FLAGS="$SANITIZER_FLAGS $COV_FLAGS $DEBUG_FLAGS"

# 1) Fuzz build (sanitized project + harnesses). mayhem/lsan_off.cc (the build-time
#    __lsan_is_turned_off hook) is linked into every fuzz and -standalone binary.
cmake -S "$SRC" -B build/fuzz -G Ninja \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_PROJECT_Red_Panda_CPP_INCLUDE="$SRC/mayhem/project_include.cmake" \
    -DRP_LSAN_OFF_SRC="$SRC/mayhem/lsan_off.cc" \
    -DCMAKE_C_FLAGS="$FUZZ_FLAGS" \
    -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
    -DCMAKE_C_FLAGS_DEBUG="-O1" \
    -DCMAKE_CXX_FLAGS_DEBUG="-O1" \
    -DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS"
cmake --build build/fuzz -j"$MAYHEM_JOBS" --target rp_fuzz_all

# 2) Upstream's own test suites, normal flags (independent tree).
cmake -S "$SRC" -B build/tests -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
    -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS"
cmake --build build/tests -j"$MAYHEM_JOBS" --target test-cppparser test-qsynedit

ls -l build/fuzz/bin/
