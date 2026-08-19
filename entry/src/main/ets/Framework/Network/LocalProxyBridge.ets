import socket from '@ohos.net.socket';
import { connection } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'LocalProxyBridge';

export enum LocalProxyBridgeUpstreamProtocol {
  HTTP = 'HTTP',
  SOCKS5 = 'SOCKS5'
}

export interface LocalProxyBridgeConfig {
  upstreamProtocol: LocalProxyBridgeUpstreamProtocol;
  upstreamHost: string;
  upstreamPort: number;
  upstreamAuthEnabled: boolean;
  upstreamUsername: string;
  upstreamPassword: string;
}

interface ProxyTarget {
  host: string;
  port: number;
  requestLine: string;
}

interface BridgeConnectionState {
  client: socket.TCPSocketConnection;
  upstream: socket.TCPSocket | null;
  firstPacketHandled: boolean;
  pending: Uint8Array;
  tunnelEstablished: boolean;
  waitingHttpProxyConnect: boolean;
  closing: boolean;
}

export class LocalProxyBridge {
  private server: socket.TCPSocketServer | null = null;
  private activePort: number = 0;
  private config: LocalProxyBridgeConfig | null = null;
  private connections: Map<number, BridgeConnectionState> = new Map<number, BridgeConnectionState>();
  private decoder: util.TextDecoder = new util.TextDecoder('utf-8');
  private encoder: util.TextEncoder = new util.TextEncoder();

  getPort(): number {
    return this.activePort;
  }

  isRunningFor(config: LocalProxyBridgeConfig): boolean {
    if (this.server === null || this.config === null || this.activePort <= 0) {
      return false;
    }
    return this.config.upstreamProtocol === config.upstreamProtocol &&
      this.config.upstreamHost === config.upstreamHost &&
      this.config.upstreamPort === config.upstreamPort &&
      this.config.upstreamAuthEnabled === config.upstreamAuthEnabled &&
      this.config.upstreamUsername === config.upstreamUsername &&
      this.config.upstreamPassword === config.upstreamPassword;
  }

  async start(config: LocalProxyBridgeConfig): Promise<number> {
    if (this.isRunningFor(config)) {
      return this.activePort;
    }
    await this.stop();

    const server = socket.constructTCPSocketServerInstance();
    server.on('connect', (clientConnection: socket.TCPSocketConnection) => {
      this.handleClientConnect(clientConnection);
    });
    server.on('error', (error: Error) => {
      logger.error(TAG, `本地代理桥异常: ${String(error)}`);
    });

    const listenAddress: connection.NetAddress = {
      address: '127.0.0.1',
      family: 1,
      port: 0
    };
    await server.listen(listenAddress);
    const localAddress = await server.getLocalAddress();

    this.server = server;
    this.activePort = localAddress.port !== undefined ? localAddress.port : 0;
    this.config = this.copyConfig(config);
    logger.info(TAG, `本地代理桥已启动: 127.0.0.1:${this.activePort}, upstream=${config.upstreamProtocol}:${config.upstreamHost}:${config.upstreamPort}, auth=${config.upstreamAuthEnabled}`);
    return this.activePort;
  }

  async stop(): Promise<void> {
    const states: BridgeConnectionState[] = [];
    this.connections.forEach((state: BridgeConnectionState) => {
      states.push(state);
    });
    for (let i = 0; i < states.length; i++) {
      await this.closeState(states[i]);
    }
    this.connections.clear();

    if (this.server !== null) {
      try {
        this.server.off('connect');
        this.server.off('error');
        await this.server.close();
      } catch (error) {
        logger.warn(TAG, `关闭本地代理桥失败: ${String(error)}`);
      }
    }
    this.server = null;
    this.activePort = 0;
    this.config = null;
  }

