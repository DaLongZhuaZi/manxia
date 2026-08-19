/**
 * SMB Native Client Implementation
 * 基于 libsmb2 提供 SMB2/SMB3 访问能力，替换旧的 ArkTS SMB 认证链路
 */

#include "smb_client.h"

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <memory>
#include <string>
#include <vector>

#include <hilog/log.h>
#include <smb2/smb2.h>
#include <smb2/libsmb2.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "SMBClient"

namespace smbnative {

namespace {

constexpr uint32_t DIRECTORY_ATTRIBUTE = 0x00000010;
constexpr uint32_t DEFAULT_READ_CHUNK = 64 * 1024;
constexpr const char* DEFAULT_WORKSTATION = "MANXIA_OHOS";

std::string Trim(const std::string& value)
{
    size_t start = 0;
    while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start])) != 0) {
        start++;
    }

    size_t end = value.size();
    while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1])) != 0) {
        end--;
    }

    return value.substr(start, end - start);
}

std::string NormalizeRemotePath(const std::string& path)
{
    std::string normalized;
    normalized.reserve(path.size());

    for (char ch : path) {
        normalized.push_back(ch == '\\' ? '/' : ch);
    }

    normalized = Trim(normalized);
    while (!normalized.empty() && normalized.front() == '/') {
        normalized.erase(normalized.begin());
    }
    while (!normalized.empty() && normalized.back() == '/') {
        normalized.pop_back();
    }

    std::string collapsed;
    collapsed.reserve(normalized.size());
    bool lastWasSlash = false;
    for (char ch : normalized) {
        if (ch == '/') {
            if (!lastWasSlash) {
                collapsed.push_back(ch);
            }
            lastWasSlash = true;
        } else {
            collapsed.push_back(ch);
            lastWasSlash = false;
        }
    }

    return collapsed;
}

std::string JoinRemotePath(const std::string& parentPath, const std::string& name)
{
    const std::string parent = NormalizeRemotePath(parentPath);
    const std::string child = NormalizeRemotePath(name);
    if (child.empty()) {
        return parent.empty() ? "/" : "/" + parent;
    }
    if (parent.empty()) {
        return "/" + child;
    }
    return "/" + parent + "/" + child;
}

std::string BuildServerTarget(const std::string& host, int port)
{
    const std::string trimmedHost = Trim(host);
    if (trimmedHost.empty() || port <= 0 || port == 445) {
        return trimmedHost;
    }

    const bool hasIpv6Literal = trimmedHost.find(':') != std::string::npos &&
        trimmedHost.find('[') == std::string::npos &&
        trimmedHost.find(']') == std::string::npos;
    if (hasIpv6Literal) {
        return "[" + trimmedHost + "]:" + std::to_string(port);
    }
    return trimmedHost + ":" + std::to_string(port);
}

std::string BuildWorkstation(const std::string& workstation)
{
    const std::string trimmed = Trim(workstation);
    if (!trimmed.empty()) {
        return trimmed;
    }
    return DEFAULT_WORKSTATION;
}

int ConvertStatusCode(struct smb2_context* context, int fallbackStatus)
{
    if (context != nullptr) {
        const int ntStatus = smb2_get_nterror(context);
        if (ntStatus != 0) {
            return ntStatus;
        }
    }
    return fallbackStatus;
}

std::string BuildErrorMessage(
    const std::string& prefix,
    struct smb2_context* context,
    int fallbackStatus = 0
)
{
    std::string detail;
    if (context != nullptr) {
        const char* errorText = smb2_get_error(context);
        if (errorText != nullptr) {
            detail = errorText;
        }
    }

    if (detail.empty() && fallbackStatus < 0) {
        const char* errorText = std::strerror(-fallbackStatus);
        if (errorText != nullptr) {
            detail = errorText;
        }
    }

    if (detail.empty()) {
        return prefix;
    }
    return prefix + ": " + detail;
}

} // namespace

class SMBClient::Impl {
public:
    explicit Impl(const Config& cfg) : config(cfg)
    {
        context = smb2_init_context();
        if (context == nullptr) {
            return;
        }

        smb2_set_authentication(context, SMB2_SEC_NTLMSSP);
        smb2_set_version(context, SMB2_VERSION_ANY);
        smb2_set_security_mode(context, SMB2_NEGOTIATE_SIGNING_ENABLED);
        smb2_set_timeout(context, std::max(1, config.timeoutMs / 1000));
        smb2_set_workstation(context, BuildWorkstation(config.workstation).c_str());

        if (!config.username.empty()) {
            smb2_set_user(context, config.username.c_str());
        }
        if (!config.password.empty()) {
            smb2_set_password(context, config.password.c_str());
        }
        if (!config.domain.empty()) {
            smb2_set_domain(context, config.domain.c_str());
        }
        if (config.enableEncryption) {
            smb2_set_seal(context, 1);
        }
    }

