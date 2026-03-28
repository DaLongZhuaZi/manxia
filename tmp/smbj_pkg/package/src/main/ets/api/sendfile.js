/*
 * (The MIT License)
 * Copyright (c) 2021 Huawei Device Co., Ltd.
 *
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

import SMB2Forge from '../tools/smb2_forge'

var SMB2Request = SMB2Forge.request
import {Buffer} from '../buffer/index'
import BigInt from '../tools/bigint'



export class CallResult {
  err;
  progress;
  sendFileSize;
  status
}

/**
 * fileName  上传服务器的文件名称
 */
export default function (params, cb) {
  var fileContent = Buffer.from(params[1].buffer);
  var connection = this
  var file
  var fileLength = new BigInt(8, fileContent.byteLength)
  var callResult = new CallResult();

  let position = 0; //上传位置
  let fileSize = 0; //文件大小
  let sendFileSize = 0; //已经发送文件大小

  var splitSize = 0; //分片大小
  function splitFile(fileWritten) {
    fileSize = fileContent.byteLength;
    if (fileContent == undefined) {
      console.info("file length load fail,please check  file")
      return
    }
    fileSize = params[1].byteLength;
    stack(fileSize - sendFileSize, fileWritten)
  }

  function stack(residualSize, fileWritten) {
    var offsetLength, offset
    if (residualSize == 0) {
      fileContent = null;
      fileWritten()
      return
    } else if (residualSize < 100) {
      splitSize = 1
      offsetLength = offsetP(splitSize + position)
    }
    else if (residualSize < 1024) {
      splitSize = 100
      offsetLength = offsetP(splitSize + position)
    } else if (residualSize < 1024 * 60) {
      //      offsetLength = fileLength
      splitSize = 1024
      offsetLength = offsetP(splitSize + position)
    } else { //1024*60  为管道传输最大伐值，
      splitSize = 1024 * 60
      offsetLength = offsetP(splitSize + position)
    }
    offset = offsetP(position)

    var contentBuffer = fileContent.slice(offset.toNumber(), offsetLength.toNumber())
    writeFile(contentBuffer, offset, (callResult) => {
      cb(callResult);
      if (callResult.status) {
        if (callResult.progress != 100) {
          position -= splitSize;
        }
        fileWritten()
        console.log("  sendfile success  ok .")
        return
      } else {
        if (fileContent.byteLength == sendFileSize) {
          console.info("-----------")
          return
        }
        position += splitSize;
        stack(fileSize - sendFileSize, fileWritten)
        console.log("...continue....")
      }
    })
  }

  function offsetP(n) {
    // @ts-ignore
    return new BigInt(8).add(n)
  }

  function createFile(fileCreated) {
    SMB2Request('create', {
      path: params[0]
    }, connection, function (err, f) {
      callResult.err = err
      if (err) cb && cb(callResult);
      // SMB2 set file size
      else {
        file = f;
        fileCreated();
      }
    });
  }


  function closeFile() {
    SMB2Request('close', file, connection, function (err) {
      if (err) cb && cb(callResult.err = err);
      else {
        file = null;
      }
    });
  }


  function setFileSize(fileSizeSetted) {
    SMB2Request('set_info', {
      FileId: file.FileId, FileInfoClass: 'FileEndOfFileInformation', Buffer: fileLength.toBuffer()
    }, connection, function (err) {
      if (err) cb && cb(callResult.err = err);
      else fileSizeSetted();
    });
  }

  function writeFile(contentBuffer, offset, cb) {
    var stop = false


    function checkDone() {
      if (stop) return;
      createPackets();
    }

    function createPackets() {
      try {
        SMB2Request('write', {
          'FileId': file.FileId
        , 'Offset': offset.toBuffer()
        , 'Buffer': contentBuffer
        }, connection, function (err) {
          if (err) {
            stop = true;
            let progress = Math.floor((sendFileSize / fileSize) * 100)
            callResult.progress = progress,
            callResult.status = stop
            callResult.err = err
            callResult.sendFileSize = sendFileSize
            cb && cb(callResult);
            console.log('send fail');
            return
          } else {
            sendFileSize += contentBuffer.byteLength;
            let pro = Math.floor((sendFileSize / fileSize) * 100)
            console.error("-----send file size " + sendFileSize / 1024 + "KB")
            if (sendFileSize == fileSize) {
              console.info("--------send --end------")
              callResult.progress = 100,
              callResult.status = true
              callResult.sendFileSize = sendFileSize
              console.log('send success');
              cb(callResult);
              return
            } else {
              stop = false
              callResult.progress = pro,
              callResult.status = stop
              callResult.sendFileSize = sendFileSize
              cb(callResult);
              return
            }
          }
        });
      } catch (e) {
        console.info("-------createPackets-----------" + e)
      }
    }

    checkDone();
  }

  createFile(function () {
    setFileSize(function () {
      splitFile(function () {
        closeFile()
      })
    });
  });

}