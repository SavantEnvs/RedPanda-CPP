# Injected with -DCMAKE_PROJECT_Red_Panda_CPP_INCLUDE=<this file> (mayhem/build.sh).
# CMake includes it right after upstream's top-level project() call; it only
# defers mayhem/fuzz.cmake to the end of the top-level CMakeLists.txt, so the
# fuzz targets are added once upstream's targets (qsynedit, redpanda_qt_utils)
# and helper functions exist. Upstream files are not modified.
cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}"
    CALL include "${CMAKE_SOURCE_DIR}/mayhem/fuzz.cmake")
