// libFuzzer harness: RedPanda-CPP's code-completion parser (preprocessor ->
// tokenizer -> declaration/statement parser -> type resolver) over one
// in-memory source file, through the public CppParser::parseFileBlocking API.
//
// The file contents come from the parser's own GetFileStream hook, so nothing
// is read from disk: the fuzz input is served for the main file and every
// other file the input #includes is served as empty. A fresh CppParser is
// built per input, so no parser state survives between inputs.
#include <QCoreApplication>
#include <QString>
#include <QStringList>
#include <cstdint>
#include <cstdlib>
#include <memory>

#include "parser/cppparser.h"
#include "parser/parserutils.h"

static const QString kCFile = QStringLiteral("/fuzz/input.c");
static const QString kCppFile = QStringLiteral("/fuzz/input.cpp");

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
    static int qargc = 1;
    static char *qargv[] = {(*argv)[0], nullptr};
    new QCoreApplication(qargc, qargv);
    initializeParserGlobals();
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 1)
        return -1;
    // First byte selects the parser language (C or C++), the rest is the file.
    const bool isC = (data[0] & 1) != 0;
    const QString mainFile = isC ? kCFile : kCppFile;
    const QStringList lines =
        QString::fromUtf8(reinterpret_cast<const char *>(data + 1), int(size - 1))
            .split('\n', Qt::KeepEmptyParts);

    PCppParser parser = std::make_shared<CppParser>();
    parser->setLanguage(isC ? ParserLanguage::C : ParserLanguage::CPlusPlus);
    parser->setOnGetFileStream(
        [&](const QString &fileName, QStringList &buffer, int &contentVersion) {
            buffer = (fileName == mainFile) ? lines : QStringList();
            contentVersion = 1;
            return true;
        });
    CppParser::parseFileBlocking(parser, mainFile, false, "");
    // Walk the result model too, so its accessors run on what was parsed.
    (void)parser->statementList().count();
    (void)parser->namespaces();
    return 0;
}
