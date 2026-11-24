// libFuzzer harness: Debug Adapter Protocol message decoding (the content part
// of a DAP frame received from the debug adapter).
#include <QByteArray>
#include <QCoreApplication>
#include <cstdint>

#include "debugger/dapprotocol.h"

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
    static int qargc = 1;
    static char *qargv[] = {(*argv)[0], nullptr};
    new QCoreApplication(qargc, qargv);
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    const QByteArray content(reinterpret_cast<const char *>(data), int(size));
    try {
        // parseDAPMessage throws DAPMessageError on malformed messages; that
        // is its documented error path, not a defect.
        (void)parseDAPMessage(content);
    } catch (const DAPMessageError &) {
    }
    return 0;
}
