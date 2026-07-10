/**
 * WebDAV Native Client Implementation
 * 使用libcurl实现完整的WebDAV协议支持
 * 
 * 文件路径: entry/src/main/cpp/webdav/webdav_client.cpp
 */

#include "webdav_client.h"
#include "curl_global.h"
#include <curl/curl.h>
#include <sstream>
#include <fstream>
#include <algorithm>
#include <cstring>
#include <regex>
#include <iomanip>
#include <cstdio>
#include <ctime>
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "WebDAVClient"

namespace webdav {

// RFC 2822 日期解析为毫秒时间戳
// 格式: "Tue, 06 May 2025 12:34:56 GMT"
static int64_t parseRFC2822DateToMillis(const std::string& dateStr) {
    if (dateStr.empty()) return 0;

    struct tm tm;
    memset(&tm, 0, sizeof(tm));

    // 尝试完整格式: "Tue, 06 May 2025 12:34:56 GMT"
    char* result = strptime(dateStr.c_str(), "%a, %d %b %Y %H:%M:%S %Z", &tm);
    if (result == nullptr) {
        // 尝试无星期几格式: "06 May 2025 12:34:56 GMT"
        result = strptime(dateStr.c_str(), "%d %b %Y %H:%M:%S %Z", &tm);
    }
    if (result == nullptr) {
        // 尝试 ISO 8601 格式: "2025-05-06T12:34:56Z"
        result = strptime(dateStr.c_str(), "%Y-%m-%dT%H:%M:%S", &tm);
    }
    if (result == nullptr) {
        return 0;
    }

    time_t epoch = timegm(&tm);
    if (epoch == static_cast<time_t>(-1)) {
        return 0;
    }
    return static_cast<int64_t>(epoch) * 1000;
}

// Base64编码表
static const char base64_chars[] = 
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Base64编码
static std::string base64_encode(const std::string& input) {
    std::string ret;
    int i = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];
    const char* bytes_to_encode = input.c_str();
    size_t in_len = input.length();

    while (in_len--) {
        char_array_3[i++] = *(bytes_to_encode++);
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;

            for (i = 0; i < 4; i++)
                ret += base64_chars[char_array_4[i]];
            i = 0;
        }
    }

    if (i) {
        for (int j = i; j < 3; j++)
            char_array_3[j] = '\0';

        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);

        for (int j = 0; j < i + 1; j++)
            ret += base64_chars[char_array_4[j]];

        while (i++ < 3)
            ret += '=';
    }

    return ret;
}

// URL编码
static std::string urlEncode(const std::string& str) {
    std::ostringstream escaped;
    escaped.fill('0');
    escaped << std::hex;

    for (char c : str) {
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~' || c == '/') {
            escaped << c;
        } else {
            escaped << '%' << std::setw(2) << int((unsigned char)c);
        }
    }

    return escaped.str();
}

// CURL写入回调
static size_t writeCallback(void* contents, size_t size, size_t nmemb, void* userp) {
    size_t realsize = size * nmemb;
    std::string* str = static_cast<std::string*>(userp);
    str->append(static_cast<char*>(contents), realsize);
    return realsize;
}

// CURL读取回调（用于上传）
struct ReadCallbackData {
    const char* data;
    size_t size;
    size_t pos;
};

static size_t readCallback(void* ptr, size_t size, size_t nmemb, void* userp) {
    ReadCallbackData* readData = static_cast<ReadCallbackData*>(userp);
    size_t maxSize = size * nmemb;
    size_t remaining = readData->size - readData->pos;
    size_t copySize = std::min(maxSize, remaining);
    
    if (copySize > 0) {
        memcpy(ptr, readData->data + readData->pos, copySize);
        readData->pos += copySize;
    }
    
    return copySize;
}

// CURL文件读取回调（流式上传）
static size_t fileReadCallback(void* ptr, size_t size, size_t nmemb, void* userp) {
    FILE* file = static_cast<FILE*>(userp);
    if (!file) {
        return CURL_READFUNC_ABORT;
    }
    size_t readItems = fread(ptr, size, nmemb, file);
    return readItems * size;
}

// CURL文件写入回调（流式下载）
static size_t fileWriteCallback(void* ptr, size_t size, size_t nmemb, void* userp) {
    FILE* file = static_cast<FILE*>(userp);
    if (!file) {
        return 0;
    }
    size_t writtenItems = fwrite(ptr, size, nmemb, file);
    return writtenItems * size;
}

