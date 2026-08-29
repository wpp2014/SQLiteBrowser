#include <QByteArray>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslSocket>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrl>

#include <openssl/comp.h>
#include <openssl/err.h>
#include <sqlite3.h>
#include <windows.h>

#include <memory>
#include <vector>

namespace
{
class SqliteDatabase
{
public:
    ~SqliteDatabase()
    {
        if(m_db)
            sqlite3_close(m_db);
    }

    sqlite3** address()
    {
        return &m_db;
    }

    sqlite3* get() const
    {
        return m_db;
    }

private:
    sqlite3* m_db = nullptr;
};

bool reportFailure(const QString& message)
{
    qCritical().noquote() << message;
    return false;
}

QString canonicalPath(const QString& path)
{
    const QString canonical = QFileInfo(path).canonicalFilePath();
    return QDir::cleanPath(canonical.isEmpty() ? QFileInfo(path).absoluteFilePath() : canonical);
}

QString loadedModulePath(const QString& moduleName)
{
    const HMODULE module = GetModuleHandleW(
        reinterpret_cast<LPCWSTR>(moduleName.utf16()));
    if(module == nullptr)
        return {};

    std::vector<wchar_t> buffer(32768);
    const DWORD length = GetModuleFileNameW(
        module, buffer.data(), static_cast<DWORD>(buffer.size()));
    if(length == 0 || length == buffer.size())
        return {};

    return QString::fromWCharArray(buffer.data(), static_cast<qsizetype>(length));
}

bool verifyModuleDirectory(const QString& runtimeDir,
                           const QString& moduleName,
                           const QString& relativeDirectory = {})
{
    const QString modulePath = loadedModulePath(moduleName);
    if(modulePath.isEmpty())
        return reportFailure(QStringLiteral("Required module is not loaded: %1").arg(moduleName));

    const QString expectedDirectory = canonicalPath(
        QDir(runtimeDir).filePath(relativeDirectory));
    const QString actualDirectory = canonicalPath(QFileInfo(modulePath).absolutePath());
    if(actualDirectory.compare(expectedDirectory, Qt::CaseInsensitive) != 0)
    {
        return reportFailure(
            QStringLiteral("Module %1 was loaded from %2; expected directory: %3")
                .arg(moduleName, modulePath, expectedDirectory));
    }

    qInfo().noquote() << QStringLiteral("module: %1 -> %2").arg(moduleName, modulePath);
    return true;
}

QString qtModuleName(const QString& baseName)
{
#ifdef _DEBUG
    return baseName + QStringLiteral("d.dll");
#else
    return baseName + QStringLiteral(".dll");
#endif
}

QString qtPluginName(const QString& baseName)
{
#ifdef _DEBUG
    return baseName + QStringLiteral("d.dll");
#else
    return baseName + QStringLiteral(".dll");
#endif
}

bool verifyCommonModules(const QString& runtimeDir)
{
    return verifyModuleDirectory(runtimeDir, qtModuleName(QStringLiteral("Qt6Core")))
        && verifyModuleDirectory(runtimeDir, qtModuleName(QStringLiteral("Qt6Network")))
        && verifyModuleDirectory(runtimeDir, QStringLiteral("sqlcipher.dll"))
        && verifyModuleDirectory(runtimeDir, QStringLiteral("libcrypto-3-x64.dll"));
}

bool sqliteExec(sqlite3* database, const char* sql)
{
    char* errorMessage = nullptr;
    const int result = sqlite3_exec(database, sql, nullptr, nullptr, &errorMessage);
    if(result == SQLITE_OK)
        return true;

    const QString details = errorMessage
        ? QString::fromUtf8(errorMessage)
        : QString::fromUtf8(sqlite3_errmsg(database));
    sqlite3_free(errorMessage);
    return reportFailure(
        QStringLiteral("SQL failed (%1): %2").arg(result).arg(details));
}

bool querySingleText(sqlite3* database, const char* sql, QString& value)
{
    sqlite3_stmt* statement = nullptr;
    const int prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nullptr);
    if(prepareResult != SQLITE_OK)
    {
        return reportFailure(
            QStringLiteral("SQL prepare failed (%1): %2")
                .arg(prepareResult)
                .arg(QString::fromUtf8(sqlite3_errmsg(database))));
    }

    const int stepResult = sqlite3_step(statement);
    if(stepResult != SQLITE_ROW)
    {
        sqlite3_finalize(statement);
        return reportFailure(
            QStringLiteral("SQL query returned %1 instead of a row: %2")
                .arg(stepResult)
                .arg(QString::fromUtf8(sqlite3_errmsg(database))));
    }

