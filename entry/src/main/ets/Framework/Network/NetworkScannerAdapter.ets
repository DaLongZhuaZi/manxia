/**
 * Network Scanner Adapter
 * ArkTS wrapper for native network scanner + gateway detection
 */

import { connection } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';
import {
  NetworkScanHost,
  NetworkSMBShare,
  NetworkSMBEnumResult,
  ProtocolPort
} from '../../Models/NetworkFolderModels';
import webdavNativeModuleImport from 'libwebdav_native.so';

const TAG = 'NetScannerAdapter';

interface NativeScanConfig {
  subnetBase: string;
  hostTimeoutMs?: number;
}

interface NativeProtocolPort {
  protocol: number;
  port: number;
}

interface NativeDiscoveredHost {
  ip: string;
  hostname: string;
  protocols: number[];
  protocolPorts: NativeProtocolPort[];
}

interface NativeSMBEnumConfig {
  host: string;
  port?: number;
  username?: string;
  password?: string;
  domain?: string;
  timeoutMs?: number;
}

interface NativeSMBShareInfo {
  name: string;
  remark: string;
  type: number;
  isHidden: boolean;
  isDiskShare: boolean;
}

interface NativeSMBEnumResult {
  success: boolean;
  message: string;
  shares: NativeSMBShareInfo[];
}

interface ScannerNativeModule {
  scanStart(
    config: NativeScanConfig,
    onProgress: (scanned: number, total: number, currentIP: string) => void,
    onHostFound: (host: NativeDiscoveredHost) => void,
    onComplete: (cancelled: boolean) => void
  ): void;
  scanStop(): void;
  scanIsRunning(): boolean;
  smbEnumShares(config: NativeSMBEnumConfig): NativeSMBEnumResult;
}

let nativeModule: ScannerNativeModule | null = null;
let nativeModuleChecked: boolean = false;

function getNativeModule(): ScannerNativeModule | null {
  if (nativeModuleChecked) {
    return nativeModule;
  }
  nativeModuleChecked = true;
  try {
    if (webdavNativeModuleImport) {
      const mod = webdavNativeModuleImport as ScannerNativeModule;
      if (typeof mod.scanStart === 'function') {
        nativeModule = mod;
        logger.info(TAG, 'Scanner Native模块加载成功');
      } else {
        logger.warn(TAG, 'Scanner Native方法不可用');
      }
    }
  } catch (error) {
    logger.error(TAG, `Scanner Native模块加载失败：${String(error)}`);
  }
  return nativeModule;
}

export class NetworkScannerAdapter {
  public isAvailable(): boolean {
    return getNativeModule() !== null;
  }

  public getLocalSubnet(): string {
    try {
      const netHandle: connection.NetHandle = connection.getDefaultNetSync();
      const properties: connection.ConnectionProperties = connection.getConnectionPropertiesSync(netHandle);

      // Try to get subnet from default route gateway
      const routes: connection.RouteInfo[] = properties.routes;
      for (const route of routes) {
        if (route.isDefaultRoute && route.hasGateway) {
          const gatewayIP: string = route.gateway.address;
          const parts: string[] = gatewayIP.split('.');
          if (parts.length >= 3) {
            const subnet: string = `${parts[0]}.${parts[1]}.${parts[2]}`;
            logger.info(TAG, `从网关推断子网: ${subnet}.0/24 (网关: ${gatewayIP})`);
            return subnet;
          }
        }
      }

      // Fallback: extract from local IP
      const linkAddresses: connection.LinkAddress[] = properties.linkAddresses;
      if (linkAddresses.length > 0) {
        const localIP: string = linkAddresses[0].address.address;
        const parts: string[] = localIP.split('.');
        if (parts.length >= 3) {
          const subnet: string = `${parts[0]}.${parts[1]}.${parts[2]}`;
          logger.info(TAG, `从本地IP推断子网: ${subnet}.0/24`);
          return subnet;
        }
      }
    } catch (error) {
      logger.error(TAG, `获取子网失败: ${String(error)}`);
    }
    logger.warn(TAG, '无法检测子网，使用默认值 192.168.1');
    return '192.168.1';
  }

