import { fileIo as fs } from '@kit.CoreFileKit';
import { ByteUtil } from './ByteUtil';
import { LsConstants } from '../common/Constants';
import { AppContext } from '../common/AppContext';

const MIME_TABLE: Map<string, string> = new Map<string, string>([
  ['txt', 'text/plain'], ['md', 'text/markdown'], ['json', 'application/json'],
  ['png', 'image/png'], ['jpg', 'image/jpeg'], ['jpeg', 'image/jpeg'],
  ['gif', 'image/gif'], ['webp', 'image/webp'], ['svg', 'image/svg+xml'],
  ['mp4', 'video/mp4'], ['mkv', 'video/x-matroska'], ['mp3', 'audio/mpeg'],
  ['pdf', 'application/pdf'], ['zip', 'application/zip'], ['apk', 'application/vnd.android.package-archive'],
  ['hap', 'application/hap'], ['doc', 'application/msword'], ['xls', 'application/vnd.ms-excel']
]);

export class FileUtil {
  static fileNameFromUri(uri: string): string {
    let clean: string = uri;
    try {
      clean = decodeURIComponent(uri);
    } catch (e) {
      clean = uri;
    }
    let q: number = clean.indexOf('?');
    if (q >= 0) {
      clean = clean.substring(0, q);
    }
    let parts: string[] = clean.split('/');
    let name: string = parts[parts.length - 1];
    return name.length === 0 ? 'file.bin' : name;
  }

  static mimeOf(fileName: string): string {
    let dot: number = fileName.lastIndexOf('.');
    if (dot < 0) {
      return 'application/octet-stream';
    }
    let ext: string = fileName.substring(dot + 1).toLowerCase();
    let mime: string | undefined = MIME_TABLE.get(ext);
    return mime === undefined ? 'application/octet-stream' : mime;
  }

  static sanitize(fileName: string): string {
    let name: string = fileName;
    name = name.replace(/[\\/:*?"<>|]/g, '_');
    name = name.replace(/\.\./g, '_');
    if (name.length === 0) {
      name = 'unnamed';
    }
    return name;
  }

  /** Reads a document-picker URI fully into memory. Files larger than MAX_UPLOAD_BYTES are rejected. */
  static async readAllFromUri(uri: string): Promise<Uint8Array> {
    let file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let chunks: Uint8Array[] = [];
    let total: number = 0;
    try {
      while (true) {
        let buf = new ArrayBuffer(LsConstants.HTTP_CHUNK);
        let n: number = fs.readSync(file.fd, buf);
        if (n <= 0) {
          break;
        }
        total += n;
        if (total > LsConstants.MAX_UPLOAD_BYTES) {
          throw new Error('File exceeds the 64 MiB MVP limit');
        }
        chunks.push(new Uint8Array(buf, 0, n));
        if (n < LsConstants.HTTP_CHUNK) {
          break;
        }
      }
    } finally {
      fs.closeSync(file);
    }
    return ByteUtil.concat(chunks);
  }

  /** Writes an incoming file into the app sandbox and resolves duplicate names. */
  static saveIncoming(fileName: string, data: Uint8Array): string {
    let dir: string = AppContext.filesDir() + '/LocalSend';
    try {
      fs.accessSync(dir);
    } catch (e) {
      fs.mkdirSync(dir, true);
    }
    let safe: string = FileUtil.sanitize(fileName);
    let candidate: string = dir + '/' + safe;
    let counter: number = 1;
    while (FileUtil.exists(candidate)) {
      let dot: number = safe.lastIndexOf('.');
      if (dot > 0) {
        candidate = dir + '/' + safe.substring(0, dot) + ' (' + counter + ')' + safe.substring(dot);
      } else {
        candidate = dir + '/' + safe + ' (' + counter + ')';
      }
      counter++;
    }
    let file = fs.openSync(candidate, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, ByteUtil.toArrayBuffer(data));
    } finally {
      fs.closeSync(file);
    }
    return candidate;
  }

  static exists(path: string): boolean {
    try {
      fs.accessSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  static receiveDir(): string {
    return AppContext.filesDir() + '/LocalSend';
  }
}
