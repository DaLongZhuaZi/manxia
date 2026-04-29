/**
 * Network Scanner Implementation
 * Single-connection two-phase probe: TCP connect + banner/request verification
 * Protocol detection reuses Phase 1 connections for speed
 */

#include "network_scanner.h"

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <hilog/log.h>
#include <smb2/smb2.h>
#include <smb2/libsmb2.h>
#include <smb2/libsmb2-raw.h>
#include <smb2/libsmb2-dcerpc-srvsvc.h>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3201
#define LOG_TAG "NetScanner"

namespace netscan {

namespace {

struct ProbePort {
    int port;
    Protocol protocol;
};

// All ports to probe
static const ProbePort kProbePorts[] = {
    // Standard ports
    { 21,   Protocol::FTP },
    { 22,   Protocol::SFTP },
    { 80,   Protocol::WEBDAV },
    { 443,  Protocol::WEBDAVS },
    { 445,  Protocol::SMB },
    { 990,  Protocol::FTPS },

    // NAS / alternative WebDAV ports
    { 139,  Protocol::SMB },        // SMB NetBIOS (legacy)
    { 5005, Protocol::WEBDAV },     // Synology WebDAV HTTP
    { 5006, Protocol::WEBDAVS },    // Synology WebDAV HTTPS
    { 8000, Protocol::WEBDAV },     // Asustor WebDAV HTTP
    { 8001, Protocol::WEBDAVS },    // Asustor WebDAV HTTPS
    { 8080, Protocol::WEBDAV },     // QNAP WebDAV HTTP / general alternative HTTP
    { 8443, Protocol::WEBDAVS },    // QNAP WebDAV HTTPS / general alternative HTTPS
};

static constexpr int kProbePortCount = static_cast<int>(sizeof(kProbePorts) / sizeof(kProbePorts[0]));
static constexpr int kParallelBatchSize = 32;

// Read available data from socket with timeout. Returns bytes read or -1.
static int ReadWithTimeout(int fd, char* buf, int maxLen, int timeoutMs)
{
    struct pollfd pfd{};
    pfd.fd = fd;
    pfd.events = POLLIN;
    pfd.revents = 0;

    const int pollRc = poll(&pfd, 1, timeoutMs);
    if (pollRc <= 0) return -1;
    if ((pfd.revents & (POLLIN | POLLHUP)) == 0) return -1;

    int totalRead = 0;
    while (totalRead < maxLen - 1) {
        const ssize_t n = read(fd, buf + totalRead, static_cast<size_t>(maxLen - 1 - totalRead));
        if (n <= 0) break;
        totalRead += static_cast<int>(n);
        // Check for line ending
        for (int k = totalRead - static_cast<int>(n); k < totalRead; k++) {
            if (buf[k] == '\n' || buf[k] == '\r') {
                buf[k] = '\0';
                return k > 0 ? k : totalRead;
            }
        }
        // Try to read more if available
        struct pollfd morePfd{};
        morePfd.fd = fd;
        morePfd.events = POLLIN;
        if (poll(&morePfd, 1, 0) <= 0) break;
        if ((morePfd.revents & POLLIN) == 0) break;
    }
    buf[totalRead] = '\0';
    return totalRead;
}

// Send data on socket with timeout. Returns bytes sent or -1.
static int SendWithTimeout(int fd, const char* data, int len, int timeoutMs)
{
    struct pollfd pfd{};
    pfd.fd = fd;
    pfd.events = POLLOUT;
    pfd.revents = 0;

    const int pollRc = poll(&pfd, 1, timeoutMs);
    if (pollRc <= 0) return -1;
    if ((pfd.revents & POLLOUT) == 0) return -1;

    const ssize_t sent = send(fd, data, static_cast<size_t>(len), MSG_NOSIGNAL);
    return static_cast<int>(sent);
}

// Convert string to lowercase in-place
static void ToLower(std::string& s)
{
    for (char& c : s) {
        c = static_cast<char>(tolower(static_cast<unsigned char>(c)));
    }
}

// ============================================================
// Protocol Verification Functions
// Each takes an already-connected fd and verifies the protocol
// ============================================================

// Verify FTP on an open connection: expect "220 ..." banner
static bool VerifyFTPOnFd(int fd, int timeoutMs)
{
    char buf[256] = {};
    const int n = ReadWithTimeout(fd, buf, sizeof(buf), timeoutMs);
    if (n < 3) return false;
    return strncmp(buf, "220", 3) == 0;
}

// Verify SSH/SFTP on an open connection: expect "SSH-..." banner
static bool VerifySSHOnFd(int fd, int timeoutMs)
{
    char buf[256] = {};
    const int n = ReadWithTimeout(fd, buf, sizeof(buf), timeoutMs);
    if (n < 4) return false;
    return strncmp(buf, "SSH-", 4) == 0;
}

// Verify WebDAV on an open connection: send HTTP OPTIONS, check response
static bool VerifyWebDAVOnFd(int fd, int port, int timeoutMs)
{
    // Build OPTIONS request with the actual port
    std::string req = "OPTIONS / HTTP/1.1\r\nHost: localhost";
    if (port != 80 && port != 443) {
        req += ":" + std::to_string(port);
    }
    req += "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";

    const int sent = SendWithTimeout(fd, req.c_str(), static_cast<int>(req.size()), timeoutMs);
    if (sent < 0) return false;

    char buf[2048] = {};
    const int n = ReadWithTimeout(fd, buf, sizeof(buf), timeoutMs);
    if (n < 10) return false;

    std::string resp(buf, static_cast<size_t>(n));
    std::string lower = resp;
    ToLower(lower);

    // Direct DAV header detection
    if (lower.find("dav:") != std::string::npos ||
        lower.find("dav/1") != std::string::npos ||
        lower.find("dav/2") != std::string::npos ||
        lower.find("ms-author-via") != std::string::npos) {
        return true;
    }

    // PROPFIND/PROPPATCH in Allow header
    if (lower.find("allow:") != std::string::npos &&
        (lower.find("propfind") != std::string::npos ||
         lower.find("mkcol") != std::string::npos ||
         lower.find("proppatch") != std::string::npos)) {
        return true;
    }

    // Check for common WebDAV server signatures
    if (lower.find("microsoft-iis") != std::string::npos) {
        return true;  // IIS with WebDAV module
    }

    // Accept any HTTP 2xx/3xx response on known WebDAV ports as potential WebDAV
    // The user can try connecting manually if it's not actually WebDAV
    if (resp.find("HTTP/1.") == 0) {
        // Check status code
        const size_t spacePos = resp.find(' ');
        if (spacePos != std::string::npos && spacePos + 3 < resp.size()) {
            const char sc = resp[spacePos + 1];
            if (sc == '2' || sc == '3') {
                // On dedicated WebDAV ports, any HTTP response is likely WebDAV
                if (port == 5005 || port == 5006 || port == 8000 || port == 8001) {
                    return true;
                }
                // On standard ports, check for more evidence
                if (lower.find("server:") != std::string::npos) {
                    if (lower.find("apache") != std::string::npos ||
                        lower.find("nginx") != std::string::npos ||
                        lower.find("lighttpd") != std::string::npos) {
                        return true;  // Common WebDAV-capable servers
                    }
                }
            }
        }
    }

    return false;
}

// Verify SMB on an open connection: send SMB negotiate, check for SMB response
static bool VerifySMBOnFd(int fd, int timeoutMs)
{
    // SMB1 Negotiate Protocol Request
    // This is the simplest way to detect SMB - send a minimal negotiate request
    // Dialects: PC NETWORK PROGRAM 1.0, LANMAN1.0, Windows for Workgroups 3.1a,
    //           LM1.2X002, LANMAN2.1, NT LM 0.12
    // Dialect data = 24+11+28+11+11+12 = 97 bytes
    // ByteCount = 97 (0x61), NetBIOS length = 32+1+2+97 = 132 (0x84)
    static const uint8_t smbNegotiate[] = {
        0x00, 0x00, 0x00, 0x84,  // NetBIOS session header: length = 132 bytes after header
        0xFF, 0x53, 0x4D, 0x42,  // SMB magic
        0x72,                      // Command: Negotiate Protocol
        0x00, 0x00, 0x00, 0x00,  // Status: Success
        0x18,                      // Flags
        0x53, 0xC8,              // Flags2
        0x00, 0x00,              // PID High
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Signature
        0x00, 0x00,              // Reserved
        0x00, 0x00,              // TID
        0xFE, 0xFF,              // PID
        0x00, 0x00,              // UID
        0x00, 0x00,              // MID
        0x00,                      // WordCount = 0
        0x61, 0x00,              // ByteCount = 97
        // Dialect strings (each prefixed with 0x02 buffer type, null-terminated)
        0x02, 'P', 'C', ' ', 'N', 'E', 'T', 'W', 'O', 'R', 'K', ' ',
              'P', 'R', 'O', 'G', 'R', 'A', 'M', ' ', '1', '.', '0', 0x00,  // 24 bytes
        0x02, 'L', 'A', 'N', 'M', 'A', 'N', '1', '.', '0', 0x00,            // 11 bytes
        0x02, 'W', 'i', 'n', 'd', 'o', 'w', 's', ' ', 'f', 'o', 'r', ' ',
              'W', 'o', 'r', 'k', 'g', 'r', 'o', 'u', 'p', 's', ' ',
              '3', '.', '1', 'a', 0x00,                                       // 28 bytes
        0x02, 'L', 'M', '1', '.', '2', 'X', '0', '0', '2', 0x00,            // 11 bytes
        0x02, 'L', 'A', 'N', 'M', 'A', 'N', '2', '.', '1', 0x00,            // 11 bytes
        0x02, 'N', 'T', ' ', 'L', 'M', ' ', '0', '.', '1', '2', 0x00,       // 12 bytes
    };

    const int sent = SendWithTimeout(fd, reinterpret_cast<const char*>(smbNegotiate),
                                     static_cast<int>(sizeof(smbNegotiate)), timeoutMs);
    if (sent < 0) return false;

    char buf[256] = {};
    const int n = ReadWithTimeout(fd, buf, sizeof(buf), timeoutMs);
    if (n < 4) return false;

    // Check for SMB response magic: 0xFF 0x53 0x4D 0x42
    // Or SMB2 response: 0xFE 0x53 0x4D 0x42
    if (n >= 8) {
        if ((buf[4] == '\xFF' && buf[5] == 'S' && buf[6] == 'M' && buf[7] == 'B') ||
            (buf[4] == '\xFE' && buf[5] == 'S' && buf[6] == 'M' && buf[7] == 'B')) {
            return true;
        }
    }

    // Also check for NetBIOS session positive response (0x82)
    if (n >= 1 && static_cast<uint8_t>(buf[0]) == 0x82) {
        return true;
    }

    return false;
}

// ============================================================
// ProbeResult and ProbeHost
// ============================================================

struct ProbeResult {
    std::vector<Protocol> protocols;
    std::vector<ProtocolPort> protocolPorts;
};

// Single-connection probe: connect once, verify protocol on same connection
static ProbeResult ProbeHost(const std::string& ip, int timeoutMs)
{
    ProbeResult result;

    // Phase 1: Connect to all ports in parallel using non-blocking sockets
    struct ConnectEntry {
        int fd;
        int portIndex;
        bool connected;
    };

    std::vector<ConnectEntry> entries;
    entries.reserve(kProbePortCount);

    struct sockaddr_in addr{};
    addr.sin_family = AF_INET;
    inet_pton(AF_INET, ip.c_str(), &addr.sin_addr);

    // Create all sockets and start connections
    for (int i = 0; i < kProbePortCount; i++) {
        const int port = kProbePorts[i].port;
        addr.sin_port = htons(static_cast<uint16_t>(port));

        const int fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
        if (fd < 0) continue;

        const int rc = connect(fd, reinterpret_cast<struct sockaddr*>(&addr), sizeof(addr));
        if (rc == 0) {
            // Connected immediately
            entries.push_back({fd, i, true});
        } else if (errno == EINPROGRESS) {
            entries.push_back({fd, i, false});
        } else {
            close(fd);
        }
    }

    // Poll all sockets for connection completion
    if (!entries.empty()) {
        std::vector<struct pollfd> pollfds;
        for (const auto& e : entries) {
            if (!e.connected) {
                struct pollfd pfd{};
                pfd.fd = e.fd;
                pfd.events = POLLOUT;
                pfd.revents = 0;
                pollfds.push_back(pfd);
            }
        }

        if (!pollfds.empty()) {
            const int pollRc = poll(pollfds.data(), static_cast<nfds_t>(pollfds.size()), timeoutMs);
            if (pollRc > 0) {
                size_t pfdIdx = 0;
                for (auto& e : entries) {
                    if (!e.connected) {
                        if (pfdIdx < pollfds.size()) {
                            if ((pollfds[pfdIdx].revents & POLLOUT) != 0) {
                                int sockErr = 0;
                                socklen_t errLen = sizeof(sockErr);
                                getsockopt(e.fd, SOL_SOCKET, SO_ERROR, &sockErr, &errLen);
                                e.connected = (sockErr == 0);
                            }
                            pfdIdx++;
                        }
                    }
                }
            }
        }
    }

    // Phase 2: Verify protocols on connected sockets (reuses the same connection)
    for (auto& e : entries) {
        if (!e.connected) {
            close(e.fd);
            continue;
        }

        const int port = kProbePorts[e.portIndex].port;
        const Protocol proto = kProbePorts[e.portIndex].protocol;
        bool verified = false;

        switch (proto) {
            case Protocol::FTP:
                verified = VerifyFTPOnFd(e.fd, timeoutMs);
                break;
            case Protocol::SFTP:
                verified = VerifySSHOnFd(e.fd, timeoutMs);
                break;
            case Protocol::WEBDAV:
            case Protocol::WEBDAVS:
                verified = VerifyWebDAVOnFd(e.fd, port, timeoutMs);
                break;
            case Protocol::SMB:
                verified = VerifySMBOnFd(e.fd, timeoutMs);
                break;
            case Protocol::FTPS:
                verified = VerifyFTPOnFd(e.fd, timeoutMs);
                break;
        }

        close(e.fd);

        if (verified) {
            result.protocols.push_back(proto);
            result.protocolPorts.push_back({proto, port});
            OH_LOG_INFO(LOG_APP, "ProbeHost %{public}s:%d -> %{public}s ✓",
                        ip.c_str(), port,
                        proto == Protocol::FTP ? "FTP" :
                        proto == Protocol::SFTP ? "SFTP" :
                        proto == Protocol::WEBDAV ? "WebDAV" :
                        proto == Protocol::WEBDAVS ? "WebDAVS" :
                        proto == Protocol::SMB ? "SMB" :
                        proto == Protocol::FTPS ? "FTPS" : "?");
        }
    }

    return result;
}

} // anonymous namespace

class NetworkScanner::Impl {
public:
    std::atomic<bool> scanning{false};
    std::atomic<bool> cancelFlag{false};
    std::mutex callbackMutex;

