/*
 * (The MIT License)

 * Copyright (c) 2021 Huawei Device Co., Ltd.

 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * 'Software'), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:

 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import {Buffer} from './buffer/index'
import SMB2Connection from './tools/smb2_connection'
import exists from './api/exists'
import close from './api/close'
import mkdir from './api/mkdir'
import readdir from './api/readdir'
import readfile from './api/readfile'
import rename from './api/rename'
import writefile from './api/writefile'
import rmdir from './api/rmdir'
import unlink from './api/unlink'

import sendfile from './api/sendfile'

let shareRegExp = /\\\\([^\\]*)\\([^\\]*)\\?/
let port = 445
let packetConcurrency = 20
let autoCloseTimeout = 10000


export interface options {
  share: string,
  port?: number,
  packetConcurrency?: number,
  autoCloseTimeout?: number,
  domain: string,
  username: string,
  password: string,

}

export class SMB2 {
  private ip: string='';
  private port: number=445;
  private messageId: number=0;
  private share: string='';
  private fullPath: string='';
  private packetConcurrency: number=20;
  private autoCloseTimeout: number=10000;
  private domain: string='DOMAIN';
  private username: string='';
  private password: string='';
  private SessionId;
  private ProcessId;
  private socket;
  private errorHandler=[];
  private newResponse:boolean = false;
  private clientIP: string='';

  public constructor(opt) {
    opt = opt || {};
    // Parse share-string
    var matches = [];
    if (!opt.share || !(matches = opt.share.match(shareRegExp))) {
      throw new Error('the share is not valid');
    }

    // resolve IP from NetBios
    // this.ip = netBios.resolve(matches[0]);
    this.ip = matches[1];

    // set default port
    this.port = opt.port || port;

    // set message id
    this.messageId = 0;

    // extract share
    this.share = matches[2];

    // save the full path
    this.fullPath = opt.share;

    // packet concurrency default 20
    this.packetConcurrency = opt.packetConcurrency || packetConcurrency;

    // close timeout default 10s
    if (opt.autoCloseTimeout !== undefined) {
      this.autoCloseTimeout = opt.autoCloseTimeout
    } else {
      this.autoCloseTimeout = autoCloseTimeout
    }
    this.clientIP = opt.clientIP;

    // store authentification
    this.domain = opt.domain;
    this.username = opt.username;
    this.password = opt.password;

    // set session id
    this.SessionId = Math.floor(Math.random() * 256) & 0xFF;


    // set the process id
    // https://msdn.microsoft.com/en-us/library/ff470100.aspx
    this.ProcessId = new Buffer([
      Math.floor(Math.random() * 256) & 0xFF,
      Math.floor(Math.random() * 256) & 0xFF,
      Math.floor(Math.random() * 256) & 0xFF,
      Math.floor(Math.random() * 256) & 0xFE
    ]);

    // init connection (socket)
    SMB2Connection.init(this);
  }

  public exists(path, callback) {
    SMB2Connection.requireConnect(this, exists)(path, callback)
  }

  public mkdir(path, callback) {
    SMB2Connection.requireConnect(this, mkdir)(path, callback)
  }

  public readdir(path, callback) {
    SMB2Connection.requireConnect(this, readdir)(path, callback)
  }

  public readFile(filename: string, options?: { encoding: 'UTF-8' }, callback?: any) {
    if (!options) {
      options = { encoding: 'UTF-8' }
    }
    SMB2Connection.requireConnect(this, readfile)([filename, options], callback)
  }

  public rename(oldPath, newPath, callback) {
    SMB2Connection.requireConnect(this, rename)([oldPath, newPath], callback)
  }

  public writeFile(filename, data, encoding?: string, callback?: any) {
    if (!encoding) {
      encoding = 'UTF-8'
    }
    SMB2Connection.requireConnect(this, writefile)([filename, data, encoding], callback)
  }


  public rmdir(path, callback) {
    SMB2Connection.requireConnect(this, rmdir)(path, callback)
  }

  public unlink(path, callback) {
    SMB2Connection.requireConnect(this, unlink)(path, callback)
  }

  public sendFile(filename, data, callback) {
    SMB2Connection.requireConnect(this, sendfile)([filename, data], callback)
  }

  public close() {
    close(this)
  }
}