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

import SMB2Forge from '../tools/smb2_forge'
import BigInt from '../tools/bigint'
var SMB2Request = SMB2Forge.request

/*
 * rmdir
 * =====
 *
 * remove directory:
 *
 *  - open the folder
 *
 *  - remove the folder
 *
 *  - close the folder
 *
 */
export default function(path, cb){
  var connection = this;

  connection.exists(path, function(err, exists){

    if(err) cb && cb(err);

    else if(exists){

      // SMB2 open file
      SMB2Request('open_folder', {path:path}, connection, function(err, file){
        if(err) cb && cb(err);
        // SMB2 query directory
        else SMB2Request('set_info', {FileId:file.FileId, FileInfoClass:'FileDispositionInformation',Buffer:(new BigInt(1,1)).toBuffer()}, connection, function(err, files){
          if(err) cb && cb(err);
          // SMB2 close directory
          else SMB2Request('close', file, connection, function(err){
            cb && cb(null, files);
          });
        });
      });

    } else {
      cb(new Error('Folder does not exists'));

    }
  });

}
