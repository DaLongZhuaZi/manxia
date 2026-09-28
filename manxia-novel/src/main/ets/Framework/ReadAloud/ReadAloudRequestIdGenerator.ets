const REQUEST_ID_SERIAL_MAX: number = 1000000;
const REQUEST_ID_SERIAL_PAD_LENGTH: number = 6;
const REQUEST_ID_RANDOM_RANGE: number = 10000;
const REQUEST_ID_RANDOM_PAD_LENGTH: number = 4;

export class ReadAloudRequestIdGenerator {
  private static serial: number = 0;

  static next(_prefix: string): string {
    ReadAloudRequestIdGenerator.serial = (ReadAloudRequestIdGenerator.serial + 1) % REQUEST_ID_SERIAL_MAX;
    const timePart = String(Date.now());
    const serialPart = String(ReadAloudRequestIdGenerator.serial).padStart(REQUEST_ID_SERIAL_PAD_LENGTH, '0');
    const randomPart = String(Math.floor(Math.random() * REQUEST_ID_RANDOM_RANGE)).padStart(
      REQUEST_ID_RANDOM_PAD_LENGTH,
      '0'
    );
    return `${timePart}${serialPart}${randomPart}`;
  }
}
