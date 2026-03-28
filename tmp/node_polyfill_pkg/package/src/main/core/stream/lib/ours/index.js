const CustomStream = require("../stream");

const originalDestroy = CustomStream.Readable.destroy;
exports._isUint8Array = CustomStream._isUint8Array;
exports.isDisturbed = CustomStream.isDisturbed;
exports.isErrored = CustomStream.isErrored;
exports.isReadable = CustomStream.isReadable;
exports.Readable = CustomStream.Readable;
exports.Writable = CustomStream.Writable;
exports.Duplex = CustomStream.Duplex;
exports.Transform = CustomStream.Transform;
exports.PassThrough = CustomStream.PassThrough;
exports.addAbortSignal = CustomStream.addAbortSignal;
exports.finished = CustomStream.finished;
exports.destroy = CustomStream.destroy;
exports.destroy = originalDestroy;
exports.pipeline = CustomStream.pipeline;
exports.compose = CustomStream.compose;

// module.exports.default = module.exports;
