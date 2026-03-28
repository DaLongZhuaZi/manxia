function setImmediate(params,time) {
    time = time == undefined ? 0 : time
    setTimeout(params, time);
}

module.exports = {
    setImmediate
}