  public startScan(
    subnetBase: string,
    onProgress: (scanned: number, total: number, currentIP: string) => void,
    onHostFound: (host: NetworkScanHost) => void,
    onComplete: (cancelled: boolean) => void
  ): boolean {
    const mod = getNativeModule();
    if (!mod) {
      logger.error(TAG, 'Scanner模块未加载，无法开始扫描');
      return false;
    }

    const config: NativeScanConfig = {
      subnetBase: subnetBase,
      hostTimeoutMs: 200
    };

    logger.info(TAG, `启动扫描：子网=${subnetBase}.0/24，超时=${config.hostTimeoutMs}ms`);

    try {
      const startTime = Date.now();
      mod.scanStart(config,
        (scanned: number, total: number, currentIP: string) => {
          onProgress(scanned, total, currentIP);
        },
        (nativeHost: NativeDiscoveredHost) => {
          // Map protocolPorts from native
          const protocolPorts: ProtocolPort[] = [];
          if (nativeHost.protocolPorts) {
            for (const pp of nativeHost.protocolPorts) {
              protocolPorts.push({ protocol: pp.protocol, port: pp.port });
            }
          }

          const host: NetworkScanHost = {
            ip: nativeHost.ip,
            hostname: nativeHost.hostname,
            protocols: nativeHost.protocols,
            protocolPorts: protocolPorts
          };

          // Build detailed log with ports
          const protoNames: string[] = [];
          for (const pp of protocolPorts) {
            if (pp.protocol === 0) protoNames.push(`FTP:${pp.port}`);
            else if (pp.protocol === 1) protoNames.push(`SFTP:${pp.port}`);
            else if (pp.protocol === 2) protoNames.push(`FTPS:${pp.port}`);
            else if (pp.protocol === 3) protoNames.push(`WebDAV:${pp.port}`);
            else if (pp.protocol === 4) protoNames.push(`WebDAVS:${pp.port}`);
            else if (pp.protocol === 5) protoNames.push(`SMB:${pp.port}`);
            else protoNames.push(`Unknown(${pp.protocol}):${pp.port}`);
          }
          logger.info(TAG, `发现主机: ${nativeHost.ip} [${protoNames.join(', ')}]`);
          onHostFound(host);
        },
        (cancelled: boolean) => {
          const duration = Date.now() - startTime;
          logger.info(TAG, `扫描完成：耗时=${duration}ms，取消=${cancelled}`);
          onComplete(cancelled);
        }
      );
      logger.info(TAG, `扫描已在原生层启动`);
      return true;
    } catch (error) {
      logger.error(TAG, `启动扫描失败：${String(error)}`);
      return false;
    }
  }

  public stopScan(): void {
    const mod = getNativeModule();
    if (!mod) {
      return;
    }
    try {
      mod.scanStop();
      logger.info(TAG, '网络扫描已停止');
    } catch (error) {
      logger.error(TAG, `停止扫描失败：${String(error)}`);
    }
  }

  public isScanning(): boolean {
    const mod = getNativeModule();
    if (!mod) {
      return false;
    }
    try {
      return mod.scanIsRunning();
    } catch {
      return false;
    }
  }

  public enumSMBShares(
    host: string,
    port: number = 445,
    username: string = '',
    password: string = '',
    domain: string = ''
  ): NetworkSMBEnumResult {
    const mod = getNativeModule();
    if (!mod) {
      return { success: false, message: 'Scanner模块未加载', shares: [] };
    }

    try {
      const config: NativeSMBEnumConfig = {
        host: host,
        port: port,
        username: username,
        password: password,
        domain: domain,
        timeoutMs: 10000
      };
      const nativeResult = mod.smbEnumShares(config);
      const mappedShares: NetworkSMBShare[] = [];
      for (const s of nativeResult.shares) {
        const share: NetworkSMBShare = {
          name: s.name,
          remark: s.remark,
          type: s.type,
          isHidden: s.isHidden,
          isDiskShare: s.isDiskShare
        };
        mappedShares.push(share);
      }
      const result: NetworkSMBEnumResult = {
        success: nativeResult.success,
        message: nativeResult.message,
        shares: mappedShares
      };
      return result;
    } catch (error) {
      const errResult: NetworkSMBEnumResult = { success: false, message: `枚举共享失败：${String(error)}`, shares: [] };
      return errResult;
    }
  }
}
