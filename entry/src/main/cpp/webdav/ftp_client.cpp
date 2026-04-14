/**
 * FTP Native Client Implementation
 * 使用libcurl实现 FTP/FTPS/SFTP 协议支持
 * 
 * 文件路径: entry/src/main/cpp/webdav/ftp_client.cpp
 */

#include "ftp_client.h"
#include "curl_global.h"
#include <curl/curl.h>
#include <fstream>
#include <sstream>
#include <cstring>
#include <cctype>
#include <algorithm>
#include <regex>
#include <vector>
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "FTPClient"

namespace ftp {

namespace {

bool ProtocolEqualsIgnoreCase(const char* left, const char* right)
{
    if (left == nullptr || right == nullptr) {
        return false;
    }

    size_t index = 0;
    while (left[index] != '\0' && right[index] != '\0') {
        const unsigned char leftChar = static_cast<unsigned char>(left[index]);
        const unsigned char rightChar = static_cast<unsigned char>(right[index]);
        if (std::tolower(leftChar) != std::tolower(rightChar)) {
            return false;
        }
        index++;
    }

    return left[index] == '\0' && right[index] == '\0';
}

bool IsCurlProtocolSupported(const char* protocolName)
{
    const curl_version_info_data* info = curl_version_info(CURLVERSION_NOW);
    if (info == nullptr || info->protocols == nullptr) {
        return false;
    }

    const char* const* protocols = info->protocols;
    size_t index = 0;
    while (protocols[index] != nullptr) {
        if (ProtocolEqualsIgnoreCase(protocols[index], protocolName)) {
            return true;
        }
        index++;
    }
    return false;
}

std::string TrimWhitespace(const std::string& text)
{
    if (text.empty()) {
        return "";
    }

    size_t start = 0;
    while (start < text.length() && std::isspace(static_cast<unsigned char>(text[start])) != 0) {
        start++;
    }

    if (start >= text.length()) {
        return "";
    }

    size_t end = text.length() - 1;
    while (end > start && std::isspace(static_cast<unsigned char>(text[end])) != 0) {
        end--;
    }

    return text.substr(start, end - start + 1);
}

bool ParseUnixListLine(const std::string& rawLine, FileInfo& outInfo)
{
    const std::string line = TrimWhitespace(rawLine);
    if (line.length() < 11) {
        return false;
    }
    if (!(line[0] == 'd' || line[0] == '-' || line[0] == 'l')) {
        return false;
    }

    std::istringstream stream(line);
    std::string permissions;
    std::string linkCount;
    std::string owner;
    std::string group;
    std::string sizeToken;
    std::string month;
    std::string day;
    std::string timeOrYear;
    if (!(stream >> permissions >> linkCount >> owner >> group >> sizeToken >> month >> day >> timeOrYear)) {
        return false;
    }

    std::string name;
    std::getline(stream, name);
    name = TrimWhitespace(name);
    if (name.empty()) {
        return false;
    }

    if (!permissions.empty() && permissions[0] == 'l') {
        const size_t arrowIndex = name.find(" -> ");
        if (arrowIndex != std::string::npos) {
            name = name.substr(0, arrowIndex);
            name = TrimWhitespace(name);
        }
    }

    outInfo.isDirectory = !permissions.empty() && permissions[0] == 'd';
    outInfo.permissions = permissions.length() >= 10 ? permissions.substr(0, 10) : permissions;
    outInfo.name = name;
    outInfo.size = 0;
    try {
        outInfo.size = std::stoll(sizeToken);
    } catch (...) {
        outInfo.size = 0;
    }
    return true;
}

bool ParseWindowsListLine(const std::string& rawLine, FileInfo& outInfo)
{
    static const std::regex windowsPattern(
        "^\\s*\\d{2}-\\d{2}-\\d{2,4}\\s+\\d{2}:\\d{2}(?:AM|PM)?\\s+(<DIR>|\\d+)\\s+(.+)\\s*$",
        std::regex::icase
    );

    std::smatch match;
    if (!std::regex_match(rawLine, match, windowsPattern) || match.size() < 3) {
        return false;
    }

    const std::string typeToken = match[1].str();
    const std::string name = TrimWhitespace(match[2].str());
    if (name.empty()) {
        return false;
    }

    const std::string upperTypeToken = [&typeToken]() {
        std::string upper = typeToken;
        std::transform(upper.begin(), upper.end(), upper.begin(), [](unsigned char ch) {
            return static_cast<char>(std::toupper(ch));
        });
        return upper;
    }();

    outInfo.name = name;
    outInfo.permissions = "";
    outInfo.isDirectory = upperTypeToken == "<DIR>";
    outInfo.size = 0;
    if (!outInfo.isDirectory) {
        try {
            outInfo.size = std::stoll(typeToken);
        } catch (...) {
            outInfo.size = 0;
        }
    }
    return true;
}

} // namespace

// 写入回调
static size_t WriteCallback(void* contents, size_t size, size_t nmemb, void* userp) {
    std::string* str = static_cast<std::string*>(userp);
    size_t totalSize = size * nmemb;
    str->append(static_cast<char*>(contents), totalSize);
    return totalSize;
}

// 文件写入回调
static size_t FileWriteCallback(void* contents, size_t size, size_t nmemb, void* userp) {
    std::ofstream* file = static_cast<std::ofstream*>(userp);
    size_t totalSize = size * nmemb;
    file->write(static_cast<char*>(contents), totalSize);
    return totalSize;
}

// 文件读取回调
static size_t FileReadCallback(void* ptr, size_t size, size_t nmemb, void* userp) {
    std::ifstream* file = static_cast<std::ifstream*>(userp);
    file->read(static_cast<char*>(ptr), size * nmemb);
    return file->gcount();
}

// 进度回调结构
struct ProgressData {
    ProgressCallback callback;
    int64_t lastReported;
};

// 进度回调
static int ProgressCallback_curl(void* clientp, curl_off_t dltotal, curl_off_t dlnow,
                                  curl_off_t ultotal, curl_off_t ulnow) {
    ProgressData* data = static_cast<ProgressData*>(clientp);
    if (data && data->callback) {
        int64_t total = (dltotal > 0) ? dltotal : ultotal;
        int64_t now = (dlnow > 0) ? dlnow : ulnow;
        if (now - data->lastReported > 1024 || now == total) {
            data->callback(now, total);
            data->lastReported = now;
        }
    }
    return 0;
}

class FTPClient::Impl {
public:
    Config config;
    CURL* curl = nullptr;

