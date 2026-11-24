// libFuzzer harness: the problem-set file importers. Even first byte: the
// FPS (Free Problem Set) XML importer importFreeProblemSet(); odd first byte:
// the OJ problem-set JSON loader OJProblemSetModel::loadFromFile(). Both take
// a file path, so the rest of the input is written to a private temp file
// (under $TMPDIR) that is removed after each input.
#include <QGuiApplication>
#include <QString>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <unistd.h>

#include "problems/freeprojectsetformat.h"
#include "problems/ojproblemset.h"
#include "widgets/ojproblemsetmodel.h"
#include "qt_utils/utils.h"
#include "qt_utils/charsetinfo.h"

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
    qputenv("QT_QPA_PLATFORM", "offscreen");
    static int qargc = 1;
    static char *qargv[] = {(*argv)[0], nullptr};
    new QGuiApplication(qargc, qargv);
    // The IDE installs this global at startup (RedPandaIDE/src/main.cpp) and
    // the file loaders use it for charset fallback. A fixed locale (zh_CN, the
    // IDE's main audience, with GBK/GB18030 fallbacks) keeps runs reproducible.
    // Read-only after this point.
    pCharsetInfoManager = new CharsetInfoManager(QStringLiteral("zh_CN"));
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1)
        return -1;
    const char *tmpdir = getenv("TMPDIR");
    std::string path = std::string(tmpdir && *tmpdir ? tmpdir : "/tmp") + "/rp-fuzz-XXXXXX";
    int fd = mkstemp(&path[0]);
    if (fd < 0)
        return 0;
    const uint8_t *p = data + 1;
    size_t left = size - 1;
    while (left > 0) {
        ssize_t n = write(fd, p, left);
        if (n <= 0)
            break;
        p += n;
        left -= size_t(n);
    }
    close(fd);
    const QString file = QString::fromStdString(path);
    if ((data[0] & 1) == 0) {
        try {
            // FileError is importFreeProblemSet's documented error for
            // unreadable or malformed XML (the IDE catches it, mainwindow.cpp).
            QList<POJProblem> problems = importFreeProblemSet(file);
            for (const POJProblem &problem : problems)
                (void)problem->cases().count();
        } catch (const FileError &) {
        }
    } else {
        OJProblemSetModel model;
        int currentIndex = -1;
        try {
            // FileError is loadFromFile's documented error for unreadable or
            // non-JSON files.
            model.loadFromFile(file, false, currentIndex);
        } catch (const FileError &) {
        }
        (void)model.count();
    }
    unlink(path.c_str());
    return 0;
}
