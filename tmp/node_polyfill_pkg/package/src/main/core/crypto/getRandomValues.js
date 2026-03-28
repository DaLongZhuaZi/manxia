const cryptoFramework = require("@ohos.security.cryptoFramework");

exports.getRandomValues = (typedArray) => {
  const len = (typedArray && typedArray.length) || 0;
  const rand = cryptoFramework.createRandom();
  const randData = rand.generateRandomSync(len).data;
  for (let i = 0; i < len; i += 1) {
    typedArray[i] = randData[i] & 255;
  }
  return typedArray;
};
