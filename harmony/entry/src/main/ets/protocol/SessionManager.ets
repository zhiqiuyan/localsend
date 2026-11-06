import { FileDto } from '../common/Models';
import { ByteUtil } from '../util/ByteUtil';

/** Only one upload session may be active at a time (upstream V2State semantics). */
export class UploadSession {
  sessionId: string;
  peerIp: string;
  files: Map<string, FileDto> = new Map<string, FileDto>();
  tokens: Map<string, string> = new Map<string, string>();
  createdAt: number;

  constructor(sessionId: string, peerIp: string) {
    this.sessionId = sessionId;
    this.peerIp = peerIp;
    this.createdAt = Date.now();
  }
}

export class SessionManager {
  private current: UploadSession | null = null;

  hasActive(): boolean {
    return this.current !== null;
  }

  active(): UploadSession | null {
    return this.current;
  }

  create(peerIp: string, files: FileDto[]): UploadSession | null {
    if (this.current !== null) {
      // A session whose sender disappeared must not block the receiver forever.
      if (Date.now() - this.current.createdAt > 10 * 60 * 1000) {
        this.current = null;
      } else {
        return null;
      }
    }
    let session = new UploadSession(ByteUtil.randomId(), peerIp);
    for (let i = 0; i < files.length; i++) {
      session.files.set(files[i].id, files[i]);
      session.tokens.set(files[i].id, ByteUtil.randomId());
    }
    this.current = session;
    return session;
  }

  find(sessionId: string): UploadSession | null {
    if (this.current === null || this.current.sessionId !== sessionId) {
      return null;
    }
    return this.current;
  }

  /** Validates sessionId, fileId, per-file token and the bound sender IP. */
  validate(sessionId: string, fileId: string, token: string, peerIp: string): UploadSession | null {
    let session = this.find(sessionId);
    if (session === null || session.peerIp !== peerIp) {
      return null;
    }
    let expected: string | undefined = session.tokens.get(fileId);
    if (expected === undefined || expected !== token) {
      return null;
    }
    return session;
  }

  remove(sessionId: string): void {
    let session = this.find(sessionId);
    if (session !== null) {
      this.current = null;
    }
  }

  clear(): void {
    this.current = null;
  }
}
