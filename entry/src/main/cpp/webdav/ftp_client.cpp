/**
 * FTP Native Client Implementation
 * 使用libcurl实现FTP/FTPS协议支持
 * 
 * 文件路径: entry/src/main/cpp/webdav/ftp_client.cpp
 */

#include "ftp_client.h"
#include <curl/curl.h>
#include <fstream>
#include <sstream>
#include <cstring>
#include <algorithm>
#include <regex>

namespace ftp {

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
        curl = curl_easy_init();
    }

    ~Impl() {
        if (curl) {
            curl_easy_cleanup(curl);
        }
    }

    void setupCurl(const std::string& url) {
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
        
        // 跟随重定向
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        
        // 详细日志（调试用，生产环境可关闭）
        // curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);
    }
};

FTPClient::FTPClient(const Config& config) : pImpl(std::make_unique<Impl>(config)) {}

FTPClient::~FTPClient() = default;

std::string FTPClient::buildFTPUrl(const std::string& remotePath) const {
    std::string protocol = pImpl->config.useFTPS ? "ftps" : "ftp";
    std::string url = protocol + "://" + pImpl->config.host;
    
    if (pImpl->config.port != 21 && pImpl->config.port != 990) {
        url += ":" + std::to_string(pImpl->config.port);
    }
    
    if (!remotePath.empty()) {
        if (remotePath[0] != '/') {
            url += "/";
        }
        url += remotePath;
    } else {
        url += "/";
    }
    
    return url;
}

Result FTPClient::testConnection() {
    Result result;
    
    if (!pImpl->curl) {
        result.success = false;
        result.message = "CURL not initialized";
        return result;
    }
    
    std::string url = buildFTPUrl("/");
    pImpl->setupCurl(url);
    
    // 只获取目录列表来测试连接
    curl_easy_setopt(pImpl->curl, CURLOPT_DIRLISTONLY, 1L);
    
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
    
    std::string path = remotePath.empty() ? "/" : remotePath;
    if (path.back() != '/') {
        path += "/";
    }
    
    std::string url = buildFTPUrl(path);
    pImpl->setupCurl(url);
    
    // 获取详细列表
    curl_easy_setopt(pImpl->curl, CURLOPT_DIRLISTONLY, 0L);
    
    std::string response;
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEFUNCTION, WriteCallback);
    curl_easy_setopt(pImpl->curl, CURLOPT_WRITEDATA, &response);
    
    CURLcode res = curl_easy_perform(pImpl->curl);
    
    if (res != CURLE_OK) {
        result.success = false;
        result.message = "List failed: " + std::string(curl_easy_strerror(res));
        return result;
    }
    
    // 解析FTP目录列表
    std::istringstream stream(response);
    std::string line;
    
    while (std::getline(stream, line)) {
        if (line.empty()) continue;
        
        FileInfo info;
        
        // 尝试解析Unix风格的列表
        // 格式: drwxr-xr-x 2 user group 4096 Jan 01 12:00 dirname
        if (line.length() > 10 && (line[0] == 'd' || line[0] == '-' || line[0] == 'l')) {
            info.isDirectory = (line[0] == 'd');
            info.permissions = line.substr(0, 10);
            
            // 提取文件名（最后一个空格后的内容）
            size_t lastSpace = line.rfind(' ');
            if (lastSpace != std::string::npos && lastSpace < line.length() - 1) {
                info.name = line.substr(lastSpace + 1);
                // 去除换行符
                while (!info.name.empty() && (info.name.back() == '\r' || info.name.back() == '\n')) {
                    info.name.pop_back();
                }
            }
            
            // 尝试提取文件大小
            std::regex sizeRegex("\\s+(\\d+)\\s+\\w+\\s+\\d+\\s+[\\d:]+\\s+");
            std::smatch match;
            if (std::regex_search(line, match, sizeRegex) && match.size() > 1) {
                try {
                    info.size = std::stoll(match[1].str());
                } catch (...) {
                    info.size = 0;
                }
            }
        } else {
            // 简单格式，只有文件名
            info.name = line;
            while (!info.name.empty() && (info.name.back() == '\r' || info.name.back() == '\n')) {
                info.name.pop_back();
            }
            info.isDirectory = false;
            info.size = 0;
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