    Impl(const Config& cfg) : config(cfg) {
        // 先初始化curl全局状态
        curl_ref_init();
        curl = curl_easy_init();
        if (!curl) {
            OH_LOG_ERROR(LOG_APP, "curl_easy_init failed");
        }
    }

    ~Impl() {
        if (curl) {
            curl_easy_cleanup(curl);
            curl = nullptr;
        }
        // 释放curl全局引用
        curl_ref_cleanup();
    }

    void setupCurl(const std::string& url) {
        if (!curl) {
            OH_LOG_ERROR(LOG_APP, "setupCurl: curl handle is null");
            return;
        }
        curl_easy_reset(curl);
        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        
        // 认证
        if (!config.username.empty()) {
            std::string userpwd = config.username + ":" + config.password;
            curl_easy_setopt(curl, CURLOPT_USERPWD, userpwd.c_str());
        }
        
        // 超时设置 - 使用秒为单位，更可靠
        long timeoutSec = config.timeoutMs / 1000;
        if (timeoutSec < 5) timeoutSec = 5; // 最少5秒
        if (timeoutSec > 30) timeoutSec = 30; // 最多30秒
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, timeoutSec);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, timeoutSec);
        
        // 禁用信号处理（避免多线程问题）
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        
        if (!config.useSFTP) {
            // 被动模式（FTP默认使用被动模式更安全）
            if (config.passive) {
                curl_easy_setopt(curl, CURLOPT_FTP_USE_EPSV, 1L);
            } else {
                curl_easy_setopt(curl, CURLOPT_FTP_USE_EPSV, 0L);
                curl_easy_setopt(curl, CURLOPT_FTP_USE_EPRT, 0L);
            }

            // FTPS设置
            if (config.useFTPS) {
                curl_easy_setopt(curl, CURLOPT_USE_SSL, CURLUSESSL_ALL);
                curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
                curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
            }
        } else {
            curl_easy_setopt(curl, CURLOPT_SSH_AUTH_TYPES, CURLSSH_AUTH_ANY);
        }
        
