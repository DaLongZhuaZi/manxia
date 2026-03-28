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

import MsErref from './ms_erref'
import BigInt from './bigint'


var defaults = {

  successCode: 'STATUS_SUCCESS'

, parse: function (connection, cb) {

    var self = this;
    return function(response){
      var h = response.getHeaders()
      // @ts-ignore
       var err = MsErref.getStatus(BigInt.fromBuffer(h.Status).toNumber())

      if(err.code == self.successCode){
        self.onSuccess && self.onSuccess(connection, response);
        cb && cb(
          null
          , self.parseResponse && self.parseResponse(response)
        );
      } else {
        var error = new Error(MsErref.getErrorMessage(err));
        // @ts-ignore
        error.code = err.code;
        cb && cb(error);
      }
    }

  }

, parseResponse: function (response) {
    return response.getResponse();
  }
};

export function message(obj) {

  for (var key in defaults) {
    obj[key] = obj[key] || defaults[key];
  }

  return obj;
}
