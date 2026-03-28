import { E as EventEmitter_1 } from './index-n_WnU07Q.js';
import socket from '@ohos.net.socket';
import connection from '@ohos.net.connection';
import buffer from '@ohos.buffer';
import './_commonjsHelpers-YxXKG0rd.js';

var tag = "dudu---";
class OhosTcpSocket {
  tcp_socket; // TcpSocket实例
  options; //配置
  net_handle; //网络句柄
  net_address; //网络地址
  connecting;
  constructor(options) {
    this.tcp_socket = socket.constructTCPSocketInstance();
    this.options = options;
  }
  async getDefaultNet() {
    this.net_handle = await connection.getDefaultNet();
    return this;
  }
  async getConnectionProperties() {
    const res = await connection.getConnectionProperties(this.net_handle);
    if (!res || !res.linkAddresses || res.linkAddresses.length === 0) return;
    this.net_address = res.linkAddresses[0].address;
    return this;
  }
  async bind() {
    await this.tcp_socket.bind(this.net_address);
    return this;
  }
  async connect() {
    await this.tcp_socket.connect({
      address: {
        address: this.options.host,
        port: this.options.port,
        family: 1,
      },
      timeout: 6000,
    });
    return this;
  }
}

class Socket extends EventEmitter_1 {
  ohos_tcp_socket;
  constructor(options) {
    super();
    this.options = options;
    this.ohos_tcp_socket = new OhosTcpSocket(options);
    this.ohos_tcp_socket.tcp_socket.on("message", (data) => {
      console.log(
        tag + `服务端发来消息 :${buffer.from(data.message).toString()}`
      );

      this.emit("data", buffer.from(data.message).toString());
    });
  }
  async connect() {
    try {
      this.ohos_tcp_socket.connecting = true;
      await this.ohos_tcp_socket.getDefaultNet();
      console.log(tag + `getDefaultNet 成功`);
      await this.ohos_tcp_socket.getConnectionProperties();
      console.log(tag + `getConnectionProperties 成功`);
      await this.ohos_tcp_socket.bind();
      console.log(tag + `bind 成功`);
      await this.ohos_tcp_socket.connect();
      console.log(tag + `connect 成功`);
      this.ohos_tcp_socket.connecting = false;
      this.emit("connect");
    } catch (err) {
      console.log(tag + `connect 出现异常 ${JSON.stringify(err)}`);

      this.ohos_tcp_socket.connecting = false;
      this.emit("error", err);
    }
  }

  write(data, encoding, cb) {
    console.log(tag + `write 开始发送消息`);

    if (this.ohos_tcp_socket.connecting) {
      console.log(tag + `进入缓冲队列`);

      this.once("connect", () => {
        this.write(data, encoding, cb);
      });
    } else {
      console.log(tag + `write 真正发送一条消息` + data);

      this.ohos_tcp_socket.tcp_socket.send({ data, encoding }, cb);
    }
  }

  end() {}
  destroy() {}
  removeAllListeners() {}
  unref() {}
}

function createConnection(port, host, connectionListener) {
  const socket = new Socket({ port, host, connectionListener });
  socket.connect();
  return socket;
}

export { createConnection };
