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
#include <hilog/log.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "WebDAVClient"

namespace webdav {

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

// 实现类
class WebDAVClient::Impl {
public:
    Config config;
    
    Impl(const Config& cfg) : config(cfg) {
        curl_ref_init();
    }
    
    ~Impl() {
        curl_ref_cleanup();
    }
    
    CURL* createCurl() {
        CURL* curl = curl_easy_init();
        if (curl) {
            // 设置超时
            curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, config.timeoutMs);
            curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, config.timeoutMs);
            
            // SSL验证
            if (!config.verifySSL) {
                curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
                curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
            }
            
            // 跟随重定向
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
            
            // 设置User-Agent
            curl_easy_setopt(curl, CURLOPT_USERAGENT, "ManXia-WebDAV-Native/1.0");
        }
        return curl;
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
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }
    
    std::string url = getFullUrl("");
    if (url.back() != '/') url += '/';
    
    std::string response;
    struct curl_slist* headers = pImpl->createAuthHeaders();
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "OPTIONS");
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
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
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::exists(const std::string& remotePath) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }
    
    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_NOBODY, 1L); // HEAD request
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);
        result.success = (httpCode == 200 || httpCode == 207);
        result.message = result.success ? "Exists" : "Not found";
    }
    
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::stat(const std::string& remotePath, FileInfo& outInfo) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
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
    
    // PROPFIND请求体
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
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PROPFIND");
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, propfindBody.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);
        
        if (httpCode == 207 || httpCode == 200) {
            result.success = true;
            result.data = response;
            
            // 解析XML响应
            outInfo.path = remotePath;
            
            // 提取文件名
            size_t lastSlash = remotePath.rfind('/');
            outInfo.name = (lastSlash != std::string::npos) ? 
                remotePath.substr(lastSlash + 1) : remotePath;
            
            // 解析大小
            std::regex sizeRegex("<D:getcontentlength>([0-9]+)</D:getcontentlength>", 
                std::regex::icase);
            std::smatch sizeMatch;
            if (std::regex_search(response, sizeMatch, sizeRegex)) {
                outInfo.size = std::stoll(sizeMatch[1].str());
            } else {
                outInfo.size = 0;
            }
            
            // 检查是否是目录
            outInfo.isDirectory = (response.find("<D:collection") != std::string::npos) ||
                                  (response.find("<d:collection") != std::string::npos);
            
            result.message = "Success";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }
    
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    
    return result;
}

