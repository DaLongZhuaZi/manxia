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
var SMB2Request = SMB2Forge.request
/*
 * readdir
 * =======
 *
 * list the file / directory from the path provided:
 *
 *  - open the directory
 *
 *  - query directory content
 *
 *  - close the directory
 *
 */
export default function(path, cb){
  var connection = this;

  // SMB2 open directory
  SMB2Request('open_folder', {path:path}, connection, function(err, file){
    if(err) cb && cb(err);
    // SMB2 query directory
    else queryDir(file, connection, [], cb);
  });
}





/*
 * Helpers
 */

/**
 * queryDir - recursive querying until all files in a directory have been added to the listing.
 * @param file
 * @param connection
 * @param completeFileListing
 * @param cb
 */
function queryDir(file, connection, completeFileListing, cb) {
  SMB2Request('query_directory', file, connection, function(err, files){
    var allFiles = completeFileListing.concat(files || []);
    console.info("smb readdir:"+JSON.stringify(allFiles))
    // no more file
    // => close and send response
    if(err && err.code === 'STATUS_NO_MORE_FILES') {
      return SMB2Request('close', file, connection, function(err){

        var fileNames = allFiles
          .map(function(v){ return v.Filename }) // get the filename only
          .filter(function(v){ return v!='.' && v!='..' }) // remove '.' and '..' values

        cb && cb(null, fileNames);
      });
    }

    // error
    // => close and send error
    if (err) {
      return cb && cb(err);
    }

    // still receiving files
    // => maybe the folder is not empty
    queryDir(file, connection, allFiles, cb)
  });
}

