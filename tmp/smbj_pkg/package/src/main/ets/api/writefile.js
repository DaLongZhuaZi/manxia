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

import {Buffer} from '../buffer/index'
import SMB2Forge from '../tools/smb2_forge'
import BigInt from '../tools/bigint'
var SMB2Request = SMB2Forge.request
/*
 * writeFile
 * =========
 *
 * create and write file on the share
 *
 *  - create the file
 *
 *  - set info of the file
 *
 *  - set content of the file
 *
 *  - close the file
 *
 */
 // filename, data, options
export default function(params, cb){

  var connection = this
   var file
   var fileContent = Buffer.isBuffer(params[1]) ? params[1] : new Buffer(params[1], params[2])
   var fileLength = new BigInt(8, fileContent.length)

  function createFile(fileCreated){
    SMB2Request('create', {path:params[0]}, connection, function(err, f){
      if(err) cb && cb(err);
      // SMB2 set file size
      else {
        file = f;
        fileCreated();
      }
    });
  }

  function closeFile(fileClosed){
    SMB2Request('close', file, connection, function(err){
      if(err) cb && cb(err);
      else {
        file = null;
        fileClosed();
      }
    });
  }

  function setFileSize(fileSizeSetted){
    SMB2Request('set_info', {FileId:file.FileId, FileInfoClass:'FileEndOfFileInformation', Buffer:fileLength.toBuffer()}, connection, function(err){
      if(err) cb && cb(err);
      else fileSizeSetted();
    });
  }

  function writeFile(fileWritten){
    // @ts-ignore
    var offset = new BigInt(8)
      , stop = false
      , nbRemainingPackets = 0
      , maxPacketSize = new BigInt(8, 0x00010000 - 0x71)
    ;
    // callback manager
    function callback(offset){
      return function(err){
        if(stop) return;
        if(err) {
          cb && cb(err);
          stop = true;
        } else {
          nbRemainingPackets--;
          checkDone();
        }
      }
    }
    // callback manager
    function checkDone(){
      if(stop) return;
      createPackets();
      if(nbRemainingPackets==0 && offset.ge(fileLength)) {
        fileWritten();
      }
    }
    // create packets
    function createPackets(){
      while(nbRemainingPackets<connection.packetConcurrency && offset.lt(fileLength)){
        // process packet size
        var rest = fileLength.sub(offset);
        var packetSize = rest.gt(maxPacketSize) ? maxPacketSize : rest;
        // generate buffer
        SMB2Request('write', {
          'FileId':file.FileId
        , 'Offset':offset.toBuffer()
        , 'Buffer':fileContent.slice(offset.toNumber(), offset.add(packetSize).toNumber())
        }, connection, callback(offset));
        offset = offset.add(packetSize);
        nbRemainingPackets++;
      }
    }
    checkDone();
  }


  createFile(function(){
    setFileSize(function(){
      writeFile(function(){
        closeFile(cb);
      });
    });
  });

}