        // 跟随重定向
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        
        // 详细日志（调试用，生产环境可关闭）
        // curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);
    }
};

FTPClient::FTPClient(const Config& config) : pImpl(std::make_unique<Impl>(config)) {}

FTPClient::~FTPClient() = default;

std::string FTPClient::buildFTPUrl(const std::string& remotePath, bool encodePathSegments) const {
    std::string protocol = pImpl->config.useSFTP ? "sftp" : (pImpl->config.useFTPS ? "ftps" : "ftp");
    std::string url = protocol + "://" + pImpl->config.host;

    const int defaultPort = pImpl->config.useSFTP ? 22 : (pImpl->config.useFTPS ? 990 : 21);
    if (pImpl->config.port != defaultPort) {
        url += ":" + std::to_string(pImpl->config.port);
    }
    
    std::string normalizedPath = remotePath.empty() ? "/" : remotePath;
    const bool hasLeadingSlash = !normalizedPath.empty() && normalizedPath.front() == '/';
    const bool hasTrailingSlash = normalizedPath.size() > 1 && normalizedPath.back() == '/';

    std::vector<std::string> segments;
    std::string currentSegment;
    for (char ch : normalizedPath) {
        if (ch == '/') {
            if (!currentSegment.empty()) {
                segments.push_back(currentSegment);
                currentSegment.clear();
            }
            continue;
        }
        currentSegment.push_back(ch);
    }
    if (!currentSegment.empty()) {
        segments.push_back(currentSegment);
    }

    std::string encodedPath = hasLeadingSlash ? "/" : "";
    bool firstSegment = true;
    for (const std::string& segment : segments) {
        std::string encodedSegment = segment;
        if (encodePathSegments && pImpl->curl != nullptr) {
            char* encoded = curl_easy_escape(
                pImpl->curl,
                segment.c_str(),
                static_cast<int>(segment.size())
            );
            if (encoded != nullptr) {
                encodedSegment = std::string(encoded);
                curl_free(encoded);
            }
        }

        if (!firstSegment) {
            encodedPath += "/";
        }
        encodedPath += encodedSegment;
        firstSegment = false;
    }

    if (encodedPath.empty()) {
        encodedPath = "/";
    } else if (hasTrailingSlash && encodedPath.back() != '/') {
        encodedPath += "/";
    }

    if (encodedPath.front() != '/') {
        encodedPath = "/" + encodedPath;
    }

    url += encodedPath;

    return url;
}

std::string FTPClient::buildFTPUrl(const std::string& remotePath) const {
    return buildFTPUrl(remotePath, true);
}

Result FTPClient::testConnection() {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "Connection failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::string url = buildFTPUrl("/");
    pImpl->setupCurl(url);
    
    // 只获取目录列表来测试连接
    curl_easy_setopt(pImpl->curl, CURLOPT_DIRLISTONLY, pImpl->config.useSFTP ? 0L : 1L);
    
    std::string response;
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, WriteCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &response);
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    
    if (res == CURLE_OK) {
        result.success = true;
        result.message = "Connection successful";
    } else {
        result.success = false;
        result.message = "Connection failed: " + std::string(curl_easy_strerror(res));
    }
    
    return result;
}