    ~Impl()
    {
        Disconnect();
        if (context != nullptr) {
            smb2_destroy_context(context);
            context = nullptr;
        }
    }

    Impl(const Impl&) = delete;
    Impl& operator=(const Impl&) = delete;

    bool Connect(Result* errorResult = nullptr)
    {
        if (connected) {
            return true;
        }
        if (context == nullptr) {
            if (errorResult != nullptr) {
                errorResult->success = false;
                errorResult->statusCode = ENOMEM;
                errorResult->message = "SMB 上下文未初始化";
            }
            return false;
        }

        const std::string serverTarget = BuildServerTarget(config.host, config.port);
        const char* userValue = config.username.empty() ? nullptr : config.username.c_str();
        OH_LOG_INFO(
            LOG_APP,
            "开始连接 SMB 共享: host=%{public}s port=%{public}d share=%{public}s target=%{public}s encryption=%{public}d",
            config.host.c_str(),
            config.port,
            config.shareName.c_str(),
            serverTarget.c_str(),
            config.enableEncryption ? 1 : 0
        );
        const int rc = smb2_connect_share(
            context,
            serverTarget.c_str(),
            config.shareName.c_str(),
            userValue
        );
        if (rc != 0) {
            const int statusCode = ConvertStatusCode(context, rc);
            const std::string errorMessage = BuildErrorMessage("连接 SMB 共享失败", context, rc);
            OH_LOG_ERROR(
                LOG_APP,
                "连接 SMB 共享失败: host=%{public}s port=%{public}d share=%{public}s rc=%{public}d ntStatus=%{public}d detail=%{public}s",
                config.host.c_str(),
                config.port,
                config.shareName.c_str(),
                rc,
                statusCode,
                errorMessage.c_str()
            );
            if (errorResult != nullptr) {
                errorResult->success = false;
                errorResult->statusCode = statusCode;
                errorResult->message = errorMessage;
            }
            return false;
        }

        connected = true;
        return true;
    }

    void Disconnect()
    {
        if (connected && context != nullptr) {
            smb2_disconnect_share(context);
            connected = false;
        }
    }

    bool EnsureConnected(Result* errorResult = nullptr)
    {
        if (connected) {
            return true;
        }
        return Connect(errorResult);
    }

    Result TestConnection(const std::string& remotePath)
    {
        Result result;
        const std::string normalizedPath = NormalizeRemotePath(remotePath);
        OH_LOG_INFO(
            LOG_APP,
            "开始测试 SMB 连接: host=%{public}s share=%{public}s path=%{public}s",
            config.host.c_str(),
            config.shareName.c_str(),
            normalizedPath.c_str()
        );

        if (!EnsureConnected(&result)) {
            return result;
        }

        if (!normalizedPath.empty()) {
            struct smb2dir* dir = smb2_opendir(context, normalizedPath.c_str());
            if (dir == nullptr) {
                result.success = false;
                result.statusCode = ConvertStatusCode(context, -ENOENT);
                result.message = BuildErrorMessage("访问 SMB 目录失败", context, -ENOENT);
                return result;
            }
            smb2_closedir(context, dir);
        }

        result.success = true;
        result.message = "SMB 连接成功";
        return result;
    }