// CURL进度回调
struct ProgressData {
    ProgressCallback callback;
};

static int progressCallback(void* clientp, curl_off_t dltotal, curl_off_t dlnow,
                           curl_off_t ultotal, curl_off_t ulnow) {
    ProgressData* data = static_cast<ProgressData*>(clientp);
    if (data && data->callback) {
        int64_t total = (dltotal > 0) ? dltotal : ultotal;
        int64_t current = (dlnow > 0) ? dlnow : ulnow;
        data->callback(current, total);
    }
    return 0;
}

// 命名空间无关的 XML 标签查找辅助函数
// 在 xml 中查找 ":tagName>" 开头标签的位置，返回标签内容起始位置，未找到返回 string::npos
static size_t findXmlOpenTag(const std::string& xml, const std::string& tagName, size_t startPos = 0) {
    std::string suffix = ":" + tagName + ">";
    size_t pos = xml.find(suffix, startPos);
    while (pos != std::string::npos) {
        // 向前找到 '<'
        size_t ltPos = xml.rfind('<', pos);
        if (ltPos != std::string::npos && ltPos < pos) {
            return pos + suffix.length(); // 返回内容起始位置
        }
        pos = xml.find(suffix, pos + 1);
    }
    return std::string::npos;
}

// 在 xml 中查找 "</:tagName>" 闭合标签的位置，返回内容结束位置（即闭合标签的起始位置）
static size_t findXmlCloseTag(const std::string& xml, const std::string& tagName, size_t startPos = 0) {
    std::string suffix = ":" + tagName + ">";
    size_t pos = xml.find(suffix, startPos);
    while (pos != std::string::npos) {
        // 向前检查是否为 "</" 开头
        if (pos >= 2 && xml[pos - 1] == '/' && xml[pos - 2] == '<') {
            return pos - 2; // 返回闭合标签 '<' 的位置
        }
        pos = xml.find(suffix, pos + 1);
    }
    return std::string::npos;
}

// 检查 xml 中是否存在 ":collection" 标签（自闭合标签，无内容无闭合）
static bool hasCollectionTag(const std::string& xml) {
    size_t pos = xml.find(":collection");
    while (pos != std::string::npos) {
        // 向前找到 '<'
        if (pos >= 1 && xml[pos - 1] == '<') {
            return true;
        }
        pos = xml.find(":collection", pos + 1);
    }
    return false;
}

// 实现类
class WebDAVClient::Impl {
public:
    Config config;
    CURL* curl = nullptr;

    Impl(const Config& cfg) : config(cfg) {
        curl_ref_init();
        curl = curl_easy_init();
    }

    ~Impl() {
        if (curl) {
            curl_easy_cleanup(curl);
            curl = nullptr;
        }
        curl_ref_cleanup();
    }

    void setupCurl(const std::string& url) {
        if (!curl) { return; }
        // Enforce HTTPS to protect Basic Auth credentials from plaintext exposure
        if (url.size() < 8 || url.substr(0, 8) != "https://") { return; }
        curl_easy_reset(curl);
        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, config.timeoutMs);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, config.timeoutMs);
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        // Always verify peer certificate; only allow skipping hostname check when verifySSL is false
        if (!config.verifySSL) {
            curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
        }
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "ManXia-WebDAV-Native/1.0");
    }

    struct curl_slist* createAuthHeaders(struct curl_slist* headers = nullptr) {
        std::string auth = "Authorization: Basic " +
            base64_encode(config.username + ":" + config.password);
        return curl_slist_append(headers, auth.c_str());
    }
};

WebDAVClient::WebDAVClient(const Config& config) 
    : pImpl(std::make_unique<Impl>(config)) {
}

WebDAVClient::~WebDAVClient() = default;

std::string WebDAVClient::getFullUrl(const std::string& relativePath) const {
    std::string baseUrl = pImpl->config.serverUrl;
    // 移除末尾斜杠
    while (!baseUrl.empty() && baseUrl.back() == '/') {
        baseUrl.pop_back();
    }
    
    std::string basePath = pImpl->config.basePath;
    // 移除首尾斜杠
    while (!basePath.empty() && basePath.front() == '/') {
        basePath.erase(0, 1);
    }
    while (!basePath.empty() && basePath.back() == '/') {
        basePath.pop_back();
    }
    
    std::string relPath = relativePath;
    while (!relPath.empty() && relPath.front() == '/') {
        relPath.erase(0, 1);
    }
    
    std::string fullUrl = baseUrl;
    if (!basePath.empty()) {
        fullUrl += "/" + basePath;
    }
    if (!relPath.empty()) {
        fullUrl += "/" + relPath;
    }
    
    return fullUrl;
}

