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


import { oddpar } from './common'
import { expandkey } from './common'
import {Buffer} from '../buffer/index'

import { lmhashbuf } from './smbhash'
import { nthashbuf } from './smbhash'
import { crypto } from '@ohos/node-polyfill'
var globalEncodeBuff;



export function encodeType3(username, hostname, ntdomain, nonce, password) {
  hostname = hostname.toUpperCase();
  ntdomain = ntdomain.toUpperCase();

  var lmh = new Buffer(21);
  lmhashbuf(password).copy(lmh);
  lmh.fill(0x00, 16); // null pad to 21 bytes
  var nth = new Buffer(21);
  nthashbuf(password).copy(nth);
  nth.fill(0x00, 16); // null pad to 21 bytes

  var lmr=makeResponse(lmh, nonce);
  var ntr =makeResponse(nth, nonce);


  var usernamelen = Buffer.byteLength(username, 'ucs2');
  var hostnamelen = Buffer.byteLength(hostname, 'ucs2');
  var ntdomainlen = Buffer.byteLength(ntdomain, 'ucs2');
  var lmrlen = 0x18;
  var ntrlen = 0x18;

  var ntdomainoff = 0x40;
  var usernameoff = ntdomainoff + ntdomainlen;
  var hostnameoff = usernameoff + usernamelen;
  var lmroff = hostnameoff + hostnamelen;
  var ntroff = lmroff + lmrlen;

  var pos = 0;
  var msg_len = 64 + ntdomainlen + usernamelen + hostnamelen + lmrlen + ntrlen;
  var buf = Buffer.alloc(msg_len);



    let bb = Buffer.from('NTLMSSP').toString('ascii')
    buf.write(bb, pos); // byte protocol[8];
    pos += 7;
    buf.writeUInt8(0, pos);
    pos++;

    buf.writeUInt8(0x03, pos); // byte type;
    pos++;

    buf.fill(0x00, pos, pos + 3); // byte zero[3];
    pos += 3;

    buf.writeUInt16LE(lmrlen, pos); // short lm_resp_len;
    pos += 2;
    buf.writeUInt16LE(lmrlen, pos); // short lm_resp_len;
    pos += 2;
    buf.writeUInt16LE(lmroff, pos); // short lm_resp_off;
    pos += 2;
    buf.fill(0x00, pos, pos + 2); // byte zero[2];
    pos += 2;

    buf.writeUInt16LE(ntrlen, pos); // short nt_resp_len;
    pos += 2;
    buf.writeUInt16LE(ntrlen, pos); // short nt_resp_len;
    pos += 2;
    buf.writeUInt16LE(ntroff, pos); // short nt_resp_off;
    pos += 2;
    buf.fill(0x00, pos, pos + 2); // byte zero[2];
    pos += 2;

    buf.writeUInt16LE(ntdomainlen, pos); // short dom_len;
    pos += 2;
    buf.writeUInt16LE(ntdomainlen, pos); // short dom_len;
    pos += 2;
    buf.writeUInt16LE(ntdomainoff, pos); // short dom_off;
    pos += 2;
    buf.fill(0x00, pos, pos + 2); // byte zero[2];
    pos += 2;

    buf.writeUInt16LE(usernamelen, pos); // short user_len;
    pos += 2;
    buf.writeUInt16LE(usernamelen, pos); // short user_len;
    pos += 2;
    buf.writeUInt16LE(usernameoff, pos); // short user_off;
    pos += 2;
    buf.fill(0x00, pos, pos + 2); // byte zero[2];
    pos += 2;

    buf.writeUInt16LE(hostnamelen, pos); // short host_len;
    pos += 2;
    buf.writeUInt16LE(hostnamelen, pos); // short host_len;
    pos += 2;
    buf.writeUInt16LE(hostnameoff, pos); // short host_off;
    pos += 2;
    buf.fill(0x00, pos, pos + 6); // byte zero[6];
    pos += 6;

    buf.writeUInt16LE(msg_len, pos); // short msg_len;
    pos += 2;
    buf.fill(0x00, pos, pos + 2); // byte zero[2];
    pos += 2;

    buf.writeUInt16LE(0x8201, pos); // short flags;
    pos += 2;
    buf.fill(0x00, pos, pos + 2); // byte zero[2];
    pos += 2;

    buf.write(ntdomain, ntdomainoff, ntdomainlen, 'ucs2');
    buf.write(username, usernameoff, usernamelen, 'ucs2');
    buf.write(hostname, hostnameoff, hostnamelen, 'ucs2');
    lmr.copy(buf, lmroff, 0, lmrlen);
    ntr.copy(buf, ntroff, 0, ntrlen);
  console.info("smb handle makeResponseEnd end lmr:" + JSON.stringify(lmr))
  console.info("smb handle makeResponseEnd end ntr:" + JSON.stringify(ntr))
    globalEncodeBuff = buf;



  return buf;
}

export function getGlobBuff() {
  return globalEncodeBuff;
}

function makeResponse(hash, nonce) {
  var out = new Buffer(24);
  for (var i = 0; i < 3; i++) {
    var keybuf = oddpar(expandkey(hash.slice(i * 7, i * 7 + 7)));
    var des = crypto.createCipheriv('DES-ECB', keybuf, '');
    var str = des.update(nonce.toString('binary'), 'binary', 'binary');
    out.write(str, i * 8, i * 8 + 8, 'binary');
  }
  return out;
}