    ListResult List(const std::string& remotePath)
    {
        ListResult result;
        Result connectResult;
        const std::string normalizedPath = NormalizeRemotePath(remotePath);
        OH_LOG_INFO(
            LOG_APP,
            "开始读取 SMB 目录: host=%{public}s share=%{public}s path=%{public}s",
            config.host.c_str(),
            config.shareName.c_str(),
            normalizedPath.c_str()
        );

        if (!EnsureConnected(&connectResult)) {
            result.success = false;
            result.statusCode = connectResult.statusCode;
            result.message = connectResult.message;
            return result;
        }

        struct smb2dir* dir = smb2_opendir(
            context,
            normalizedPath.empty() ? "" : normalizedPath.c_str()
        );
        if (dir == nullptr) {
            result.success = false;
            result.statusCode = ConvertStatusCode(context, -ENOENT);
            result.message = BuildErrorMessage("读取 SMB 目录失败", context, -ENOENT);
            return result;
        }

        struct smb2dirent* entry = nullptr;
        while ((entry = smb2_readdir(context, dir)) != nullptr) {
            if (entry->name == nullptr) {
                continue;
            }
            const std::string name = entry->name;
            if (name.empty() || name == "." || name == "..") {
                continue;
            }

            FileInfo fileInfo;
            fileInfo.name = name;
            fileInfo.path = JoinRemotePath(normalizedPath, name);
            fileInfo.isDirectory = entry->st.smb2_type == SMB2_TYPE_DIRECTORY;
            fileInfo.size = fileInfo.isDirectory ? 0 : static_cast<int64_t>(entry->st.smb2_size);
            fileInfo.lastModified = static_cast<int64_t>(entry->st.smb2_mtime) * 1000;
            result.files.push_back(fileInfo);
        }

        smb2_closedir(context, dir);
        result.success = true;
        result.message = "SMB 目录读取完成";
        return result;
    }

    Result DownloadFile(const std::string& remotePath, const std::string& localPath)
    {
        Result result;
        Result connectResult;
        const std::string normalizedPath = NormalizeRemotePath(remotePath);
        OH_LOG_INFO(
            LOG_APP,
            "开始下载 SMB 文件: host=%{public}s share=%{public}s path=%{public}s",
            config.host.c_str(),
            config.shareName.c_str(),
            normalizedPath.c_str()
        );

        if (!EnsureConnected(&connectResult)) {
            return connectResult;
        }

        struct smb2fh* fileHandle = smb2_open(context, normalizedPath.c_str(), O_RDONLY);
        if (fileHandle == nullptr) {
            result.success = false;
            result.statusCode = ConvertStatusCode(context, -ENOENT);
            result.message = BuildErrorMessage("打开 SMB 文件失败", context, -ENOENT);
            return result;
        }

        std::FILE* localFile = std::fopen(localPath.c_str(), "wb");
        if (localFile == nullptr) {
            const int fileError = errno;
            smb2_close(context, fileHandle);
            result.success = false;
            result.statusCode = fileError;
            result.message = "创建本地缓存文件失败: " + std::string(std::strerror(fileError));
            return result;
        }

        const uint32_t maxReadSize = smb2_get_max_read_size(context);
        const uint32_t chunkSize = maxReadSize > 0 ? maxReadSize : DEFAULT_READ_CHUNK;
        std::vector<uint8_t> buffer(chunkSize);
        uint64_t offset = 0;

        while (true) {
            const int bytesRead = smb2_pread(
                context,
                fileHandle,
                buffer.data(),
                chunkSize,
                offset
            );
            if (bytesRead == 0) {
                break;
            }
            if (bytesRead < 0) {
                std::fclose(localFile);
                smb2_close(context, fileHandle);
                result.success = false;
                result.statusCode = ConvertStatusCode(context, bytesRead);
                result.message = BuildErrorMessage("读取 SMB 文件失败", context, bytesRead);
                return result;
            }

            const size_t written = std::fwrite(buffer.data(), 1, static_cast<size_t>(bytesRead), localFile);
            if (written != static_cast<size_t>(bytesRead)) {
                std::fclose(localFile);
                smb2_close(context, fileHandle);
                result.success = false;
                result.statusCode = EIO;
                result.message = "写入本地缓存文件失败";
                return result;
            }

            offset += static_cast<uint64_t>(bytesRead);
        }

        std::fclose(localFile);
        smb2_close(context, fileHandle);
        result.success = true;
        result.message = "SMB 文件下载完成";
        return result;
    }

    Config config;
    struct smb2_context* context = nullptr;
    bool connected = false;
};

SMBClient::SMBClient(const Config& config) : pImpl(std::make_unique<Impl>(config)) {}

SMBClient::~SMBClient() = default;

Result SMBClient::testConnection(const std::string& remotePath)
{
    return pImpl->TestConnection(remotePath);
}

ListResult SMBClient::list(const std::string& remotePath)
{
    return pImpl->List(remotePath);
}

Result SMBClient::downloadFile(const std::string& remotePath, const std::string& localPath)
{
    return pImpl->DownloadFile(remotePath, localPath);
}

} // namespace smbnative