    void RunScan(const ScanConfig& config,
                 ScanProgressCallback onProgress,
                 HostFoundCallback onHostFound,
                 ScanCompleteCallback onComplete)
    {
        scanning.store(true);
        cancelFlag.store(false);

        const auto scanStartTime = std::chrono::steady_clock::now();

        std::atomic<int> scannedCount{0};
        std::atomic<int> foundCount{0};
        const int totalHosts = 254;
        const int timeoutMs = std::max(100, config.hostTimeoutMs);

        OH_LOG_INFO(LOG_APP, "===== Network Scan Started =====");
        OH_LOG_INFO(LOG_APP, "Subnet: %{public}s.0/24, timeout: %dms, batch: %d, ports: %d",
                    config.subnetBase.c_str(), timeoutMs, kParallelBatchSize, kProbePortCount);

        for (int batchStart = 1; batchStart <= totalHosts; batchStart += kParallelBatchSize) {
            if (cancelFlag.load()) {
                OH_LOG_INFO(LOG_APP, "Scan cancelled at host %d/%d", scannedCount.load(), totalHosts);
                onComplete(true);
                scanning.store(false);
                return;
            }

            const int batchEnd = std::min(batchStart + kParallelBatchSize - 1, totalHosts);
            std::vector<std::thread> threads;

            for (int i = batchStart; i <= batchEnd; i++) {
                const std::string ip = config.subnetBase + "." + std::to_string(i);

                threads.emplace_back([this, ip, timeoutMs, &scannedCount, totalHosts, &foundCount,
                                      &onProgress, &onHostFound]() {
                    if (cancelFlag.load()) {
                        scannedCount.fetch_add(1);
                        return;
                    }

                    const auto hostStart = std::chrono::steady_clock::now();
                    auto probeResult = ProbeHost(ip, timeoutMs);
                    const auto hostEnd = std::chrono::steady_clock::now();
                    const int hostMs = static_cast<int>(
                        std::chrono::duration_cast<std::chrono::milliseconds>(hostEnd - hostStart).count());

                    const int current = scannedCount.fetch_add(1) + 1;
                    {
                        std::lock_guard<std::mutex> lock(callbackMutex);
                        onProgress(current, totalHosts, ip);
                    }

                    if (!probeResult.protocols.empty()) {
                        const int fc = foundCount.fetch_add(1) + 1;
                        DiscoveredHost host;
                        host.ip = ip;
                        host.hostname = "";
                        host.protocols = std::move(probeResult.protocols);
                        host.protocolPorts = std::move(probeResult.protocolPorts);

                        // Build log string
                        std::string protoList;
                        for (size_t p = 0; p < host.protocolPorts.size(); p++) {
                            if (p > 0) protoList += ",";
                            switch (host.protocolPorts[p].protocol) {
                                case Protocol::FTP: protoList += "FTP:"; break;
                                case Protocol::SFTP: protoList += "SFTP:"; break;
                                case Protocol::FTPS: protoList += "FTPS:"; break;
                                case Protocol::WEBDAV: protoList += "WebDAV:"; break;
                                case Protocol::WEBDAVS: protoList += "WebDAVS:"; break;
                                case Protocol::SMB: protoList += "SMB:"; break;
                            }
                            protoList += std::to_string(host.protocolPorts[p].port);
                        }

                        {
                            std::lock_guard<std::mutex> lock(callbackMutex);
                            OH_LOG_INFO(LOG_APP, "Host #%d: %{public}s [%{public}s] in %dms",
                                        fc, ip.c_str(), protoList.c_str(), hostMs);
                            onHostFound(host);
                        }
                    }
                });
            }

            for (auto& t : threads) {
                if (t.joinable()) {
                    t.join();
                }
            }
        }

        const auto scanEndTime = std::chrono::steady_clock::now();
        const int totalMs = static_cast<int>(
            std::chrono::duration_cast<std::chrono::milliseconds>(scanEndTime - scanStartTime).count());

        OH_LOG_INFO(LOG_APP, "===== Network Scan Complete =====");
        OH_LOG_INFO(LOG_APP, "Duration: %dms, Scanned: %d/%d, Found: %{public}d hosts",
                    totalMs, scannedCount.load(), totalHosts, foundCount.load());

        onComplete(false);
        scanning.store(false);
    }
};

NetworkScanner::NetworkScanner() : pImpl(std::make_unique<Impl>()) {}

NetworkScanner::~NetworkScanner() = default;

void NetworkScanner::startScan(const ScanConfig& config,
                               ScanProgressCallback onProgress,
                               HostFoundCallback onHostFound,
                               ScanCompleteCallback onComplete)
{
    if (pImpl->scanning.load()) {
        return;
    }

    std::thread([this, config,
                 onProgress = std::move(onProgress),
                 onHostFound = std::move(onHostFound),
                 onComplete = std::move(onComplete)]() mutable {
        pImpl->RunScan(config, std::move(onProgress), std::move(onHostFound), std::move(onComplete));
    }).detach();
}

void NetworkScanner::cancelScan()
{
    pImpl->cancelFlag.store(true);
}

bool NetworkScanner::isScanning() const
{
    return pImpl->scanning.load();
}

SMBEnumResult NetworkScanner::enumerateSMBShares(const SMBEnumConfig& config)
{
    SMBEnumResult result;

    struct smb2_context* smb2 = smb2_init_context();
    if (smb2 == nullptr) {
        result.message = "Failed to init SMB context";
        return result;
    }

    smb2_set_security_mode(smb2, SMB2_NEGOTIATE_SIGNING_ENABLED);
    smb2_set_timeout(smb2, std::max(1, config.timeoutMs / 1000));

    if (!config.username.empty()) {
        smb2_set_user(smb2, config.username.c_str());
    }
    if (!config.password.empty()) {
        smb2_set_password(smb2, config.password.c_str());
    }
    if (!config.domain.empty()) {
        smb2_set_domain(smb2, config.domain.c_str());
    }

    const std::string server = (config.port != 445)
        ? config.host + ":" + std::to_string(config.port)
        : config.host;

    OH_LOG_INFO(LOG_APP, "SMB enum: connecting to %{public}s IPC$", server.c_str());

    const int rc = smb2_connect_share(smb2, server.c_str(), "IPC$", nullptr);
    if (rc < 0) {
        result.message = std::string("Failed to connect to IPC$: ") + smb2_get_error(smb2);
        OH_LOG_WARN(LOG_APP, "SMB enum connect failed: %{public}s", result.message.c_str());
        smb2_destroy_context(smb2);
        return result;
    }

    struct srvsvc_NetrShareEnum_rep* rep = smb2_share_enum_sync(smb2, SHARE_INFO_1);
    if (rep == nullptr) {
        result.message = std::string("Share enum failed: ") + smb2_get_error(smb2);
        OH_LOG_WARN(LOG_APP, "SMB enum failed: %{public}s", result.message.c_str());
        smb2_disconnect_share(smb2);
        smb2_destroy_context(smb2);
        return result;
    }

    result.success = true;
    result.message = "OK";

    if (rep->ses.Level == SHARE_INFO_1 && rep->ses.ShareInfo.Level1.Buffer != nullptr) {
        const int count = static_cast<int>(rep->ses.ShareInfo.Level1.EntriesRead);
        OH_LOG_INFO(LOG_APP, "SMB enum: found %d shares", count);
        for (int i = 0; i < count; i++) {
            const auto& entry = rep->ses.ShareInfo.Level1.Buffer->share_info_1[i];
            SMBShareInfo share;
            share.name = entry.netname.utf8 ? entry.netname.utf8 : "";
            share.remark = entry.remark.utf8 ? entry.remark.utf8 : "";
            share.type = entry.type;
            share.isHidden = (entry.type & 0x80000000) != 0;
            share.isDiskShare = (entry.type & 3) == 0;
            result.shares.push_back(std::move(share));
        }
    }

    smb2_free_data(smb2, rep);
    smb2_disconnect_share(smb2);
    smb2_destroy_context(smb2);
    return result;
}

} // namespace netscan
