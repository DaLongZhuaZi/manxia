/**
 * Network Scanner Header
 * LAN file server discovery via TCP port probing and SMB share enumeration
 */

#ifndef NETWORK_SCANNER_H
#define NETWORK_SCANNER_H

#include <atomic>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace netscan {

enum class Protocol : int {
    FTP = 0,
    SFTP = 1,
    FTPS = 2,
    WEBDAV = 3,
    WEBDAVS = 4,
    SMB = 5
};

struct ProtocolPort {
    Protocol protocol;
    int port;
};

struct DiscoveredHost {
    std::string ip;
    std::string hostname;
    std::vector<Protocol> protocols;
    std::vector<ProtocolPort> protocolPorts;  // protocol + actual port
};

struct SMBShareInfo {
    std::string name;
    std::string remark;
    uint32_t type = 0;
    bool isHidden = false;
    bool isDiskShare = false;
};

struct ScanConfig {
    std::string subnetBase;   // "192.168.1" -> scan .1 through .254
    int hostTimeoutMs = 200;
};

struct SMBEnumConfig {
    std::string host;
    int port = 445;
    std::string username;
    std::string password;
    std::string domain;
    int timeoutMs = 10000;
};

using ScanProgressCallback = std::function<void(int scanned, int total, const std::string& currentIP)>;
using HostFoundCallback = std::function<void(const DiscoveredHost& host)>;
using ScanCompleteCallback = std::function<void(bool cancelled)>;

struct SMBEnumResult {
    bool success = false;
    std::string message;
    std::vector<SMBShareInfo> shares;
};

class NetworkScanner {
public:
    NetworkScanner();
    ~NetworkScanner();

    NetworkScanner(const NetworkScanner&) = delete;
    NetworkScanner& operator=(const NetworkScanner&) = delete;

    void startScan(const ScanConfig& config,
                   ScanProgressCallback onProgress,
                   HostFoundCallback onHostFound,
                   ScanCompleteCallback onComplete);

    void cancelScan();
    bool isScanning() const;

    SMBEnumResult enumerateSMBShares(const SMBEnumConfig& config);

private:
    class Impl;
    std::unique_ptr<Impl> pImpl;
};

} // namespace netscan

#endif // NETWORK_SCANNER_H
