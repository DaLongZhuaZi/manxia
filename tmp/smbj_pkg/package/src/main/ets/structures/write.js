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
    ['StructureSize', 2, 49]
    , ['DataOffset', 2, 0x70]
    , ['Length', 4, 0]
    , ['Offset', 8]
    , ['FileId', 16]
    , ['Channel', 4, 0]
    , ['RemainingBytes', 4, 0]
    , ['WriteChannelInfoOffset', 2, 0]
    , ['WriteChannelInfoLength', 2, 0]
    , ['Flags', 4, 0]
    , ['Buffer', 'Length']
  ],

  response: [
    ['StructureSize', 2]
    , ['Reserved', 2]
    , ['Count', 4]
    , ['Remaining', 4]
    , ['WriteChannelInfoOffset', 2]
    , ['WriteChannelInfoLength', 2]
  ]
}