    const unsigned char* text = sqlite3_column_text(statement, 0);
    value = text ? QString::fromUtf8(reinterpret_cast<const char*>(text)) : QString();
    const int finalizeResult = sqlite3_finalize(statement);
    if(finalizeResult != SQLITE_OK)
    {
        return reportFailure(
            QStringLiteral("SQL finalize failed (%1): %2")
                .arg(finalizeResult)
                .arg(QString::fromUtf8(sqlite3_errmsg(database))));
    }
    return true;
}

bool openDatabase(const QString& path, SqliteDatabase& database)
{
    const QByteArray encodedPath = QFile::encodeName(path);
    const int result = sqlite3_open_v2(
        encodedPath.constData(),
        database.address(),
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
        nullptr);
    if(result == SQLITE_OK)
        return true;

    return reportFailure(
        QStringLiteral("Could not open database %1 (%2): %3")
            .arg(path)
            .arg(result)
            .arg(database.get() ? QString::fromUtf8(sqlite3_errmsg(database.get()))
                                : QStringLiteral("no database handle")));
}

bool runDatabaseSmoke(const QString& runtimeDir)
{
    QTemporaryDir temporaryDirectory;
    if(!temporaryDirectory.isValid())
        return reportFailure(QStringLiteral("Could not create the database smoke directory."));

    const QString plainPath = temporaryDirectory.filePath(QStringLiteral("plain.sqlite"));
    {
        SqliteDatabase plainDatabase;
        if(!openDatabase(plainPath, plainDatabase)
            || !sqliteExec(plainDatabase.get(),
                           "CREATE TABLE plain_data(value TEXT NOT NULL);"
                           "INSERT INTO plain_data VALUES('plain-ok');"))
        {
            return false;
        }

        QString value;
        if(!querySingleText(plainDatabase.get(),
                            "SELECT value FROM plain_data;",
                            value)
            || value != QStringLiteral("plain-ok"))
        {
            return reportFailure(QStringLiteral("Plain SQLite round trip failed."));
        }
    }

    const QByteArray key("sqlitebrowser-stage4-key");
    const QString encryptedPath =
        temporaryDirectory.filePath(QStringLiteral("encrypted.sqlite"));
    QString cipherVersion;
    {
        SqliteDatabase encryptedDatabase;
        if(!openDatabase(encryptedPath, encryptedDatabase))
            return false;
        if(sqlite3_key(encryptedDatabase.get(), key.constData(), key.size()) != SQLITE_OK)
            return reportFailure(QStringLiteral("sqlite3_key() failed for the encrypted database."));
        if(!querySingleText(encryptedDatabase.get(),
                            "PRAGMA cipher_version;",
                            cipherVersion)
            || !cipherVersion.startsWith(QStringLiteral("4.18.")))
        {
            return reportFailure(
                QStringLiteral("Unexpected SQLCipher version: %1").arg(cipherVersion));
        }
        if(!sqliteExec(encryptedDatabase.get(),
                       "CREATE TABLE secure_data(value TEXT NOT NULL);"
                       "INSERT INTO secure_data VALUES('cipher-ok');"))
        {
            return false;
        }
    }

    QFile encryptedFile(encryptedPath);
    if(!encryptedFile.open(QIODevice::ReadOnly))
        return reportFailure(QStringLiteral("Could not inspect the encrypted database file."));
    const QByteArray encryptedHeader = encryptedFile.read(16);
    encryptedFile.close();
    if(encryptedHeader == QByteArray("SQLite format 3\0", 16))
        return reportFailure(QStringLiteral("The SQLCipher database has a plaintext SQLite header."));

    {
        SqliteDatabase databaseWithoutKey;
        if(!openDatabase(encryptedPath, databaseWithoutKey))
            return false;

        sqlite3_stmt* statement = nullptr;
        const int prepareResult = sqlite3_prepare_v2(
            databaseWithoutKey.get(),
            "SELECT value FROM secure_data;",
            -1,
            &statement,
            nullptr);
        const int stepResult =
            prepareResult == SQLITE_OK ? sqlite3_step(statement) : prepareResult;
        sqlite3_finalize(statement);
        if(stepResult == SQLITE_ROW)
            return reportFailure(QStringLiteral("Encrypted database was readable without its key."));
    }

    {
        SqliteDatabase reopenedDatabase;
        if(!openDatabase(encryptedPath, reopenedDatabase))
            return false;
        if(sqlite3_key(reopenedDatabase.get(), key.constData(), key.size()) != SQLITE_OK)
            return reportFailure(QStringLiteral("sqlite3_key() failed while reopening the database."));

        QString value;
        QString integrity;
        if(!querySingleText(reopenedDatabase.get(),
                            "SELECT value FROM secure_data;",
                            value)
            || value != QStringLiteral("cipher-ok")
            || !querySingleText(reopenedDatabase.get(),
                                "PRAGMA integrity_check;",
                                integrity)
            || integrity != QStringLiteral("ok"))
        {
            return reportFailure(QStringLiteral("Encrypted SQLCipher round trip failed."));
        }
    }

    if(!verifyCommonModules(runtimeDir))
        return false;

    qInfo().noquote()
        << QStringLiteral("database smoke passed; SQLCipher %1").arg(cipherVersion);
    return true;
}

