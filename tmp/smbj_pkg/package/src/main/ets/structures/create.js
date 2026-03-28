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

export default {
  request: [

    ['StructureSize', 2, 57]
    , ['SecurityFlags', 1, 0]
    , ['RequestedOplockLevel', 1, 0]
    , ['ImpersonationLevel', 4, 0x00000002]
    , ['SmbCreateFlags', 8, 0]
    , ['Reserved', 8, 0]
    , ['DesiredAccess', 4, 0x00100081]
    , ['FileAttributes', 4, 0x00000000]
    , ['ShareAccess', 4, 0x00000007]
    , ['CreateDisposition', 4, 0x00000001]
    , ['CreateOptions', 4, 0x00000020]
    , ['NameOffset', 2]
    , ['NameLength', 2]
    , ['CreateContextsOffset', 4]
    , ['CreateContextsLength', 4]
    , ['Buffer', 'NameLength']
    , ['Reserved2', 2, 0x4200]
    , ['CreateContexts', 'CreateContextsLength', '']

  ],

  response: [

    ['StructureSize', 2]
    , ['OplockLevel', 1]
    , ['Flags', 1]
    , ['CreateAction', 4]
    , ['CreationTime', 8]
    , ['LastAccessTime', 8]
    , ['LastWriteTime', 8]
    , ['ChangeTime', 8]
    , ['AllocationSize', 8]
    , ['EndofFile', 8]
    , ['FileAttributes', 4]
    , ['Reserved2', 4]
    , ['FileId', 16]
    , ['CreateContextsOffset', 4]
    , ['CreateContextsLength', 4]
    , ['Buffer', 'CreateContextsLength']

  ]
}