std::string WebDAVClient::buildAuthHeader() const {
    return "Basic " + base64_encode(pImpl->config.username + ":" + pImpl->config.password);
}

Result WebDAVClient::testConnection() {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl("");
    if (url.back() != '/') url += '/';

    std::string response;
    struct curl_slist* headers = pImpl->createAuthHeaders();

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, "OPTIONS");
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &response);

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode >= 200 && httpCode < 300) {
            result.success = true;
            result.message = "Connection successful";
        } else if (httpCode == 401) {
            result.success = false;
            result.message = "Authentication failed";
        } else {
            result.success = false;
            result.message = "Server returned " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::exists(const std::string& remotePath) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_NOBODY, 1L); // HEAD request

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);
        result.success = (httpCode == 200 || httpCode == 207);
        result.message = result.success ? "Exists" : "Not found";
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::stat(const std::string& remotePath, FileInfo& outInfo) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    std::string response;
    struct curl_slist* headers = pImpl->createAuthHeaders();
    headers = curl_slist_append(headers, "Depth: 0");
    headers = curl_slist_append(headers, "Content-Type: application/xml");

    std::string propfindBody =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        "<D:propfind xmlns:D=\"DAV:\">"
        "<D:prop>"
        "<D:getcontentlength/>"
        "<D:getlastmodified/>"
        "<D:getetag/>"
        "<D:getcontenttype/>"
        "<D:resourcetype/>"
        "</D:prop>"
        "</D:propfind>";

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, "PROPFIND");
    curl_easy_setopt(pImpl->curl, CURLOPT_POSTFIELDS, propfindBody.c_str());
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &response);

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 207 || httpCode == 200) {
            result.success = true;
            result.data = response;

            outInfo.path = remotePath;
            size_t lastSlash = remotePath.rfind('/');
            outInfo.name = (lastSlash != std::string::npos) ?
                remotePath.substr(lastSlash + 1) : remotePath;

            // 解析大小（命名空间无关）
            {
                size_t clStart = findXmlOpenTag(response, "getcontentlength");
                if (clStart != std::string::npos) {
                    size_t clEnd = findXmlCloseTag(response, "getcontentlength", clStart);
                    if (clEnd != std::string::npos) {
                        try {
                            outInfo.size = std::stoll(response.substr(clStart, clEnd - clStart));
                        } catch (...) {
                            outInfo.size = 0;
                        }
                    } else {
                        outInfo.size = 0;
                    }
                } else {
                    outInfo.size = 0;
                }
            }

            // 检查是否是目录
            outInfo.isDirectory = hasCollectionTag(response);

            // 提取lastModified
            {
                size_t lmStart = findXmlOpenTag(response, "getlastmodified");
                if (lmStart != std::string::npos) {
                    size_t lmEnd = findXmlCloseTag(response, "getlastmodified", lmStart);
                    if (lmEnd != std::string::npos) {
                        std::string dateStr = response.substr(lmStart, lmEnd - lmStart);
                        outInfo.lastModified = parseRFC2822DateToMillis(dateStr);
                    }
                }
            }

            result.message = "Success";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

ListResult WebDAVClient::list(const std::string& remotePath, int depth) {
    ListResult result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    if (url.back() != '/') url += '/';

    std::string response;
    struct curl_slist* headers = pImpl->createAuthHeaders();
    headers = curl_slist_append(headers, ("Depth: " + std::to_string(depth)).c_str());
    headers = curl_slist_append(headers, "Content-Type: application/xml");

    std::string propfindBody =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        "<D:propfind xmlns:D=\"DAV:\">"
        "<D:prop>"
        "<D:displayname/>"
        "<D:getcontentlength/>"
        "<D:getlastmodified/>"
        "<D:getetag/>"
        "<D:getcontenttype/>"
        "<D:resourcetype/>"
        "</D:prop>"
        "</D:propfind>";

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, "PROPFIND");
    curl_easy_setopt(pImpl->curl, CURLOPT_POSTFIELDS, propfindBody.c_str());
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &response);

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 207 || httpCode == 200) {
            result.success = true;
            result.message = "Success";

            // 命名空间无关的 XML 解析
            size_t pos = 0;
            while ((pos = response.find(":response", pos)) != std::string::npos) {
                // 验证前面是 '<'
                if (pos == 0 || response[pos - 1] != '<') { pos += 9; continue; }

                // 查找闭合标签 ":response>"
                size_t endSearch = pos + 9;
                size_t endPos = findXmlCloseTag(response, "response", endSearch);
                if (endPos == std::string::npos) break;

                // 计算闭合标签结束位置 "</...:response>"
                size_t closeEnd = response.find('>', endPos);
                if (closeEnd == std::string::npos) break;
                closeEnd += 1;

                std::string responseData = response.substr(pos - 1, closeEnd - (pos - 1));
                FileInfo info;

                // 提取href
                size_t hrefContentStart = findXmlOpenTag(responseData, "href");
                if (hrefContentStart != std::string::npos) {
                    size_t hrefContentEnd = findXmlCloseTag(responseData, "href", hrefContentStart);
                    if (hrefContentEnd != std::string::npos) {
                        info.path = responseData.substr(hrefContentStart, hrefContentEnd - hrefContentStart);
                        // URL解码（复用 pImpl->curl）
                        if (pImpl->curl) {
                            int outLen = 0;
                            char* decoded = curl_easy_unescape(pImpl->curl, info.path.c_str(),
                                static_cast<int>(info.path.length()), &outLen);
                            if (decoded) {
                                info.path = std::string(decoded, outLen);
                                curl_free(decoded);
                            }
                        }

                        // 提取文件名
                        size_t lastSlash = info.path.rfind('/');
                        if (lastSlash != std::string::npos && lastSlash < info.path.length() - 1) {
                            info.name = info.path.substr(lastSlash + 1);
                        } else if (lastSlash == info.path.length() - 1 && info.path.length() > 1) {
                            std::string temp = info.path.substr(0, info.path.length() - 1);
                            lastSlash = temp.rfind('/');
                            info.name = (lastSlash != std::string::npos) ?
                                temp.substr(lastSlash + 1) : temp;
                        } else {
                            info.name = info.path;
                        }
                    }
                }

                // 提取大小
                {
                    size_t clStart = findXmlOpenTag(responseData, "getcontentlength");
                    if (clStart != std::string::npos) {
                        size_t clEnd = findXmlCloseTag(responseData, "getcontentlength", clStart);
                        if (clEnd != std::string::npos) {
                            try {
                                info.size = std::stoll(responseData.substr(clStart, clEnd - clStart));
                            } catch (...) {
                                info.size = 0;
                            }
                        }
                    } else {
                        info.size = 0;
                    }
                }

                // 检查是否是目录
                info.isDirectory = hasCollectionTag(responseData);

                // 提取etag
                {
                    size_t etagStart = findXmlOpenTag(responseData, "getetag");
                    if (etagStart != std::string::npos) {
                        size_t etagEnd = findXmlCloseTag(responseData, "getetag", etagStart);
                        if (etagEnd != std::string::npos) {
                            info.etag = responseData.substr(etagStart, etagEnd - etagStart);
                            if (!info.etag.empty() && info.etag.front() == '"') info.etag = info.etag.substr(1);
                            if (!info.etag.empty() && info.etag.back() == '"') info.etag.pop_back();
                        }
                    }
                }

                // 提取contentType
                {
                    size_t ctStart = findXmlOpenTag(responseData, "getcontenttype");
                    if (ctStart != std::string::npos) {
                        size_t ctEnd = findXmlCloseTag(responseData, "getcontenttype", ctStart);
                        if (ctEnd != std::string::npos) {
                            info.contentType = responseData.substr(ctStart, ctEnd - ctStart);
                        }
                    }
                }

                // 提取lastModified
                {
                    size_t lmStart = findXmlOpenTag(responseData, "getlastmodified");
                    if (lmStart != std::string::npos) {
                        size_t lmEnd = findXmlCloseTag(responseData, "getlastmodified", lmStart);
                        if (lmEnd != std::string::npos) {
                            std::string dateStr = responseData.substr(lmStart, lmEnd - lmStart);
                            info.lastModified = parseRFC2822DateToMillis(dateStr);
                        }
                    }
                }

                // 跳过当前目录本身
                if (!info.name.empty() && info.path != url) {
                    result.files.push_back(info);
                }

                pos = closeEnd;
            }
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::createDirectory(const std::string& remotePath) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    if (url.back() != '/') url += '/';

    struct curl_slist* headers = pImpl->createAuthHeaders();

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, "MKCOL");

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 201 || httpCode == 200 || httpCode == 204) {
            result.success = true;
            result.message = "Directory created";
        } else if (httpCode == 405) {
            result.success = true;
            result.message = "Directory already exists";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::createDirectoryRecursive(const std::string& remotePath) {
    std::vector<std::string> parts;
    std::string path = remotePath;
    
    // 分割路径
    size_t pos = 0;
    while ((pos = path.find('/')) != std::string::npos) {
        std::string part = path.substr(0, pos);
        if (!part.empty()) {
            parts.push_back(part);
        }
        path.erase(0, pos + 1);
    }
    if (!path.empty()) {
        parts.push_back(path);
    }
    
    // 逐级创建目录
    std::string currentPath;
    Result result;
    result.success = true;
    
    for (const auto& part : parts) {
        currentPath += "/" + part;
        
        // 检查是否存在
        Result existsResult = exists(currentPath);
        if (!existsResult.success) {
            // 不存在，创建
            result = createDirectory(currentPath);
            if (!result.success && result.statusCode != 405) {
                return result;
            }
        }
    }
    
    result.success = true;
    result.message = "Directory created recursively";
    return result;
}

Result WebDAVClient::deleteResource(const std::string& remotePath) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, "DELETE");

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 200 || httpCode == 204 || httpCode == 404) {
            result.success = true;
            result.message = "Deleted";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::putFileContents(const std::string& remotePath, const std::string& data) {
    return putFileContents(remotePath, data.c_str(), data.size());
}

Result WebDAVClient::putFileContents(const std::string& remotePath, const char* data, size_t size) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();
    headers = curl_slist_append(headers, "Content-Type: application/octet-stream");

    ReadCallbackData readData;
    readData.data = data;
    readData.size = size;
    readData.pos = 0;

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_UPLOAD, 1L);
    curl_easy_setopt(pImpl->curl, CURLOPT_READFUNCTION, readCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_READDATA, &readData);
    curl_easy_setopt(pImpl->curl, CURLOPT_INFILESIZE_LARGE, (curl_off_t)size);

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 200 || httpCode == 201 || httpCode == 204) {
            result.success = true;
            result.message = "Uploaded";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::uploadFile(const std::string& localPath, const std::string& remotePath,
                                ProgressCallback progressCallback) {
    Result result;
    
    // 以流式方式读取本地文件，避免一次性载入内存导致OOM
    FILE* file = fopen(localPath.c_str(), "rb");
    if (!file) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to open local file";
        return result;
    }

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to seek local file";
        return result;
    }
    long fileSize = ftell(file);
    if (fileSize < 0) {
        fclose(file);
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to get local file size";
        return result;
    }
    rewind(file);
    
    // 上传
    if (!pImpl->curl) {
        fclose(file);
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();
    headers = curl_slist_append(headers, "Content-Type: application/octet-stream");

    ProgressData progressData;
    progressData.callback = progressCallback;

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_UPLOAD, 1L);
    curl_easy_setopt(pImpl->curl, CURLOPT_READFUNCTION, fileReadCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_READDATA, file);
    curl_easy_setopt(pImpl->curl, CURLOPT_INFILESIZE_LARGE, static_cast<curl_off_t>(fileSize));

    if (progressCallback) {
        curl_easy_setopt(pImpl->curl, CURLOPT_XFERINFOFUNCTION, webdav::progressCallback);
        curl_easy_setopt(pImpl->curl, CURLOPT_XFERINFODATA, &progressData);
        curl_easy_setopt(pImpl->curl, CURLOPT_NOPROGRESS, 0L);
    }

    CURLcode res = curl_easy_perform(pImpl->curl);
    fclose(file);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 200 || httpCode == 201 || httpCode == 204) {
            result.success = true;
            result.message = "Uploaded";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::getFileContents(const std::string& remotePath, std::string& outData) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &outData);

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 200) {
            result.success = true;
            result.message = "Downloaded";
            result.data = outData;
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::downloadFile(const std::string& remotePath, const std::string& localPath,
                                  ProgressCallback progressCallback) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();
    FILE* file = fopen(localPath.c_str(), "wb");
    if (!file) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to open local file for write";
        curl_slist_free_all(headers);
        return result;
    }

    ProgressData progressData;
    progressData.callback = progressCallback;

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, fileWriteCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, file);

    if (progressCallback) {
        curl_easy_setopt(pImpl->curl, CURLOPT_XFERINFOFUNCTION, webdav::progressCallback);
        curl_easy_setopt(pImpl->curl, CURLOPT_XFERINFODATA, &progressData);
        curl_easy_setopt(pImpl->curl, CURLOPT_NOPROGRESS, 0L);
    }

    CURLcode res = curl_easy_perform(pImpl->curl);
    fclose(file);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
        std::remove(localPath.c_str());
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 200) {
            result.success = true;
            result.message = "Downloaded";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
            std::remove(localPath.c_str());
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::copyFile(const std::string& sourcePath, const std::string& destPath, bool overwrite) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string sourceUrl = getFullUrl(sourcePath);
    std::string destUrl = getFullUrl(destPath);

    struct curl_slist* headers = pImpl->createAuthHeaders();
    headers = curl_slist_append(headers, ("Destination: " + destUrl).c_str());
    headers = curl_slist_append(headers, overwrite ? "Overwrite: T" : "Overwrite: F");

    pImpl->setupCurl(sourceUrl);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, "COPY");

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 201 || httpCode == 204) {
            result.success = true;
            result.message = "Copied";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::moveFile(const std::string& sourcePath, const std::string& destPath, bool overwrite) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string sourceUrl = getFullUrl(sourcePath);
    std::string destUrl = getFullUrl(destPath);

    struct curl_slist* headers = pImpl->createAuthHeaders();
    headers = curl_slist_append(headers, ("Destination: " + destUrl).c_str());
    headers = curl_slist_append(headers, overwrite ? "Overwrite: T" : "Overwrite: F");

    pImpl->setupCurl(sourceUrl);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, "MOVE");

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 201 || httpCode == 204) {
            result.success = true;
            result.message = "Moved";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

Result WebDAVClient::getQuota(int64_t& usedBytes, int64_t& availableBytes) {
    Result result;
    if (!pImpl->curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }

    std::string url = getFullUrl("");
    if (url.back() != '/') url += '/';

    std::string response;
    struct curl_slist* headers = pImpl->createAuthHeaders();
    headers = curl_slist_append(headers, "Depth: 0");
    headers = curl_slist_append(headers, "Content-Type: application/xml");

    std::string propfindBody =
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        "<D:propfind xmlns:D=\"DAV:\">"
        "<D:prop>"
        "<D:quota-used-bytes/>"
        "<D:quota-available-bytes/>"
        "</D:prop>"
        "</D:propfind>";

    pImpl->setupCurl(url);
    curl_easy_setopt(pImpl->curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(pImpl->curl, CURLOPT_CUSTOMREQUEST, "PROPFIND");
    curl_easy_setopt(pImpl->curl, CURLOPT_POSTFIELDS, propfindBody.c_str());
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &response);

    CURLcode res = curl_easy_perform(pImpl->curl);

    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(pImpl->curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);

        if (httpCode == 207 || httpCode == 200) {
            result.success = true;

            // 解析配额信息（命名空间无关）
            {
                size_t usedStart = findXmlOpenTag(response, "quota-used-bytes");
                if (usedStart != std::string::npos) {
                    size_t usedEnd = findXmlCloseTag(response, "quota-used-bytes", usedStart);
                    if (usedEnd != std::string::npos) {
                        try {
                            usedBytes = std::stoll(response.substr(usedStart, usedEnd - usedStart));
                        } catch (...) {
                            usedBytes = -1;
                        }
                    } else {
                        usedBytes = -1;
                    }
                } else {
                    usedBytes = -1;
                }
            }

            {
                size_t availStart = findXmlOpenTag(response, "quota-available-bytes");
                if (availStart != std::string::npos) {
                    size_t availEnd = findXmlCloseTag(response, "quota-available-bytes", availStart);
                    if (availEnd != std::string::npos) {
                        try {
                            availableBytes = std::stoll(response.substr(availStart, availEnd - availStart));
                        } catch (...) {
                            availableBytes = -1;
                        }
                    } else {
                        availableBytes = -1;
                    }
                } else {
                    availableBytes = -1;
                }
            }

            result.message = "Success";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }

    curl_slist_free_all(headers);
    return result;
}

} // namespace webdav
