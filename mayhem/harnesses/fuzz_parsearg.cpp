// libFuzzer harness: the shell-like argument splitter and macro expander the
// IDE applies to compiler/run option strings read from project files.
#include <QCoreApplication>
#include <QMap>
#include <QString>
#include <cstdint>

#include "utils/parsearg.h"
#include "utils/parsemacros.h"

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
    static int qargc = 1;
    static char *qargv[] = {(*argv)[0], nullptr};
    new QCoreApplication(qargc, qargv);
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    const QString s = QString::fromUtf8(reinterpret_cast<const char *>(data), int(size));
    const QMap<QString, QString> vars{
        {QStringLiteral("SOURCE"), QStringLiteral("main.cpp")},
        {QStringLiteral("EXE"), QStringLiteral("a b.out")},
        {QStringLiteral("DIR"), QStringLiteral("/tmp/x")},
    };
    (void)parseArguments(s, vars, true);
    (void)parseArguments(s, vars, false);
    (void)parseArgumentsWithoutVariables(s);
    (void)parseMacros(s, vars);
    return 0;
}