  private copyConfig(config: LocalProxyBridgeConfig): LocalProxyBridgeConfig {
    const copied: LocalProxyBridgeConfig = {
      upstreamProtocol: config.upstreamProtocol,
      upstreamHost: config.upstreamHost,
      upstreamPort: config.upstreamPort,
      upstreamAuthEnabled: config.upstreamAuthEnabled,
      upstreamUsername: config.upstreamUsername,
      upstreamPassword: config.upstreamPassword
    };
    return copied;
  }

  private handleClientConnect(clientConnection: socket.TCPSocketConnection): void {
    const state: BridgeConnectionState = {
      client: clientConnection,
      upstream: null,
      firstPacketHandled: false,
      pending: new Uint8Array(0),
      tunnelEstablished: false,
      waitingHttpProxyConnect: false,
      closing: false
    };
    this.connections.set(clientConnection.clientId, state);

    clientConnection.on('message', (messageInfo: socket.SocketMessageInfo) => {
      void this.handleClientMessage(state, new Uint8Array(messageInfo.message));
    });
    clientConnection.on('close', () => {
      void this.closeState(state);
    });
    clientConnection.on('error', (error: Error) => {
      logger.warn(TAG, `本地代理客户端连接异常: client=${clientConnection.clientId}, error=${String(error)}`);
      void this.closeState(state);
    });
  }

  private async handleClientMessage(state: BridgeConnectionState, data: Uint8Array): Promise<void> {
    if (state.closing) {
      return;
    }
    if (state.tunnelEstablished && state.upstream !== null) {
      await state.upstream.send({ data: data.buffer });
      return;
    }
    if (state.firstPacketHandled && state.upstream !== null) {
      await state.upstream.send({ data: data.buffer });
      return;
    }

    state.pending = this.concatBytes(state.pending, data);
    const headerEnd = this.findHeaderEnd(state.pending);
    if (headerEnd < 0) {
      return;
    }

    if (state.firstPacketHandled) {
      if (state.upstream !== null) {
        await state.upstream.send({ data: data.buffer });
      }
      return;
    }

    state.firstPacketHandled = true;
    const headerBytes = state.pending.slice(0, headerEnd);
    const bodyBytes = state.pending.slice(headerEnd);
    state.pending = new Uint8Array(0);
    const headerText = this.decodeBytes(headerBytes);
    const firstLineEnd = headerText.indexOf('\r\n');
    const requestLine = firstLineEnd >= 0 ? headerText.substring(0, firstLineEnd) : headerText;
    const method = this.readRequestMethod(requestLine);

    try {
      if (method === 'CONNECT') {
        const target = this.parseConnectTarget(requestLine);
        if (this.isHttpUpstreamProxy()) {
          await this.connectHttpProxyUpstream(state);
          state.waitingHttpProxyConnect = true;
          const proxiedHeader = this.addProxyAuthorizationHeader(headerText);
          if (state.upstream !== null) {
            await state.upstream.send({ data: this.encodeString(proxiedHeader).buffer });
          }
          return;
        }
        await this.connectUpstream(state, target.host, target.port);
        state.tunnelEstablished = true;
        await state.client.send({ data: 'HTTP/1.1 200 Connection Established\r\n\r\n', encoding: 'utf-8' });
        if (bodyBytes.length > 0 && state.upstream !== null) {
          await state.upstream.send({ data: bodyBytes.buffer });
        }
        return;
      }

      const target = this.parseHttpTarget(requestLine, headerText);
      if (this.isHttpUpstreamProxy()) {
        await this.connectHttpProxyUpstream(state);
        const proxiedHeader = this.addProxyAuthorizationHeader(headerText);
        const proxiedPacket = this.concatBytes(this.encodeString(proxiedHeader), bodyBytes);
        if (state.upstream !== null) {
          await state.upstream.send({ data: proxiedPacket.buffer });
        }
        return;
      }
      await this.connectUpstream(state, target.host, target.port);
      const rewritten = this.rewriteHttpHeader(headerText, target.requestLine);
      const rewrittenBytes = this.encodeString(rewritten);
      const packet = this.concatBytes(rewrittenBytes, bodyBytes);
      if (state.upstream !== null) {
        await state.upstream.send({ data: packet.buffer });
      }
    } catch (error) {
      logger.warn(TAG, `本地代理请求转发失败: ${String(error)}`);
      await this.sendBadGateway(state);
      await this.closeState(state);
    }
  }

