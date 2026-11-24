// libFuzzer harness: QSynEdit's document loader, the code that opens every
// source file in the editor: charset detection/decoding (qt_utils charsetinfo),
// binary-file detection, line splitting and glyph segmentation. The first
// byte picks the requested encoding (auto-detect, as the IDE uses by default,
// or a forced one); the rest is written to a private temp file under $TMPDIR,
// loaded with Document::loadFromFile, then walked line by line through the
// glyph accessors the editor uses for layout. Removed after each input.
#include <QGuiApplication>
#include <QByteArray>
#include <QString>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <string>
#include <unistd.h>

#include "qsynedit/document.h"
#include "qt_utils/utils.h"
#include "qt_utils/charsetinfo.h"

using namespace QSynedit;

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

static const char *const kEncodings[] = {
    ENCODING_AUTO_DETECT, ENCODING_AUTO_DETECT, ENCODING_AUTO_DETECT, ENCODING_AUTO_DETECT,
    ENCODING_UTF8,        ENCODING_UTF8_BOM,    ENCODING_UTF16,       ENCODING_UTF32,
    ENCODING_ASCII,       "GBK",                "Shift-JIS",          "ISO-8859-1",
};

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1)
        return -1;
    const QByteArray encoding(kEncodings[data[0] % (sizeof(kEncodings) / sizeof(kEncodings[0]))]);
    const char *tmpdir = getenv("TMPDIR");
    std::string path = std::string(tmpdir && *tmpdir ? tmpdir : "/tmp") + "/rp-doc-XXXXXX";
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

    auto doc = std::make_shared<Document>();
    QByteArray realEncoding;
    try {
        // FileError (and its BinaryFileError) is loadFromFile's documented
        // way to refuse a file; the editor reports it to the user.
        doc->loadFromFile(QString::fromStdString(path), encoding, realEncoding);
        for (int line = 0; line < doc->count(); line++) {
            const QString text = doc->getLine(line);
            const int glyphs = doc->glyphCount(line);
            for (int g = 0; g < glyphs; g++)
                (void)doc->glyph(line, g);
            for (int c = 0; c <= text.length(); c++)
                (void)doc->charToGlyphIndex(line, c);
        }
    } catch (const FileError &) {
    }
    unlink(path.c_str());
    return 0;
}
