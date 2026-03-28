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
    , ['Padding', 1, 0x50]
    , ['Flags', 1, 0]
    , ['Length', 4]
    , ['Offset', 8]
    , ['FileId', 16]
    , ['MinimumCount', 4, 0]
    , ['Channel', 4, 0]
    , ['RemainingBytes', 4, 0]
    , ['ReadChannelInfoOffset', 2, 0]
    , ['ReadChannelInfoLength', 2, 0]
    , ['Buffer', 1, 0]
  ],

  response: [
    ['StructureSize', 2]
    , ['DataOffset', 1]
    , ['Reserved', 1]
    , ['DataLength', 4]
    , ['DataRemaining', 4]
    , ['Reserved2', 4]
    , ['Buffer', 'DataLength']
  ]
}