ListResult FTPClient::list(const std::string& remotePath) {
    ListResult result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "List failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::string normalizedInputPath = remotePath.empty() ? "/" : remotePath;
    if (!normalizedInputPath.empty() && normalizedInputPath.front() != '/') {
        normalizedInputPath = "/" + normalizedInputPath;
    }
    while (normalizedInputPath.length() > 1 && normalizedInputPath.back() == '/') {
        normalizedInputPath.pop_back();
    }

    const std::string pathWithoutTrailing = normalizedInputPath.empty() ? "/" : normalizedInputPath;
    const std::string pathWithTrailing = pathWithoutTrailing == "/" ? "/" : pathWithoutTrailing + "/";

    struct ListAttempt {
        const char* name;
        bool encodePathSegments;
        bool appendTrailingSlash;
        long ftpFileMethod;
        bool useCustomListCommand;
        bool quotePathForCommand;
    };

    std::vector<ListAttempt> attempts = {
        {"encoded/trailing/multi", true, true, CURLFTPMETHOD_MULTICWD, false, false},
        {"encoded/no-trailing/multi", true, false, CURLFTPMETHOD_MULTICWD, false, false},
        {"raw/trailing/multi", false, true, CURLFTPMETHOD_MULTICWD, false, false},
        {"raw/no-trailing/multi", false, false, CURLFTPMETHOD_MULTICWD, false, false},
        {"raw/trailing/no-cwd", false, true, CURLFTPMETHOD_NOCWD, false, false},
        {"encoded/trailing/no-cwd", true, true, CURLFTPMETHOD_NOCWD, false, false}
    };
    if (!pImpl->config.useSFTP) {
        attempts.push_back({"custom-list/raw", false, false, CURLFTPMETHOD_NOCWD, true, false});
        attempts.push_back({"custom-list/quoted", false, false, CURLFTPMETHOD_NOCWD, true, true});
    }

    std::string response;
    std::string path = pathWithTrailing;
    CURLcode finalErrorCode = CURLE_OK;
    long finalResponseCode = 0;
    std::vector<std::string> attemptErrors;
    bool listSucceeded = false;

    for (const ListAttempt& attempt : attempts) {
        const std::string currentPath = attempt.appendTrailingSlash ? pathWithTrailing : pathWithoutTrailing;
        std::string strategyDetail = "";

        if (attempt.useCustomListCommand) {
            const std::string url = buildFTPUrl("/", attempt.encodePathSegments);
            pImpl->setupCurl(url);
            strategyDetail = "urlPath=/";
        } else {
            const std::string url = buildFTPUrl(currentPath, attempt.encodePathSegments);
            pImpl->setupCurl(url);
            strategyDetail = "urlPath=" + currentPath;
        }

        // 获取详细列表
        curl_easy_setopt(pImpl->curl, CURLOPT_DIRLISTONLY, 0L);
        if (!pImpl->config.useSFTP) {
            curl_easy_setopt(pImpl->curl, CURLOPT_FTP_FILEMETHOD, attempt.ftpFileMethod);
        }

        std::string customListCommand = "";
        if (attempt.useCustomListCommand) {
            customListCommand = "LIST ";
            if (attempt.quotePathForCommand) {
                customListCommand += "\"" + currentPath + "\"";
            } else {
                customListCommand += currentPath;
            }
            curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, customListCommand.c_str());
            strategyDetail += ", command=" + customListCommand;
        }

        response.clear();
        curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, WriteCallback);
        curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &response);

        const CURLcode res = curl_easy_perform(pImpl->curl);
        long responseCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &responseCode);

        if (res == CURLE_OK) {
            path = currentPath;
            if (path.back() != '/') {
                path += "/";
            }
            listSucceeded = true;
            break;
        }

        finalErrorCode = res;
        finalResponseCode = responseCode;
        attemptErrors.push_back(
            "[" + std::string(attempt.name) +
            ", path=" + currentPath +
            ", " + strategyDetail +
            ", curl=" + std::to_string(static_cast<int>(res)) +
            ", response=" + std::to_string(responseCode) +
            ", reason=" + std::string(curl_easy_strerror(res)) + "]"
        );
    }

    if (!listSucceeded) {
        result.success = false;
        std::string details;
        for (size_t index = 0; index < attemptErrors.size(); index++) {
            if (index > 0) {
                details += "; ";
            }
            details += attemptErrors[index];
        }
        result.message = "List failed: " + std::string(curl_easy_strerror(finalErrorCode)) +
                         " (response=" + std::to_string(finalResponseCode) +
                         ", attempts=" + details + ")";
        return result;
    }
    
    // 解析FTP目录列表
    std::istringstream stream(response);
    std::string line;
    
    while (std::getline(stream, line)) {
        const std::string trimmedLine = TrimWhitespace(line);
        if (trimmedLine.empty()) {
            continue;
        }

        FileInfo info;

        if (ParseUnixListLine(trimmedLine, info) || ParseWindowsListLine(trimmedLine, info)) {
            // 已按标准目录列表格式解析
        } else {
            // 简单格式，可能只有文件名
            info.name = trimmedLine;
            info.isDirectory = false;
            info.size = 0;
            info.permissions = "";
        }

        info.name = TrimWhitespace(info.name);
        if (info.name == "total" || info.name.rfind("total ", 0) == 0) {
            continue;
        }
        if (!info.name.empty() && info.name != "." && info.name != "..") {
            info.path = path + info.name;
            result.files.push_back(info);
        }
    }
    
    result.success = true;
    result.message = "Listed " + std::to_string(result.files.size()) + " items";
    return result;
}

