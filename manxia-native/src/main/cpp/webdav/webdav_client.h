/**
 * WebDAV Native Client Header
 * 使用libcurl实现完整的WebDAV协议支持
 * 
 * 文件路径: entry/src/main/cpp/webdav/webdav_client.h
 */

#ifndef WEBDAV_CLIENT_H
#define WEBDAV_CLIENT_H

#include <string>
#include <vector>
#include <map>
#include <functional>
#include <memory>

namespace webdav {

/**
 * WebDAV文件/目录信息
 */
struct FileInfo {
    std::string path;
    std::string name;
    int64_t size;
    int64_t lastModified;
    bool isDirectory;
    std::string etag;
    std::string contentType;
};

/**
 * WebDAV配置
 */
struct Config {
    std::string serverUrl;
    std::string username;
    std::string password;
    std::string basePath;
    int timeoutMs = 30000;
    bool verifySSL = true;
};

/**
 * 操作结果
 */
struct Result {
    bool success;
    int statusCode;
    std::string message;
    std::string data;
};

/**
 * 目录列表结果
 */
struct ListResult {
    bool success;
    int statusCode;
    std::string message;
    std::vector<FileInfo> files;
};

/**
 * 进度回调类型
 */
using ProgressCallback = std::function<void(int64_t current, int64_t total)>;

/**
 * WebDAV客户端类
 */
class WebDAVClient {
public:
    explicit WebDAVClient(const Config& config);
    ~WebDAVClient();

    // 禁止拷贝
    WebDAVClient(const WebDAVClient&) = delete;
    WebDAVClient& operator=(const WebDAVClient&) = delete;

    /**
     * 测试连接
     */
    Result testConnection();

    /**
     * 检查文件/目录是否存在
     */
    Result exists(const std::string& remotePath);

    /**
     * 获取文件信息
     */
    Result stat(const std::string& remotePath, FileInfo& outInfo);

    /**
     * 获取目录内容 (PROPFIND)
     */
    ListResult list(const std::string& remotePath, int depth = 1);

    /**
     * 创建目录 (MKCOL)
     */
    Result createDirectory(const std::string& remotePath);

    /**
     * 递归创建目录
     */
    Result createDirectoryRecursive(const std::string& remotePath);

    /**
     * 删除文件或目录 (DELETE)
     */
    Result deleteResource(const std::string& remotePath);

    /**
     * 上传文件内容 (PUT)
     */
    Result putFileContents(const std::string& remotePath, const std::string& data);
    Result putFileContents(const std::string& remotePath, const char* data, size_t size);

    /**
     * 上传本地文件
     */
    Result uploadFile(const std::string& localPath, const std::string& remotePath, 
                      ProgressCallback progressCallback = nullptr);

    /**
     * 下载文件内容 (GET)
     */
    Result getFileContents(const std::string& remotePath, std::string& outData);

    /**
     * 下载文件到本地
     */
    Result downloadFile(const std::string& remotePath, const std::string& localPath,
                        ProgressCallback progressCallback = nullptr);

    /**
     * 复制文件 (COPY)
     */
    Result copyFile(const std::string& sourcePath, const std::string& destPath, bool overwrite = true);

    /**
     * 移动文件 (MOVE)
     */
    Result moveFile(const std::string& sourcePath, const std::string& destPath, bool overwrite = true);

    /**
     * 获取磁盘配额信息
     */
    Result getQuota(int64_t& usedBytes, int64_t& availableBytes);

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;

    std::string getFullUrl(const std::string& relativePath) const;
    std::string buildAuthHeader() const;
};

} // namespace webdav

#endif // WEBDAV_CLIENT_H
