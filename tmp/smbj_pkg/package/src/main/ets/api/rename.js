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

// @ts-ignore
import {Buffer} from '../buffer/index'
import SMB2Forge from '../tools/smb2_forge'
import BigInt from '../tools/bigint'
var SMB2Request = SMB2Forge.request

/*
 * rename
 * ======
 *
 * change the name of a file:
 *
 *  - open the file
 *
 *  - change file name
 *
 *  - close the file
 *
 */
export default function(paths, cb){

  var connection = this;
  console.info("smb rename path:"+paths)
  // SMB2 open the folder / file
  SMB2Request('open_folder', {path:paths[0]}, connection, function(err, file){
    if(err) SMB2Request('open', {path:paths[0]}, connection, function(err, file){
      if(err) cb && cb(err);
      else rename(connection, file, paths[1], cb);
    });
    else rename(connection, file, paths[1], cb);
  });

}


function rename (connection, file, newPath, cb) {
  // SMB2 rename
  SMB2Request('set_info', {FileId:file.FileId, FileInfoClass:'FileRenameInformation',Buffer:renameBuffer(newPath)}, connection, function(err){
    if(err) cb && cb(err);
    // SMB2 close file
    else SMB2Request('close', file, connection, function(err){
      cb && cb(null);
    });
  });
}


function renameBuffer (newPath) {

  var filename = new Buffer(newPath, 'ucs2');

  return Buffer.concat([

    // ReplaceIfExists 1 byte
    (new BigInt(1,0)).toBuffer()

    // Reserved 7 bytes
    , (new BigInt(7,0)).toBuffer()

    // RootDirectory 8 bytes
    , (new BigInt(8,0)).toBuffer()

    // FileNameLength 4 bytes
    , (new BigInt(4,filename.length)).toBuffer()

    // FileName
    , filename

  ]);

}
