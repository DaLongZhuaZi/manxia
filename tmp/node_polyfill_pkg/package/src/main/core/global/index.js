exports.crypto = {
  getRandomValues(unit) {
    for (let i = 0; i < unit.length; i++) {
      unit[i] = (Math.random() * 10).toFixed(0);
    }
  },
  randomBytes() {
    const unit = new Uint8Array();
    for (let i = 0; i < 10; i++) {
      unit[i] = (Math.random() * 10).toFixed(0);
    }
  },
};
