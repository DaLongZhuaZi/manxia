import { SMB2 } from '@ohos/smbj';

export interface SMB2ClientOptions {
  share: string;
  port?: number;
  packetConcurrency?: number;
  autoCloseTimeout?: number;
  domain: string;
  username: string;
  password: string;
  clientIP?: string;
}

export interface SMBReadFileOptions {
  encoding?: 'UTF-8';
}

export interface SMBJRuntimeClient {
  readdir(path: string, callback: (error: ESObject | null, files: string[]) => void): void;
  readFile(
    path: string,
    options: SMBReadFileOptions,
    callback: (error: ESObject | null, content: ESObject) => void
  ): void;
  close(): void;
}

export function createClient(options: SMB2ClientOptions): ESObject {
  return new SMB2(options) as ESObject;
}

export function readdir(
  client: ESObject,
  path: string,
  callback: (error: ESObject | null, files: string[]) => void
): void {
  (client as SMBJRuntimeClient).readdir(path, callback);
}

export function readFile(
  client: ESObject,
  path: string,
  options: SMBReadFileOptions,
  callback: (error: ESObject | null, content: ESObject) => void
): void {
  (client as SMBJRuntimeClient).readFile(path, options, callback);
}

export function close(client: ESObject): void {
  (client as SMBJRuntimeClient).close();
}