  private async connectUpstream(state: BridgeConnectionState, host: string, port: number): Promise<void> {
    if (this.config === null) {
      throw new Error('本地代理桥未配置');
    }

    const upstream = socket.constructTCPSocketInstance();
    upstream.on('message', (messageInfo: socket.SocketMessageInfo) => {
      if (state.waitingHttpProxyConnect) {
        void this.handleHttpProxyConnectResponse(state, new Uint8Array(messageInfo.message));
        return;
      }
      void state.client.send({ data: messageInfo.message });
    });
    upstream.on('close', () => {
      void this.closeState(state);
    });
    upstream.on('error', (error: Error) => {
      logger.warn(TAG, `代理桥上游连接异常: target=${host}:${port}, error=${String(error)}`);
      void this.closeState(state);
    });

    const upstreamAddress: connection.NetAddress = {
      address: host,
      family: 1,
      port: port
    };
    const socksAddress: connection.NetAddress = {
      address: this.config.upstreamHost,
      family: 1,
      port: this.config.upstreamPort
    };
    const proxyOptions: socket.ProxyOptions = {
      type: socket.ProxyTypes.SOCKS5,
      address: socksAddress
    };
    if (this.config.upstreamAuthEnabled) {
      proxyOptions.username = this.config.upstreamUsername;
      proxyOptions.password = this.config.upstreamPassword;
    }
    const connectOptions: socket.TCPConnectOptions = {
      address: upstreamAddress,
      proxy: proxyOptions
    };
    await upstream.connect(connectOptions);
    state.upstream = upstream;
  }

  private async connectHttpProxyUpstream(state: BridgeConnectionState): Promise<void> {
    if (this.config === null) {
      throw new Error('HTTP代理桥未配置');
    }
    const upstream = socket.constructTCPSocketInstance();
    upstream.on('message', (messageInfo: socket.SocketMessageInfo) => {
      if (state.waitingHttpProxyConnect) {
        void this.handleHttpProxyConnectResponse(state, new Uint8Array(messageInfo.message));
        return;
      }
      void state.client.send({ data: messageInfo.message });
    });
    upstream.on('close', () => {
      void this.closeState(state);
    });
    upstream.on('error', (error: Error) => {
      logger.warn(TAG, `HTTP代理上游连接异常: proxy=${this.config?.upstreamHost}:${this.config?.upstreamPort}, error=${String(error)}`);
      void this.closeState(state);
    });

    const proxyAddress: connection.NetAddress = {
      address: this.config.upstreamHost,
      family: 1,
      port: this.config.upstreamPort
    };
    const connectOptions: socket.TCPConnectOptions = {
      address: proxyAddress
    };
    await upstream.connect(connectOptions);
    state.upstream = upstream;
  }

  private async handleHttpProxyConnectResponse(state: BridgeConnectionState, data: Uint8Array): Promise<void> {
    await state.client.send({ data: data.buffer });
    const text = this.decodeBytes(data);
    const headerEnd = text.indexOf('\r\n\r\n');
    if (headerEnd < 0) {
      return;
    }
    const firstLineEnd = text.indexOf('\r\n');
    const statusLine = firstLineEnd >= 0 ? text.substring(0, firstLineEnd) : text;
    if (statusLine.includes(' 200 ')) {
      state.waitingHttpProxyConnect = false;
      state.tunnelEstablished = true;
      return;
    }
    logger.warn(TAG, `HTTP代理CONNECT失败: ${statusLine}`);
    await this.closeState(state);
  }

