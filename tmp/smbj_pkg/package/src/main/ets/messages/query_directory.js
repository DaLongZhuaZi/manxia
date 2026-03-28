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
  generate: function (connection, params) {

    return new SMB2Message({
      headers: {
        'Command': 'QUERY_DIRECTORY'
      , 'SessionId': connection.SessionId
      , 'TreeId': connection.TreeId
      , 'ProcessId': connection.ProcessId
      }
    , request: {
        'FileId': params.FileId
      , 'Buffer': new Buffer('*', 'ucs2')
      }
    });

  }

, parseResponse: function (response) {
    return parseFiles(response.getResponse().Buffer);
  }
});
/*
 * HELPERS
 */
function parseFiles(buffer) {
  var files = []
    , offset = 0
    , nextFileOffset = -1
  ;
  while (nextFileOffset != 0) {
    // extract next file offset
    nextFileOffset = buffer.readUInt32LE(offset);
    // extract the file
    files.push(
    parseFile(
    buffer.subarray(offset + 4, nextFileOffset ? offset + nextFileOffset : buffer.length)
    )
    );
    // move to nex file
    offset += nextFileOffset;
  }
  return files;
}


function parseFile(buffer) {
  var file = {
    Index: 0,
    CreationTime: 0,
    LastAccessTime:0,
    LastWriteTime:0,
    ChangeTime:0,
    EndofFile:0,
    AllocationSize:0,
    FileAttributes:'',
    FilenameLength:0,
    EASize:0,
    ShortNameLength:0,
    FileId:'',
    Filename:''
  }
  var offset = 0
  // index
  file.Index = buffer.readUInt32LE(offset);
  offset += 4;

  // CreationTime
  file.CreationTime = buffer.subarray(offset, offset + 8);
  offset += 8;

  // LastAccessTime
  file.LastAccessTime = buffer.subarray(offset, offset + 8);
  offset += 8;

  // LastWriteTime
  file.LastWriteTime = buffer.subarray(offset, offset + 8);
  offset += 8;

  // ChangeTime
  file.ChangeTime = buffer.subarray(offset, offset + 8);
  offset += 8;

  // EndofFile
  file.EndofFile = buffer.subarray(offset, offset + 8);
  offset += 8;

  // AllocationSize
  file.AllocationSize = buffer.subarray(offset, offset + 8);
  offset += 8;

  // FileAttributes
  file.FileAttributes = buffer.readUInt32LE(offset);
  offset += 4;

  // FilenameLength
  file.FilenameLength = buffer.readUInt32LE(offset);
  offset += 4;

  // EASize
  file.EASize = buffer.readUInt32LE(offset);
  offset += 4;

  // ShortNameLength
  file.ShortNameLength = buffer.readUInt8(offset);
  offset += 1;

  // FileId
  file.FileId = buffer.subarray(offset, offset + 8);
  offset += 8;

  // Reserved
  offset += 27;

  // Filename
  file.Filename = buffer.subarray(offset, offset + file.FilenameLength).toString('ucs2');
  offset += file.FilenameLength;

  return file;
}