# Fuzz targets for RedPanda-CPP (included at the end of the top-level
# CMakeLists.txt via mayhem/project_include.cmake). Each harness in
# mayhem/harnesses/ is linked twice: <name> (libFuzzer) and <name>-standalone
# (run-once reproducer, $STANDALONE_FUZZ_MAIN). Source lists mirror upstream's
# own test executables in RedPandaIDE/CMakeLists.txt.
set(RP_IDE "${CMAKE_SOURCE_DIR}/RedPandaIDE")
set(RP_MAYHEM "${CMAKE_SOURCE_DIR}/mayhem")
set(RP_FUZZ_OUT "${CMAKE_BINARY_DIR}/bin")
set(RP_FUZZ_ENGINE "$ENV{LIB_FUZZING_ENGINE}")
if (RP_FUZZ_ENGINE STREQUAL "")
    set(RP_FUZZ_ENGINE "-fsanitize=fuzzer")
endif()
set(RP_STANDALONE_MAIN "$ENV{STANDALONE_FUZZ_MAIN}")

if (NOT RP_LSAN_OFF_SRC)
    set(RP_LSAN_OFF_SRC "${RP_MAYHEM}/lsan_off.cc")
endif()
# OBJECT, not STATIC: nothing references the hook strongly, so an archive member
# would never be pulled into the link.
add_library(rp_fuzz_support OBJECT "${RP_LSAN_OFF_SRC}")
add_library(rp_standalone_main OBJECT "${RP_STANDALONE_MAIN}")
set_source_files_properties("${RP_STANDALONE_MAIN}" PROPERTIES LANGUAGE C)

# rp_fuzz(<name> SOURCES <upstream sources...> LIBS <libs...> DEFS <defs...>)
function(rp_fuzz name)
    cmake_parse_arguments(A "" "" "SOURCES;LIBS;DEFS" ${ARGN})
    # One object library per harness so the project sources compile once.
    add_library(${name}_objs OBJECT "${RP_MAYHEM}/harnesses/${name}.cpp" ${A_SOURCES})
    target_include_directories(${name}_objs PRIVATE "${RP_IDE}" "${RP_IDE}/src")
    target_compile_definitions(${name}_objs PRIVATE ${GLOBAL_COMPILE_DEFINITIONS} ${A_DEFS})
    target_link_libraries(${name}_objs PRIVATE ${A_LIBS})
    set_target_properties(${name}_objs PROPERTIES AUTOMOC ON)

    add_executable(${name} $<TARGET_OBJECTS:${name}_objs> $<TARGET_OBJECTS:rp_fuzz_support>)
    target_link_libraries(${name} PRIVATE ${A_LIBS})
    target_link_options(${name} PRIVATE ${RP_FUZZ_ENGINE})

    add_executable(${name}-standalone $<TARGET_OBJECTS:${name}_objs>
        $<TARGET_OBJECTS:rp_standalone_main> $<TARGET_OBJECTS:rp_fuzz_support>)
    target_link_libraries(${name}-standalone PRIVATE ${A_LIBS})

    set_target_properties(${name} ${name}-standalone PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${RP_FUZZ_OUT}")
endfunction()

set(RP_PARSER_SOURCES)
foreach (f cppparser cpppreprocessor pptoken ppexpander cpptokenizer cpptokencursor
           cpptypes cppdeclarationparser cppsyntaxparser cppstatementbuilder
           cpptyperesolver typeoperationregistry cppexpressionevaluator cppscopes
           parserutils statementmodel)
    list(APPEND RP_PARSER_SOURCES "${RP_IDE}/src/parser/${f}.cpp" "${RP_IDE}/src/parser/${f}.h")
endforeach()

rp_fuzz(fuzz_cppparser
    SOURCES ${RP_PARSER_SOURCES}
    LIBS Qt::Core qsynedit redpanda_qt_utils
    DEFS APP_NAME=\"fuzz_cppparser\"
         LIBEXECDIR=\"${CMAKE_INSTALL_LIBEXECDIR}\"
         REDPANDA_CPP_VERSION=\"${REDPANDA_VERSION}\"
         ARCH_X86_64=1 ARCH_X86=1)

rp_fuzz(fuzz_syntaxer
    LIBS Qt::Core Qt::Gui qsynedit redpanda_qt_utils)

rp_fuzz(fuzz_document
    LIBS Qt::Core Qt::Gui qsynedit redpanda_qt_utils)

rp_fuzz(fuzz_gdbmi
    SOURCES "${RP_IDE}/src/debugger/gdbmiresultparser.cpp"
            "${RP_IDE}/src/debugger/gdbmiresultparser.h"
    LIBS Qt::Core redpanda_qt_utils)

rp_fuzz(fuzz_dap
    SOURCES "${RP_IDE}/src/debugger/dapprotocol.cpp"
            "${RP_IDE}/src/debugger/dapprotocol.h"
    LIBS Qt::Core redpanda_qt_utils)

rp_fuzz(fuzz_parsearg
    SOURCES "${RP_IDE}/src/utils/parsearg.cpp" "${RP_IDE}/src/utils/parsearg.h"
            "${RP_IDE}/src/utils/parsemacros.cpp" "${RP_IDE}/src/utils/parsemacros.h"
    LIBS Qt::Core)

rp_fuzz(fuzz_problemset
    SOURCES "${RP_IDE}/src/problems/freeprojectsetformat.cpp"
            "${RP_IDE}/src/problems/ojproblemset.cpp"
            "${RP_IDE}/src/problems/ojproblemset.h"
            "${RP_IDE}/src/problems/problemcasevalidator.cpp"
            "${RP_IDE}/src/widgets/ojproblemsetmodel.cpp"
            "${RP_IDE}/src/widgets/ojproblemsetmodel.h"
            "${RP_IDE}/src/iconsmanager.h"
            "${RP_IDE}/test/test_problemset_stubs.cpp"
    LIBS Qt::Core Qt::Gui Qt::Widgets Qt::Xml redpanda_qt_utils)

add_custom_target(rp_fuzz_all DEPENDS
    fuzz_cppparser fuzz_cppparser-standalone
    fuzz_syntaxer fuzz_syntaxer-standalone
    fuzz_document fuzz_document-standalone
    fuzz_gdbmi fuzz_gdbmi-standalone
    fuzz_dap fuzz_dap-standalone
    fuzz_parsearg fuzz_parsearg-standalone
    fuzz_problemset fuzz_problemset-standalone)