Result FTPClient::uploadFile(const std::string& localPath, const std::string& remotePath,
                              ProgressCallback progressCallback) {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "Upload failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::ifstream file(localPath, std::ios::binary);
    if (!file.is_open()) {
        result.success = false;
        result.message = "Cannot open local file: " + localPath;
        return result;
    }
    
    // 获取文件大小
    file.seekg(0, std::ios::end);
    curl_off_t fileSize = file.tellg();
    file.seekg(0, std::ios::beg);
    
    std::string url = buildFTPUrl(remotePath);
    pImpl->setupCurl(url);
    
    curl_easy_setopt(pImpl->curl, CURLOPT_UPLOAD, 1L);
    curl_easy_setopt(pImpl->curl, CURLOPT_READFUNCTION, FileReadCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_READDATA, &file);
    curl_easy_setopt(pImpl->curl, CURLOPT_INFILESIZE_LARGE, fileSize);
    
    // 进度回调
    ProgressData progressData{progressCallback, 0};
    if (progressCallback) {
        curl_easy_setopt(pImpl->curl, CURLOPT_XFERINFOFUNCTION, ProgressCallback_curl);
        curl_easy_setopt(pImpl->curl, CURLOPT_XFERINFODATA, &progressData);
        curl_easy_setopt(pImpl->curl, CURLOPT_NOPROGRESS, 0L);
    }
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    file.close();
    
    if (res == CURLE_OK) {
        result.success = true;
        result.message = "Upload successful";
    } else {
        result.success = false;
        result.message = "Upload failed: " + std::string(curl_easy_strerror(res));
    }
    
    return result;
}

Result FTPClient::downloadFile(const std::string& remotePath, const std::string& localPath,
                                ProgressCallback progressCallback) {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "Download failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::ofstream file(localPath, std::ios::binary);
    if (!file.is_open()) {
        result.success = false;
        result.message = "Cannot create local file: " + localPath;
        return result;
    }
    
    std::string url = buildFTPUrl(remotePath);
    pImpl->setupCurl(url);
    
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, FileWriteCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &file);
    
    // 进度回调
    ProgressData progressData{progressCallback, 0};
    if (progressCallback) {
        curl_easy_setopt(pImpl->curl, CURLOPT_XFERINFOFUNCTION, ProgressCallback_curl);
        curl_easy_setopt(pImpl->curl, CURLOPT_XFERINFODATA, &progressData);
        curl_easy_setopt(pImpl->curl, CURLOPT_NOPROGRESS, 0L);
    }
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    file.close();
    
    if (res == CURLE_OK) {
        result.success = true;
        result.message = "Download successful";
    } else {
        result.success = false;
        result.message = "Download failed: " + std::string(curl_easy_strerror(res));
        // 删除失败的文件
        std::remove(localPath.c_str());
    }
    
    return result;
}

Result FTPClient::deleteFile(const std::string& remotePath) {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "Delete failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::string url = buildFTPUrl("/");
    pImpl->setupCurl(url);
    
    // 使用QUOTE命令删除文件
    struct curl_slist* commands = nullptr;
    std::string deleteCmd = "DELE " + remotePath;
    commands = curl_slist_append(commands, deleteCmd.c_str());
    
    curl_easy_setopt(pImpl->curl, CURLOPT_QUOTE, commands);
    curl_easy_setopt(pImpl->curl, CURLOPT_NOBODY, 1L);
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    curl_slist_free_all(commands);
    
    if (res == CURLE_OK) {
        result.success = true;
        result.message = "File deleted";
    } else {
        result.success = false;
        result.message = "Delete failed: " + std::string(curl_easy_strerror(res));
    }
    
    return result;
}