  private isHttpUpstreamProxy(): boolean {
    return this.config !== null && this.config.upstreamProtocol === LocalProxyBridgeUpstreamProtocol.HTTP;
  }

  private addProxyAuthorizationHeader(headerText: string): string {
    if (this.config === null || !this.config.upstreamAuthEnabled) {
      return headerText;
    }
    if (headerText.toLowerCase().includes('\r\nproxy-authorization:')) {
      return headerText;
    }
    const token = this.encodeBase64(`${this.config.upstreamUsername}:${this.config.upstreamPassword}`);
    const insertLine = `Proxy-Authorization: Basic ${token}`;
    if (headerText.endsWith('\r\n\r\n')) {
      return `${headerText.substring(0, headerText.length - 2)}${insertLine}\r\n\r\n`;
    }
    return `${headerText}\r\n${insertLine}\r\n\r\n`;
  }

  private encodeBase64(text: string): string {
    const bytes = new Uint8Array(this.encoder.encodeInto(text));
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(bytes);
  }

  private async sendBadGateway(state: BridgeConnectionState): Promise<void> {
    try {
      await state.client.send({
        data: 'HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n',
        encoding: 'utf-8'
      });
    } catch (error) {
      logger.debug(TAG, `发送代理错误响应失败: ${String(error)}`);
    }
  }

  private async closeState(state: BridgeConnectionState): Promise<void> {
    if (state.closing) {
      return;
    }
    state.closing = true;
    this.connections.delete(state.client.clientId);
    try {
      state.client.off('message');
      state.client.off('close');
      state.client.off('error');
      await state.client.close();
    } catch (error) {
      logger.debug(TAG, `关闭本地代理客户端失败: ${String(error)}`);
    }
    if (state.upstream !== null) {
      try {
        state.upstream.off('message');
        state.upstream.off('close');
        state.upstream.off('error');
        await state.upstream.close();
      } catch (error) {
        logger.debug(TAG, `关闭SOCKS5上游连接失败: ${String(error)}`);
      }
      state.upstream = null;
    }
  }

  private readRequestMethod(requestLine: string): string {
    const firstSpace = requestLine.indexOf(' ');
    if (firstSpace <= 0) {
      return '';
    }
    return requestLine.substring(0, firstSpace).toUpperCase();
  }

  private parseConnectTarget(requestLine: string): ProxyTarget {
    const parts = requestLine.split(' ');
    if (parts.length < 2) {
      throw new Error('CONNECT请求行无效');
    }
    const hostPort = parts[1];
    const portIndex = hostPort.lastIndexOf(':');
    if (portIndex <= 0) {
      throw new Error('CONNECT目标缺少端口');
    }
    const host = hostPort.substring(0, portIndex);
    const port = Number(hostPort.substring(portIndex + 1));
    if (host.length <= 0 || !Number.isFinite(port) || port <= 0 || port > 65535) {
      throw new Error('CONNECT目标无效');
    }
    const target: ProxyTarget = {
      host: host,
      port: port,
      requestLine: requestLine
    };
    return target;
  }