QString opensslErrorText()
{
    QStringList errors;
    unsigned long errorCode = 0;
    while((errorCode = ERR_get_error()) != 0)
    {
        char buffer[256] = {};
        ERR_error_string_n(errorCode, buffer, sizeof(buffer));
        errors.append(QString::fromLatin1(buffer));
    }
    return errors.join(QStringLiteral("; "));
}

bool runBrotliSmoke(const QString& runtimeDir)
{
    COMP_METHOD* method = COMP_brotli_oneshot();
    if(method == nullptr)
    {
        return reportFailure(
            QStringLiteral("OpenSSL Brotli method could not be loaded: %1")
                .arg(opensslErrorText()));
    }

    using CompContext = std::unique_ptr<COMP_CTX, decltype(&COMP_CTX_free)>;
    CompContext encoder(COMP_CTX_new(method), &COMP_CTX_free);
    CompContext decoder(COMP_CTX_new(method), &COMP_CTX_free);
    if(!encoder || !decoder)
    {
        return reportFailure(
            QStringLiteral("Could not create OpenSSL Brotli contexts: %1")
                .arg(opensslErrorText()));
    }

    QByteArray input;
    for(int i = 0; i < 256; ++i)
        input.append("SQLiteBrowser OpenSSL Brotli runtime smoke payload.\n");

    QByteArray compressed(input.size() * 2 + 1024, Qt::Uninitialized);
    const int compressedSize = COMP_compress_block(
        encoder.get(),
        reinterpret_cast<unsigned char*>(compressed.data()),
        compressed.size(),
        reinterpret_cast<unsigned char*>(input.data()),
        input.size());
    if(compressedSize <= 0)
    {
        return reportFailure(
            QStringLiteral("OpenSSL Brotli compression failed: %1")
                .arg(opensslErrorText()));
    }
    compressed.resize(compressedSize);

    QByteArray expanded(input.size() + 1024, Qt::Uninitialized);
    const int expandedSize = COMP_expand_block(
        decoder.get(),
        reinterpret_cast<unsigned char*>(expanded.data()),
        expanded.size(),
        reinterpret_cast<unsigned char*>(compressed.data()),
        compressed.size());
    if(expandedSize != input.size())
    {
        return reportFailure(
            QStringLiteral("OpenSSL Brotli expansion failed: %1")
                .arg(opensslErrorText()));
    }
    expanded.resize(expandedSize);
    if(expanded != input)
        return reportFailure(QStringLiteral("OpenSSL Brotli round trip produced different data."));

    if(!verifyCommonModules(runtimeDir)
        || !verifyModuleDirectory(runtimeDir, QStringLiteral("brotlicommon.dll"))
        || !verifyModuleDirectory(runtimeDir, QStringLiteral("brotlidec.dll"))
        || !verifyModuleDirectory(runtimeDir, QStringLiteral("brotlienc.dll")))
    {
        return false;
    }

    qInfo() << "Brotli smoke passed; compressed" << input.size()
            << "bytes to" << compressed.size() << "bytes";
    return true;
}