Result FTPClient::mkdir(const std::string& remotePath) {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "Mkdir failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::string url = buildFTPUrl("/");
    pImpl->setupCurl(url);
    
    // 使用QUOTE命令创建目录
    struct curl_slist* commands = nullptr;
    std::string mkdirCmd = "MKD " + remotePath;
    commands = curl_slist_append(commands, mkdirCmd.c_str());
    
    curl_easy_setopt(pImpl->curl, CURLOPT_QUOTE, commands);
    curl_easy_setopt(pImpl->curl, CURLOPT_NOBODY, 1L);
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    curl_slist_free_all(commands);
    
    if (res == CURLE_OK) {
        result.success = true;
        result.message = "Directory created";
    } else {
        result.success = false;
        result.message = "Mkdir failed: " + std::string(curl_easy_strerror(res));
    }
    
    return result;
}

Result FTPClient::rmdir(const std::string& remotePath) {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "Rmdir failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::string url = buildFTPUrl("/");
    pImpl->setupCurl(url);
    
    // 使用QUOTE命令删除目录
    struct curl_slist* commands = nullptr;
    std::string rmdirCmd = "RMD " + remotePath;
    commands = curl_slist_append(commands, rmdirCmd.c_str());
    
    curl_easy_setopt(pImpl->curl, CURLOPT_QUOTE, commands);
    curl_easy_setopt(pImpl->curl, CURLOPT_NOBODY, 1L);
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    curl_slist_free_all(commands);
    
    if (res == CURLE_OK) {
        result.success = true;
        result.message = "Directory removed";
    } else {
        result.success = false;
        result.message = "Rmdir failed: " + std::string(curl_easy_strerror(res));
    }
    
    return result;
}

Result FTPClient::rename(const std::string& fromPath, const std::string& toPath) {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "Rename failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::string url = buildFTPUrl("/");
    pImpl->setupCurl(url);
    
    // 使用QUOTE命令重命名
    struct curl_slist* commands = nullptr;
    std::string rnfrCmd = "RNFR " + fromPath;
    std::string rntoCmd = "RNTO " + toPath;
    commands = curl_slist_append(commands, rnfrCmd.c_str());
    commands = curl_slist_append(commands, rntoCmd.c_str());
    
    curl_easy_setopt(pImpl->curl, CURLOPT_QUOTE, commands);
    curl_easy_setopt(pImpl->curl, CURLOPT_NOBODY, 1L);
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    curl_slist_free_all(commands);
    
    if (res == CURLE_OK) {
        result.success = true;
        result.message = "Rename successful";
    } else {
        result.success = false;
        result.message = "Rename failed: " + std::string(curl_easy_strerror(res));
    }
    
    return result;
}

Result FTPClient::getFileSize(const std::string& remotePath, int64_t& outSize) {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    if (pImpl->config.useSFTP && !IsCurlProtocolSupported("sftp")) {
        result.success = false;
        result.message = "Get size failed: libcurl build does not include SFTP (CURL_USE_LIBSSH2=OFF)";
        return result;
    }

    std::string url = buildFTPUrl(remotePath);
    pImpl->setupCurl(url);
    
    curl_easy_setopt(pImpl->curl, CURLOPT_NOBODY, 1L);
    curl_easy_setopt(pImpl->curl, CURLOPT_FILETIME, 1L);
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    
    if (res == CURLE_OK) {
        curl_off_t size;
        res = curl_easy_getinfo(pImpl->curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD_T, &size);
        if (res == CURLE_OK && size >= 0) {
            outSize = size;
            result.success = true;
            result.message = "Size: " + std::to_string(size);
        } else {
            result.success = false;
            result.message = "Cannot get file size";
        }
    } else {
        result.success = false;
        result.message = "Failed: " + std::string(curl_easy_strerror(res));
    }
    
    return result;
}

} // namespace ftp
