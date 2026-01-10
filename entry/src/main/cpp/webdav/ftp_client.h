/**
 * FTP Native Client Header
 * 使用libcurl实现FTP/FTPS协议支持
 * 
 * 文件路径: entry/src/main/cpp/webdav/ftp_client.h
 */

#ifndef FTP_CLIENT_H
#define FTP_CLIENT_H

#include <string>
#include <vector>
#include <functional>
#include <memory>
#include <cstdint>

namespace ftp {

/**
 * FTP文件/目录信息
 */
struct FileInfo {
    std::string name;
    std::string path;
    int64_t size;
    bool isDirectory;
    int64_t lastModified;
    std::string permissions;
};

/**
 * FTP配置
 */
struct Config {
    std::string host;
    int port = 21;
    std::string username;
    std::string password;
    bool useFTPS = false;
    bool passive = true;
    int timeoutMs = 30000;
};

/**
 * 操作结果
 */
struct Result {
    bool success;
    std::string message;
    std::string data;
};

/**
 * 目录列表结果
 */
struct ListResult {
    bool success;
    std::string message;
    std::vector<FileInfo> files;
};

/**
 * 进度回调类型
 */
using ProgressCallback = std::function<void(int64_t current, int64_t total)>;

/**
 * FTP客户端类
 */
class FTPClient {
public:
    explicit FTPClient(const Config& config);
    ~FTPClient();

    // 禁止拷贝
    FTPClient(const FTPClient&) = delete;
    FTPClient& operator=(const FTPClient&) = delete;

    /**
     * 测试连接
     */
    Result testConnection();

    /**
     * 获取目录列表
     */
    ListResult list(const std::string& remotePath);

    /**
     * 上传文件
     */
    Result uploadFile(const std::string& localPath, const std::string& remotePath,
                      ProgressCallback progressCallback = nullptr);

    /**
     * 下载文件
     */
    Result downloadFile(const std::string& remotePath, const std::string& localPath,
                        ProgressCallback progressCallback = nullptr);

    /**
     * 删除文件
     */
    Result deleteFile(const std::string& remotePath);

    /**
     * 创建目录
     */
    Result mkdir(const std::string& remotePath);

    /**
     * 删除目录
     */
    Result rmdir(const std::string& remotePath);

    /**
     * 重命名/移动文件
     */
    Result rename(const std::string& fromPath, const std::string& toPath);

    /**
     * 获取文件大小
     */
    Result getFileSize(const std::string& remotePath, int64_t& outSize);

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;

    std::string buildFTPUrl(const std::string& remotePath) const;
};

} // namespace ftp

#endif // FTP_CLIENT_H