bool runTlsSmoke(const QString& runtimeDir, const QUrl& url)
{
    const QStringList availableBackends = QSslSocket::availableBackends();
    if(!availableBackends.contains(QStringLiteral("openssl")))
    {
        return reportFailure(
            QStringLiteral("Qt OpenSSL backend is unavailable; available backends: %1")
                .arg(availableBackends.join(QStringLiteral(", "))));
    }
    if(!QSslSocket::setActiveBackend(QStringLiteral("openssl"))
        || QSslSocket::activeBackend() != QStringLiteral("openssl")
        || !QSslSocket::supportsSsl())
    {
        return reportFailure(QStringLiteral("Qt could not activate the OpenSSL TLS backend."));
    }

    const QString runtimeVersion = QSslSocket::sslLibraryVersionString();
    if(!runtimeVersion.contains(QStringLiteral("OpenSSL 3.5.7")))
    {
        return reportFailure(
            QStringLiteral("Unexpected Qt TLS runtime: %1").arg(runtimeVersion));
    }

    QNetworkAccessManager network;
    QNetworkRequest request(url);
    request.setAttribute(
        QNetworkRequest::RedirectPolicyAttribute,
        QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setHeader(
        QNetworkRequest::UserAgentHeader,
        QStringLiteral("SQLiteBrowser-v4-runtime-smoke"));

    QNetworkReply* reply = network.get(request);
    QEventLoop eventLoop;
    QTimer timeout;
    timeout.setSingleShot(true);
    bool timedOut = false;
    QObject::connect(reply, &QNetworkReply::finished, &eventLoop, &QEventLoop::quit);
    QObject::connect(&timeout, &QTimer::timeout, &eventLoop, [&]() {
        timedOut = true;
        reply->abort();
        eventLoop.quit();
    });
    timeout.start(45000);
    eventLoop.exec();

    if(timedOut)
        return reportFailure(QStringLiteral("HTTPS request timed out: %1").arg(url.toString()));
    if(reply->error() != QNetworkReply::NoError)
    {
        return reportFailure(
            QStringLiteral("HTTPS request failed (%1): %2")
                .arg(reply->error())
                .arg(reply->errorString()));
    }

    const int statusCode =
        reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if(statusCode < 200 || statusCode >= 400)
    {
        return reportFailure(
            QStringLiteral("HTTPS request returned status %1: %2")
                .arg(statusCode)
                .arg(reply->url().toString()));
    }

    if(!verifyCommonModules(runtimeDir)
        || !verifyModuleDirectory(runtimeDir, QStringLiteral("libssl-3-x64.dll"))
        || !verifyModuleDirectory(
            runtimeDir,
            qtPluginName(QStringLiteral("qopensslbackend")),
            QStringLiteral("tls")))
    {
        return false;
    }

    qInfo().noquote()
        << QStringLiteral("TLS smoke passed; backend=%1; runtime=%2; status=%3; url=%4")
               .arg(QSslSocket::activeBackend(),
                    runtimeVersion,
                    QString::number(statusCode),
                    reply->url().toString());
    return true;
}
}

int main(int argc, char* argv[])
{
    QCoreApplication application(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("sqlitebrowser-runtime-smoke"));

    QCommandLineParser parser;
    parser.setApplicationDescription(
        QStringLiteral("Restricted-runtime smoke tests for SQLiteBrowser."));
    parser.addHelpOption();
    const QCommandLineOption modeOption(
        QStringLiteral("mode"),
        QStringLiteral("Smoke mode: database, brotli, or tls."),
        QStringLiteral("mode"));
    const QCommandLineOption runtimeDirectoryOption(
        QStringLiteral("runtime-dir"),
        QStringLiteral("Deployed application runtime directory."),
        QStringLiteral("directory"));
    const QCommandLineOption urlOption(
        QStringLiteral("url"),
        QStringLiteral("HTTPS URL used by tls mode."),
        QStringLiteral("url"));
    parser.addOptions({modeOption, runtimeDirectoryOption, urlOption});
    parser.process(application);

    const QString mode = parser.value(modeOption).trimmed().toLower();
    const QString runtimeDir = canonicalPath(parser.value(runtimeDirectoryOption));
    if(!QDir(runtimeDir).exists())
    {
        qCritical().noquote()
            << QStringLiteral("Runtime directory does not exist: %1").arg(runtimeDir);
        return 2;
    }

    bool passed = false;
    if(mode == QStringLiteral("database"))
    {
        passed = runDatabaseSmoke(runtimeDir);
    }
    else if(mode == QStringLiteral("brotli"))
    {
        passed = runBrotliSmoke(runtimeDir);
    }
    else if(mode == QStringLiteral("tls"))
    {
        const QUrl url(parser.value(urlOption));
        if(!url.isValid() || url.scheme() != QStringLiteral("https"))
        {
            qCritical().noquote()
                << QStringLiteral("TLS mode requires a valid HTTPS URL.");
            return 2;
        }
        passed = runTlsSmoke(runtimeDir, url);
    }
    else
    {
        qCritical().noquote()
            << QStringLiteral("Unknown smoke mode: %1").arg(mode);
        return 2;
    }

    return passed ? 0 : 1;
}