ListResult WebDAVClient::list(const std::string& remotePath, int depth) {
    ListResult result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
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
    
    // PROPFIND请求体
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
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PROPFIND");
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, propfindBody.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);
        
        if (httpCode == 207 || httpCode == 200) {
            result.success = true;
            result.message = "Success";
            
            // 使用简单字符串查找解析XML，避免正则表达式栈溢出
            size_t pos = 0;
            while ((pos = response.find("<D:response", pos)) != std::string::npos) {
                size_t endPos = response.find("</D:response>", pos);
                if (endPos == std::string::npos) {
                    // 尝试小写
                    endPos = response.find("</d:response>", pos);
                }
                if (endPos == std::string::npos) break;
                
                std::string responseData = response.substr(pos, endPos - pos + 13);
                FileInfo info;
                
                // 提取href
                size_t hrefStart = responseData.find("<D:href>");
                if (hrefStart == std::string::npos) hrefStart = responseData.find("<d:href>");
                if (hrefStart != std::string::npos) {
                    hrefStart += 8; // 跳过标签
                    size_t hrefEnd = responseData.find("</D:href>", hrefStart);
                    if (hrefEnd == std::string::npos) hrefEnd = responseData.find("</d:href>", hrefStart);
                    if (hrefEnd != std::string::npos) {
                        info.path = responseData.substr(hrefStart, hrefEnd - hrefStart);
                        // URL解码
                        CURL* decodeCurl = curl_easy_init();
                        if (decodeCurl) {
                            int outLen = 0;
                            char* decoded = curl_easy_unescape(decodeCurl, info.path.c_str(), 
                                info.path.length(), &outLen);
                            if (decoded) {
                                info.path = std::string(decoded, outLen);
                                curl_free(decoded);
                            }
                            curl_easy_cleanup(decodeCurl);
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
                size_t sizeStart = responseData.find("<D:getcontentlength>");
                if (sizeStart == std::string::npos) sizeStart = responseData.find("<d:getcontentlength>");
                if (sizeStart != std::string::npos) {
                    sizeStart += 20;
                    size_t sizeEnd = responseData.find("</D:getcontentlength>", sizeStart);
                    if (sizeEnd == std::string::npos) sizeEnd = responseData.find("</d:getcontentlength>", sizeStart);
                    if (sizeEnd != std::string::npos) {
                        try {
                            info.size = std::stoll(responseData.substr(sizeStart, sizeEnd - sizeStart));
                        } catch (...) {
                            info.size = 0;
                        }
                    }
                } else {
                    info.size = 0;
                }
                
                // 检查是否是目录
                info.isDirectory = (responseData.find("<D:collection") != std::string::npos) ||
                                   (responseData.find("<d:collection") != std::string::npos);
                
                // 提取etag
                size_t etagStart = responseData.find("<D:getetag>");
                if (etagStart == std::string::npos) etagStart = responseData.find("<d:getetag>");
                if (etagStart != std::string::npos) {
                    etagStart += 11;
                    size_t etagEnd = responseData.find("</D:getetag>", etagStart);
                    if (etagEnd == std::string::npos) etagEnd = responseData.find("</d:getetag>", etagStart);
                    if (etagEnd != std::string::npos) {
                        info.etag = responseData.substr(etagStart, etagEnd - etagStart);
                        // 去除引号
                        if (!info.etag.empty() && info.etag.front() == '"') info.etag = info.etag.substr(1);
                        if (!info.etag.empty() && info.etag.back() == '"') info.etag.pop_back();
                    }
                }
                
                // 提取contentType
                size_t ctStart = responseData.find("<D:getcontenttype>");
                if (ctStart == std::string::npos) ctStart = responseData.find("<d:getcontenttype>");
                if (ctStart != std::string::npos) {
                    ctStart += 18;
                    size_t ctEnd = responseData.find("</D:getcontenttype>", ctStart);
                    if (ctEnd == std::string::npos) ctEnd = responseData.find("</d:getcontenttype>", ctStart);
                    if (ctEnd != std::string::npos) {
                        info.contentType = responseData.substr(ctStart, ctEnd - ctStart);
                    }
                }
                
                // 跳过当前目录本身
                if (!info.name.empty() && info.path != url) {
                    result.files.push_back(info);
                }
                
                pos = endPos + 13;
            }
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }
    
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::createDirectory(const std::string& remotePath) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }
    
    std::string url = getFullUrl(remotePath);
    if (url.back() != '/') url += '/';
    
    struct curl_slist* headers = pImpl->createAuthHeaders();
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "MKCOL");
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);
        
        if (httpCode == 201 || httpCode == 200 || httpCode == 204) {
            result.success = true;
            result.message = "Directory created";
        } else if (httpCode == 405) {
            // 目录可能已存在
            result.success = true;
            result.message = "Directory already exists";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }
    
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    
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
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }
    
    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
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
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::putFileContents(const std::string& remotePath, const std::string& data) {
    return putFileContents(remotePath, data.c_str(), data.size());
}

