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

import socket from '@ohos.net.socket'
import SMB2Forge from './smb2_forge'


var SMB2Connection = {
  close: function (connection) {
  },
  requireConnect: function (connection,method) {
    return function(path,callback){}
  },
  init: function (connection) {
  }
}


SMB2Connection.close = function (connection) {
  clearAutoCloseTimeout(connection);
  if (connection.connected) {
    connection.connected = false;
    connection.socket.close();
  }
},
SMB2Connection.requireConnect = function (connection,method) {

  return function (path,callback) {
    var args = Array.prototype.slice.call(arguments);
    connect(connection, function (err) {
      // process the cb
      var cb = args.pop();
      cb = scheduleAutoClose(connection, cb);
      args.push(cb);

      // manage the connection error
      if (err) {
        cb(err)
      } else{
        method.apply(connection, args);
      }
    });
  }
},
SMB2Connection.init = function (connection) {
  // create a socket
  connection.connected = false;
  connection.socket = socket.constructTCPSocketInstance();
  // attach data events to socket


  connection.socket.on('message',SMB2Forge.response(connection))
  connection.errorHandler = [];
  connection.socket.on('error', function (err) {
    if (connection.errorHandler.length > 0) {
      connection.errorHandler[0].call(null, err)
    }
  });

}


export default SMB2Connection;


/*
 * PRIVATE FUNCTION TO HANDLE CONNECTION
 */
function connect(connection, cb) {

  if (connection.connected) {
    cb && cb(null);
    return;
  }

  cb = scheduleAutoClose(connection, cb);


//  let ipInfo = wifi.getIpInfo()
//  let ip = IpTool.intToIP(ipInfo.ipAddress)
  let promise =  connection.socket.bind({ address: connection.clientIP, port: 0, family: 1 });
  promise.then(() => {
    console.info('smb-- bind tcp success to:' + connection.ip);
    connection.socket.connect({
      address: { address: connection.ip, port: connection.port },
      timeout: connection.autoCloseTimeout
    }).then(() => {
      console.info('smj-- connect server success');
    }).catch(err => {
      //        if (connectEvent) {
      //          connectEvent(false, err)
      //        }
      console.error('smj-- connect server fail ' + JSON.stringify(err));
    });
  }).catch(err => {
//    connectEvent(false, err)
    console.error('smb-- bind tcp fail ' + err);
  });



  // SMB2 negotiate connection
  SMB2Forge.request('negotiate', {}, connection, function (err) {
    console.log("smb connection  0:")
    if (err) cb && cb(err);
    // SMB2 setup session / negotiate ntlm
    else SMB2Forge.request('session_setup_step1', {}, connection, function (err) {
      console.log("smb connection  1:")
      if (err) cb && cb(err);
      // SMB2 setup session / autheticate with ntlm
      else SMB2Forge.request('session_setup_step2', {}, connection, function (err) {
        console.log("smb connection  2:")
        if (err) cb && cb(err);

        // SMB2 tree connect
        else SMB2Forge.request('tree_connect', {}, connection, function (err) {
          console.log("smb connection  3:")
          if (err) cb && cb(err);
          else {
            connection.connected = true;
            cb && cb(null);
          }
        });
      });
    });
  });
}


/*
 * PRIVATE FUNCTION TO HANDLE CLOSING THE CONNECTION
 */
function clearAutoCloseTimeout(connection) {
  if (connection.scheduledAutoClose) {
    clearTimeout(connection.scheduledAutoClose);
    connection.scheduledAutoClose = null;
  }
}

function setAutoCloseTimeout(connection) {
  clearAutoCloseTimeout(connection);
  if (connection.autoCloseTimeout != 0) {
    connection.scheduledAutoClose = setTimeout(function () {
      connection.close();
    }, connection.autoCloseTimeout);
  }
}

function scheduleAutoClose(connection, cb) {
  addErrorListener(connection, cb);
  clearAutoCloseTimeout(connection);
  return function () {
    removeErrorListener(connection);
    setAutoCloseTimeout(connection);
    cb.apply(null, arguments);
  }
}


/*
 * PRIVATE FUNCTIONS TO HANDLE ERRORS
 */
function addErrorListener(connection, callback) {
  connection.errorHandler.unshift(callback);
}

function removeErrorListener(connection) {
  connection.errorHandler.shift();
}


