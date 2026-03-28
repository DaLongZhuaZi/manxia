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

    var buffer = new Buffer(params.path, 'ucs2');

    return new SMB2Message({
      headers: {
        'Command': 'CREATE'
      , 'SessionId': connection.SessionId
      , 'TreeId': connection.TreeId
      , 'ProcessId': connection.ProcessId
      }
    , request: {
        'Buffer': buffer
      ,
        'DesiredAccess': 0x001701DF
      ,
        'FileAttributes': 0x00000080
      ,
        'ShareAccess': 0x00000000
      ,
        'CreateDisposition': 0x00000005
      ,
        'CreateOptions': 0x00000044
      ,
        'NameOffset': 0x0078
      ,
        'CreateContextsOffset': 0x007A + buffer.length
      }
    });

  }
});