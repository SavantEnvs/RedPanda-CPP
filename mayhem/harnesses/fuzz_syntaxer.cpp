// libFuzzer harness: QSynEdit's syntax highlighters (C/C++, ASM, GAS, NASM,
// GLSL, Lua, Makefile, plain text). The first byte selects the highlighter;
// the rest is a document tokenised line by line exactly as the editor does
// (resetState, then setLine / getToken / getTokenAttribute / next until eol,
// with the range state carried from line to line). A fresh highlighter is
// built per input.
#include <QGuiApplication>
#include <QString>
#include <QStringList>
#include <cstdint>
#include <memory>

#include "qsynedit/syntaxer/asm.h"
#include "qsynedit/syntaxer/cpp.h"
#include "qsynedit/syntaxer/gas.h"
#include "qsynedit/syntaxer/glsl.h"
#include "qsynedit/syntaxer/lua.h"
#include "qsynedit/syntaxer/makefile.h"
#include "qsynedit/syntaxer/nasm.h"
#include "qsynedit/syntaxer/textfile.h"

using namespace QSynedit;

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
    qputenv("QT_QPA_PLATFORM", "offscreen");
    static int qargc = 1;
    static char *qargv[] = {(*argv)[0], nullptr};
    new QGuiApplication(qargc, qargv);
    return 0;
}

// shared_ptr, as the editor holds them (PSyntaxer); Syntaxer has no virtual
// destructor, so a unique_ptr<Syntaxer> would delete through the wrong type.
static PSyntaxer makeSyntaxer(uint8_t sel) {
    switch (sel % 8) {
    case 0: return std::make_shared<CppSyntaxer>();
    case 1: return std::make_shared<ASMSyntaxer>();
    case 2: return std::make_shared<GASSyntaxer>();
    case 3: return std::make_shared<NASMSyntaxer>();
    case 4: return std::make_shared<GLSLSyntaxer>();
    case 5: return std::make_shared<LuaSyntaxer>();
    case 6: return std::make_shared<MakefileSyntaxer>();
    default: return std::make_shared<TextSyntaxer>();
    }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1)
        return -1;
    PSyntaxer syntaxer = makeSyntaxer(data[0]);
    const QStringList lines =
        QString::fromUtf8(reinterpret_cast<const char *>(data + 1), int(size - 1))
            .split('\n', Qt::KeepEmptyParts);
    syntaxer->resetState();
    for (int i = 0; i < lines.size(); i++) {
        syntaxer->setLine(i, lines[i], i);
        while (!syntaxer->eol()) {
            (void)syntaxer->getToken();
            (void)syntaxer->getTokenAttribute();
            (void)syntaxer->getTokenType();
            (void)syntaxer->getTokenPos();
            syntaxer->next();
        }
        (void)syntaxer->getState();
    }
    return 0;
}
