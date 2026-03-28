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

import SMB2Message from '../tools/smb2_message'
import {message} from '../tools/message'
import {Buffer} from '../buffer/index'

export default message({

  generate:function(connection){

    return new SMB2Message({
      headers:{
        'Command':'SESSION_SETUP'
      , 'ProcessId':connection.ProcessId
      }
    , request:{
        'Buffer':encodeType1(
           connection.ip
          , connection.domain
        )
      }
    });

  }

, successCode: 'STATUS_MORE_PROCESSING_REQUIRED'

, onSuccess:function(connection, response){
    var h = response.getHeaders();
    connection.SessionId = h.SessionId;
    connection.nonce = decodeType2(response.getResponse().Buffer);
  }

})


function encodeType1(hostname, ntdomain) {
  hostname = hostname.toUpperCase();
  ntdomain = ntdomain.toUpperCase();
  var hostnamelen = Buffer.byteLength(hostname, 'ascii');
  var ntdomainlen = Buffer.byteLength(ntdomain, 'ascii');

  var pos = 0;
  var buf = new Buffer(32 + hostnamelen + ntdomainlen);

  buf.write('NTLMSSP', pos, 7, 'ascii'); // byte protocol[8];
  pos += 7;
  buf.writeUInt8(0, pos);
  pos++;

  buf.writeUInt8(0x01, pos); // byte type;
  pos++;

  buf.fill(0x00, pos, pos + 3); // byte zero[3];
  pos += 3;

  buf.writeUInt16LE(0xb203, pos); // short flags;
  pos += 2;

  buf.fill(0x00, pos, pos + 2); // byte zero[2];
  pos += 2;

  buf.writeUInt16LE(ntdomainlen, pos); // short dom_len;
  pos += 2;
  buf.writeUInt16LE(ntdomainlen, pos); // short dom_len;
  pos += 2;

  var ntdomainoff = 0x20 + hostnamelen;
  buf.writeUInt16LE(ntdomainoff, pos); // short dom_off;
  pos += 2;

  buf.fill(0x00, pos, pos + 2); // byte zero[2];
  pos += 2;

  buf.writeUInt16LE(hostnamelen, pos); // short host_len;
  pos += 2;
  buf.writeUInt16LE(hostnamelen, pos); // short host_len;
  pos += 2;

  buf.writeUInt16LE(0x20, pos); // short host_off;
  pos += 2;

  buf.fill(0x00, pos, pos + 2); // byte zero[2];
  pos += 2;

  buf.write(hostname, 0x20, hostnamelen, 'ascii');
  buf.write(ntdomain, ntdomainoff, ntdomainlen, 'ascii');

  return buf;
}


/*
 *
 */
function decodeType2(buf)
{
  var proto = buf.toString('ascii', 0, 7);
  if (buf[7] !== 0x00 || proto !== 'NTLMSSP')
  throw new Error('magic was not NTLMSSP');

  var type = buf.readUInt8(8);
  if (type !== 0x02)
  throw new Error('message was not NTLMSSP type 0x02');

  //var msg_len = buf.readUInt16LE(16);

  //var flags = buf.readUInt16LE(20);

  var nonce = buf.slice(24, 32);
  return nonce;
}


//function encodeType1(hostname, ntdomain) {
//  hostname = hostname.toUpperCase();
//  ntdomain = ntdomain.toUpperCase();
//  var hostnamelen = Buffer.byteLength(hostname, 'ascii');
//  var ntdomainlen = Buffer.byteLength(ntdomain, 'ascii');
//
//  const ab = new ArrayBuffer(32 + hostnamelen + ntdomainlen);
//  var input = Buffer.from(ab);
//  let bb = Buffer.from('NTLMSSP').toString('ascii')
//  input.write(bb,0)
//  input.writeUInt8(0,7)
//  input.writeUInt8(0x01, 8); // byte type;
//  input.fill(0x00, 9, 12); // byte zero[3];
//  input.writeUInt16LE(0xb203, 12);
//  input.fill(0x00,14, 16);
//  input.writeUInt16LE(ntdomainlen, 16);
//  input.writeUInt16LE(ntdomainlen, 18);
//  var ntdomainoff = 0x20 + hostnamelen;
//  input.writeUInt16LE(ntdomainoff, 20); // short dom_off;
//  input.fill(0x00, 22, 24);
//  input.writeUInt16LE(hostnamelen, 24);
//  input.writeUInt16LE(hostnamelen, 26)
//  input.writeUInt16LE(0x20, 28)
//  input.fill(0x00, 30, 32);
//  let ipBuffer = Buffer.from(hostname).toString('ascii')
//  let domainBuff = Buffer.from(ntdomain).toString('ascii')
//  input.write(ipBuffer, 0x20);
//  input.write(domainBuff, ntdomainoff);
//  console.info("smb setup_step0 :"+JSON.stringify(input))
//
//  return input;
//}
//
//
///*
// *
// */
//function decodeType2(buf)
//{
//  var temBuf = Buffer.from(buf);
//  var proto = temBuf.toString('ascii',0,7)
//  if (temBuf[7] !== 0x00 || proto !== 'NTLMSSP')
//  throw new Error('magic was not NTLMSSP');
//
//  var type = temBuf.readUInt8(8);
//  if (type !== 0x02)
//  throw new Error('message was not NTLMSSP type 0x02');
//
//  var nonce = temBuf.subarray(24, 32);
//  return nonce;
//}