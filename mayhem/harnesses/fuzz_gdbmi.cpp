// libFuzzer harness: the GDB/MI record parser the IDE runs on every line gdb
// prints (result records, async records, nested tuples/lists, C escapes).
#include <QByteArray>
#include <QCoreApplication>
#include <QString>
#include <cstdint>

#include "debugger/gdbmiresultparser.h"

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
    static int qargc = 1;
    static char *qargv[] = {(*argv)[0], nullptr};
    new QCoreApplication(qargc, qargv);
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    const QByteArray record(reinterpret_cast<const char *>(data), int(size));
    GDBMIResultParser parser;
    {
        GDBMIResultType type;
        GDBMIResultParser::ParseObject obj;
        parser.parse(record, QStringLiteral("-fuzz"), type, obj);
    }
    {
        QByteArray result;
        GDBMIResultParser::ParseObject obj;
        parser.parseAsyncResult(record, result, obj);
    }
    return 0;
}
