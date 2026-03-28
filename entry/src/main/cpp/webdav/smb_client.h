/**
 * SMB Native Client Header
 * 使用 libsmb2 提供 SMB2/SMB3 连接、目录浏览与文件下载能力
 */

#ifndef SMB_CLIENT_H
#define SMB_CLIENT_H

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace smbnative {

struct FileInfo {
    std::string path;
    std::string name;
    int64_t size = 0;
    int64_t lastModified = 0;
    bool isDirectory = false;
};

struct Config {
    std::string host;
    std::string shareName;
    int port = 445;
    std::string username;
    std::string password;
    std::string domain;
    std::string workstation;
    int timeoutMs = 30000;
    bool enableEncryption = false;
};

struct Result {
    bool success = false;
    int statusCode = 0;
    std::string message;
    std::string data;
};

struct ListResult {
    bool success = false;
    int statusCode = 0;
    std::string message;
    std::vector<FileInfo> files;
};

class SMBClient {
public:
    explicit SMBClient(const Config& config);
    ~SMBClient();

    SMBClient(const SMBClient&) = delete;
    SMBClient& operator=(const SMBClient&) = delete;

    Result testConnection(const std::string& remotePath);
    ListResult list(const std::string& remotePath);
    Result downloadFile(const std::string& remotePath, const std::string& localPath);

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;
};

} // namespace smbnative

#endif // SMB_CLIENT_H
