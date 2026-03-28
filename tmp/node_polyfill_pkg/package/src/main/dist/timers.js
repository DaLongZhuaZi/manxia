import { g as getDefaultExportFromCjs } from './_commonjsHelpers-YxXKG0rd.js';

function setImmediate(params,time) {
    time = time == undefined ? 0 : time;
    setTimeout(params, time);
}

var timers = {
    setImmediate
};

var index = /*@__PURE__*/getDefaultExportFromCjs(timers);

export { index as default };
