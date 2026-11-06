import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

export class ByteUtil {
  static encode(text: string): Uint8Array {
    return new util.TextEncoder().encodeInto(text);
  }

  static decode(bytes: Uint8Array): string {
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  static concat(parts: Uint8Array[]): Uint8Array {
    let total: number = 0;
    for (let i = 0; i < parts.length; i++) {
      total += parts[i].length;
    }
    let out = new Uint8Array(total);
    let pos = 0;
    for (let i = 0; i < parts.length; i++) {
      out.set(parts[i], pos);
      pos += parts[i].length;
    }
    return out;
  }

  static toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    let buf = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(buf).set(bytes);
    return buf;
  }

  static fromArrayBuffer(buf: ArrayBuffer): Uint8Array {
    return new Uint8Array(buf);
  }

  static hex(bytes: Uint8Array): string {
    const table: string = '0123456789ABCDEF';
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      let v: number = bytes[i];
      out += table.charAt((v >>> 4) & 0x0F);
      out += table.charAt(v & 0x0F);
    }
    return out;
  }

  static randomId(): string {
    return util.generateRandomUUID(false);
  }

  static async sha256Hex(data: Uint8Array): Promise<string> {
    let md = cryptoFramework.createMd('SHA256');
    await md.update({ data: data });
    let digest = await md.digest();
    return ByteUtil.hex(digest.data);
  }
}