Result WebDAVClient::putFileContents(const std::string& remotePath, const char* data, size_t size) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
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
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);
    curl_easy_setopt(curl, CURLOPT_READFUNCTION, readCallback);
    curl_easy_setopt(curl, CURLOPT_READDATA, &readData);
    curl_easy_setopt(curl, CURLOPT_INFILESIZE_LARGE, (curl_off_t)size);
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
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
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::uploadFile(const std::string& localPath, const std::string& remotePath,
                                ProgressCallback progressCallback) {
    Result result;
    
    // 读取本地文件
    std::ifstream file(localPath, std::ios::binary | std::ios::ate);
    if (!file.is_open()) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to open local file";
        return result;
    }
    
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    
    std::vector<char> buffer(size);
    if (!file.read(buffer.data(), size)) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to read local file";
        return result;
    }
    file.close();
    
    // 上传
    CURL* curl = pImpl->createCurl();
    if (!curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }
    
    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();
    headers = curl_slist_append(headers, "Content-Type: application/octet-stream");
    
    ReadCallbackData readData;
    readData.data = buffer.data();
    readData.size = size;
    readData.pos = 0;
    
    ProgressData progressData;
    progressData.callback = progressCallback;
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);
    curl_easy_setopt(curl, CURLOPT_READFUNCTION, readCallback);
    curl_easy_setopt(curl, CURLOPT_READDATA, &readData);
    curl_easy_setopt(curl, CURLOPT_INFILESIZE_LARGE, (curl_off_t)size);
    
    if (progressCallback) {
        curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, webdav::progressCallback);
        curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &progressData);
        curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    }
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
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
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::getFileContents(const std::string& remotePath, std::string& outData) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }
    
    std::string url = getFullUrl(remotePath);
    struct curl_slist* headers = pImpl->createAuthHeaders();
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &outData);
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
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
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::downloadFile(const std::string& remotePath, const std::string& localPath,
                                  ProgressCallback progressCallback) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
        result.success = false;
        result.statusCode = 0;
        result.message = "Failed to initialize CURL";
        return result;
    }
    
    std::string url = getFullUrl(remotePath);
    std::string response;
    struct curl_slist* headers = pImpl->createAuthHeaders();
    
    ProgressData progressData;
    progressData.callback = progressCallback;
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    
    if (progressCallback) {
        curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, webdav::progressCallback);
        curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &progressData);
        curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
    }
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);
        
        if (httpCode == 200) {
            // 写入本地文件
            std::ofstream file(localPath, std::ios::binary);
            if (file.is_open()) {
                file.write(response.c_str(), response.size());
                file.close();
                result.success = true;
                result.message = "Downloaded";
            } else {
                result.success = false;
                result.message = "Failed to write local file";
            }
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }
    
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::copyFile(const std::string& sourcePath, const std::string& destPath, bool overwrite) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
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
    
    curl_easy_setopt(curl, CURLOPT_URL, sourceUrl.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "COPY");
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
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
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::moveFile(const std::string& sourcePath, const std::string& destPath, bool overwrite) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
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
    
    curl_easy_setopt(curl, CURLOPT_URL, sourceUrl.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "MOVE");
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
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
    curl_easy_cleanup(curl);
    
    return result;
}

Result WebDAVClient::getQuota(int64_t& usedBytes, int64_t& availableBytes) {
    Result result;
    CURL* curl = pImpl->createCurl();
    
    if (!curl) {
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
    
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PROPFIND");
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, propfindBody.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
    
    CURLcode res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.statusCode = 0;
        result.message = curl_easy_strerror(res);
    } else {
        long httpCode = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
        result.statusCode = static_cast<int>(httpCode);
        
        if (httpCode == 207 || httpCode == 200) {
            result.success = true;
            
            // 解析配额信息
            std::regex usedRegex("<D:quota-used-bytes>([0-9]+)</D:quota-used-bytes>", 
                std::regex::icase);
            std::regex availableRegex("<D:quota-available-bytes>([0-9]+)</D:quota-available-bytes>", 
                std::regex::icase);
            
            std::smatch match;
            if (std::regex_search(response, match, usedRegex)) {
                usedBytes = std::stoll(match[1].str());
            } else {
                usedBytes = -1;
            }
            
            if (std::regex_search(response, match, availableRegex)) {
                availableBytes = std::stoll(match[1].str());
            } else {
                availableBytes = -1;
            }
            
            result.message = "Success";
        } else {
            result.success = false;
            result.message = "Failed with status " + std::to_string(httpCode);
        }
    }
    
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    
    return result;
}

} // namespace webdav