  private parseHttpTarget(requestLine: string, headerText: string): ProxyTarget {
    const parts = requestLine.split(' ');
    if (parts.length < 3) {
      throw new Error('HTTP代理请求行无效');
    }
    const method = parts[0];
    const rawUrl = parts[1];
    const version = parts[2];
    let host = '';
    let port = 80;
    let path = rawUrl;

    if (rawUrl.startsWith('http://')) {
      const afterScheme = rawUrl.substring(7);
      const slashIndex = afterScheme.indexOf('/');
      const authority = slashIndex >= 0 ? afterScheme.substring(0, slashIndex) : afterScheme;
      path = slashIndex >= 0 ? afterScheme.substring(slashIndex) : '/';
      const parsed = this.parseAuthority(authority, 80);
      host = parsed.host;
      port = parsed.port;
    } else if (rawUrl.startsWith('https://')) {
      const afterScheme = rawUrl.substring(8);
      const slashIndex = afterScheme.indexOf('/');
      const authority = slashIndex >= 0 ? afterScheme.substring(0, slashIndex) : afterScheme;
      path = slashIndex >= 0 ? afterScheme.substring(slashIndex) : '/';
      const parsed = this.parseAuthority(authority, 443);
      host = parsed.host;
      port = parsed.port;
    } else {
      const hostHeader = this.readHeaderValue(headerText, 'host');
      const parsed = this.parseAuthority(hostHeader, 80);
      host = parsed.host;
      port = parsed.port;
      path = rawUrl.length > 0 ? rawUrl : '/';
    }

    if (host.length <= 0) {
      throw new Error('HTTP代理请求缺少Host');
    }
    const target: ProxyTarget = {
      host: host,
      port: port,
      requestLine: `${method} ${path} ${version}`
    };
    return target;
  }

  private parseAuthority(authority: string, defaultPort: number): ProxyTarget {
    const cleaned = authority.trim();
    if (cleaned.length <= 0) {
      throw new Error('代理目标地址为空');
    }
    if (cleaned.startsWith('[')) {
      const closing = cleaned.indexOf(']');
      if (closing > 0) {
        const host = cleaned.substring(1, closing);
        let port = defaultPort;
        if (cleaned.length > closing + 2 && cleaned.charAt(closing + 1) === ':') {
          port = Number(cleaned.substring(closing + 2));
        }
        const ipv6Target: ProxyTarget = {
          host: host,
          port: port,
          requestLine: ''
        };
        return ipv6Target;
      }
    }
    const colonIndex = cleaned.lastIndexOf(':');
    if (colonIndex > 0) {
      const parsedPort = Number(cleaned.substring(colonIndex + 1));
      if (Number.isFinite(parsedPort) && parsedPort > 0 && parsedPort <= 65535) {
        const target: ProxyTarget = {
          host: cleaned.substring(0, colonIndex),
          port: parsedPort,
          requestLine: ''
        };
        return target;
      }
    }
    const target: ProxyTarget = {
      host: cleaned,
      port: defaultPort,
      requestLine: ''
    };
    return target;
  }

  private readHeaderValue(headerText: string, headerName: string): string {
    const lines = headerText.split('\r\n');
    const expected = `${headerName.toLowerCase()}:`;
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i];
      if (line.toLowerCase().startsWith(expected)) {
        return line.substring(expected.length).trim();
      }
    }
    return '';
  }

  private rewriteHttpHeader(headerText: string, requestLine: string): string {
    const headerEnd = headerText.endsWith('\r\n\r\n') ? '\r\n\r\n' : '\r\n';
    const lines = headerText.split('\r\n');
    if (lines.length <= 0) {
      return headerText;
    }
    lines[0] = requestLine;
    let result = '';
    for (let i = 0; i < lines.length; i++) {
      if (i > 0) {
        result += '\r\n';
      }
      result += lines[i];
    }
    if (!result.endsWith('\r\n\r\n')) {
      result += headerEnd;
    }
    return result;
  }

  private findHeaderEnd(data: Uint8Array): number {
    for (let i = 0; i <= data.length - 4; i++) {
      if (data[i] === 13 && data[i + 1] === 10 && data[i + 2] === 13 && data[i + 3] === 10) {
        return i + 4;
      }
    }
    return -1;
  }

  private concatBytes(left: Uint8Array, right: Uint8Array): Uint8Array {
    const result = new Uint8Array(left.length + right.length);
    result.set(left, 0);
    result.set(right, left.length);
    return result;
  }

  private decodeBytes(data: Uint8Array): string {
    return this.decoder.decodeToString(data);
  }

  private encodeString(data: string): Uint8Array {
    return new Uint8Array(this.encoder.encodeInto(data));
  }
}
