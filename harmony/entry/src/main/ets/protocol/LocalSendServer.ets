import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppSettings } from '../common/Settings';
import { LsConstants } from '../common/Constants';
import { LsLogger } from '../common/Logger';
import {
  DeviceInfo, FileDto, TokenEntry, makeDeviceInfo
} from '../common/Models';
import { ByteUtil } from '../util/ByteUtil';
import { FileUtil } from '../util/FileUtil';
import { LsRoutes } from './Routes';
import { ProtocolJson } from './ProtocolJson';
import { SessionManager } from './SessionManager';
import {
  HttpConnection, HttpRequest, HttpResponseData, RequestHandler, ResponseSender,
  jsonResponse, statusResponse
} from './HttpCodec';

export interface SharedFile {
  dto: FileDto;
  data: Uint8Array;
}

export interface ServerEvents {
  onRegister(info: DeviceInfo, ip: string, port: number): void;
  onIncomingRequest(info: DeviceInfo, files: FileDto[], ip: string): Promise<boolean>;
  onFileReceived(fileName: string, size: number, ip: string, path: string): void;
  onCancel(sessionId: string, ip: string): void;
  onError(message: string): void;
}

/**
 * LocalSend Protocol v2.2 receiver.
 * HarmonyOS has no HTTP server kit, so a TCPSocketServer is paired with
 * HttpCodec to serve the REST endpoints. HTTPS is not enabled in the MVP;
 * see harmony/README.md for the TLSSocketServer migration path.
 */
export class LocalSendServer {
  private server: socket.TCPSocketServer | null = null;
  private sessions: SessionManager = new SessionManager();
  private settings: AppSettings;
  private events: ServerEvents;
  private webSessionId: string = '';
  private shared: Map<string, SharedFile> = new Map<string, SharedFile>();

  constructor(settings: AppSettings, events: ServerEvents) {
    this.settings = settings;
    this.events = events;
  }

  async start(): Promise<void> {
    let s = socket.constructTCPSocketServerInstance();
    s.on('connect', (conn: socket.TCPSocketConnection) => {
      this.onConnect(conn);
    });
    s.on('error', (err: BusinessError) => {
      this.events.onError('tcp server error ' + err.code.toString() + ': ' + err.message);
    });
    await s.listen({ address: '0.0.0.0', port: this.settings.port });
    this.server = s;
    LsLogger.info('LocalSend receiver listening on port ' + this.settings.port.toString());
  }

  async stop(): Promise<void> {
    if (this.server !== null) {
      try {
        await this.server.close();
      } catch (e) {
        LsLogger.warn('tcp server close failed');
      }
      this.server = null;
    }
    this.sessions.clear();
  }

  /** Publishes files for the reverse (link sharing) download API. */
  setWebShare(files: SharedFile[]): string {
    this.shared.clear();
    for (let i = 0; i < files.length; i++) {
      this.shared.set(files[i].dto.id, files[i]);
    }
    this.webSessionId = ByteUtil.randomId();
    return this.webSessionId;
  }

  clearWebShare(): void {
    this.shared.clear();
    this.webSessionId = '';
  }

  private selfInfo(): DeviceInfo {
    return makeDeviceInfo(this.settings.alias, this.settings.fingerprint,
      this.settings.port, false, this.settings.webSend);
  }

  private onConnect(conn: socket.TCPSocketConnection): void {
    conn.getRemoteAddress().then((addr: socket.NetAddress) => {
      this.setupConnection(conn, addr.address);
    }).catch(() => {
      this.setupConnection(conn, '');
    });
  }

  private setupConnection(conn: socket.TCPSocketConnection, remoteIp: string): void {
    let sender: ResponseSender = async (data: ArrayBuffer): Promise<void> => {
      await conn.send({ data: data });
      try {
        await conn.close();
      } catch (e) {
        // The peer may already have closed the connection.
      }
    };
    let handler: RequestHandler = async (req: HttpRequest): Promise<HttpResponseData> => {
      return await this.dispatch(req);
    };
    let codec = new HttpConnection(handler, sender, remoteIp);
    conn.on('message', (data: socket.SocketMessageInfo) => {
      codec.feed(data.message);
    });
    conn.on('error', () => {
      LsLogger.warn('connection error from ' + remoteIp);
    });
  }

  private async dispatch(req: HttpRequest): Promise<HttpResponseData> {
    if (req.method === 'GET' && req.route === LsRoutes.INFO) {
      return jsonResponse(200, 'OK', JSON.stringify(this.selfInfo()));
    }
    if (req.method === 'POST' && req.route === LsRoutes.REGISTER) {
      return this.handleRegister(req);
    }
    if (req.method === 'POST' && req.route === LsRoutes.PREPARE_UPLOAD) {
      return await this.handlePrepareUpload(req);
    }
    if (req.method === 'POST' && req.route === LsRoutes.UPLOAD) {
      return await this.handleUpload(req);
    }
    if (req.method === 'POST' && req.route === LsRoutes.CANCEL) {
      return this.handleCancel(req);
    }
    if (req.method === 'POST' && req.route === LsRoutes.PREPARE_DOWNLOAD) {
      return this.handlePrepareDownload(req);
    }
    if (req.method === 'GET' && req.route === LsRoutes.DOWNLOAD) {
      return this.handleDownload(req);
    }
    if (req.method === 'POST' && req.route === LsRoutes.SHOW) {
      return statusResponse(200, 'OK');
    }
    if (req.method === 'GET' && (req.route === '/' || req.route === '/index.html')) {
      return this.handleWebIndex();
    }
    return statusResponse(404, 'Not Found');
  }

  private handleRegister(req: HttpRequest): HttpResponseData {
    let dto: DeviceInfo;
    try {
      dto = JSON.parse(ByteUtil.decode(req.body)) as DeviceInfo;
    } catch (e) {
      return statusResponse(400, 'Invalid Body');
    }
    if (dto.fingerprint === undefined || dto.alias === undefined) {
      return statusResponse(400, 'Invalid Body');
    }
    let port: number = dto.port === undefined ? LsConstants.DEFAULT_PORT : dto.port;
    this.events.onRegister(dto, req.remoteIp, port);
    return jsonResponse(200, 'OK', JSON.stringify(this.selfInfo()));
  }

  private async handlePrepareUpload(req: HttpRequest): Promise<HttpResponseData> {
    if (this.settings.pin.length > 0) {
      let pin: string | undefined = req.query.get('pin');
      if (pin === undefined || pin !== this.settings.pin) {
        return statusResponse(401, 'PIN required / Invalid PIN');
      }
    }
    let body: string = ByteUtil.decode(req.body);
    let info: DeviceInfo | null = ProtocolJson.parseInfo(body);
    let files: FileDto[] = ProtocolJson.parseFileList(body);
    if (info === null) {
      return statusResponse(400, 'Invalid Body');
    }
    if (files.length === 0) {
      return statusResponse(204, 'No Content');
    }
    if (this.sessions.hasActive()) {
      return statusResponse(409, 'Blocked By Another Session');
    }
    let accepted: boolean = await this.events.onIncomingRequest(info, files, req.remoteIp);
    if (!accepted) {
      return statusResponse(403, 'Rejected');
    }
    let session = this.sessions.create(req.remoteIp, files);
    if (session === null) {
      return statusResponse(409, 'Blocked By Another Session');
    }
    let tokens: TokenEntry[] = [];
    session.tokens.forEach((value: string, key: string) => {
      let entry: TokenEntry = { id: key, token: value };
      tokens.push(entry);
    });
    return jsonResponse(200, 'OK', ProtocolJson.buildPrepareUploadResponse(session.sessionId, tokens));
  }

  private async handleUpload(req: HttpRequest): Promise<HttpResponseData> {
    let sessionId: string | undefined = req.query.get('sessionId');
    let fileId: string | undefined = req.query.get('fileId');
    let token: string | undefined = req.query.get('token');
    if (sessionId === undefined || fileId === undefined || token === undefined) {
      return statusResponse(400, 'Missing Parameters');
    }
    let session = this.sessions.validate(sessionId, fileId, token, req.remoteIp);
    if (session === null) {
      return statusResponse(403, 'Invalid Token Or IP Address');
    }
    let dto: FileDto | undefined = session.files.get(fileId);
    if (dto === undefined) {
      return statusResponse(400, 'Missing Parameters');
    }
    if (dto.sha256 !== undefined && dto.sha256.length > 0) {
      let actual: string = await ByteUtil.sha256Hex(req.body);
      if (actual.toLowerCase() !== dto.sha256.toLowerCase()) {
        this.sessions.remove(sessionId);
        return statusResponse(422, 'Checksum Mismatch');
      }
    }
    let path: string = FileUtil.saveIncoming(dto.fileName, req.body);
    this.events.onFileReceived(dto.fileName, req.body.length, req.remoteIp, path);
    LsLogger.info('received ' + dto.fileName + ' -> ' + path);
    return statusResponse(200, 'OK');
  }

  private handleCancel(req: HttpRequest): HttpResponseData {
    let sessionId: string | undefined = req.query.get('sessionId');
    if (sessionId === undefined) {
      return statusResponse(400, 'Missing Parameters');
    }
    this.sessions.remove(sessionId);
    this.events.onCancel(sessionId, req.remoteIp);
    return statusResponse(200, 'OK');
  }

  private handlePrepareDownload(req: HttpRequest): HttpResponseData {
    if (this.settings.pin.length > 0) {
      let pin: string | undefined = req.query.get('pin');
      if (pin === undefined || pin !== this.settings.pin) {
        return statusResponse(401, 'PIN required / Invalid PIN');
      }
    }
    if (this.shared.size === 0) {
      return statusResponse(404, 'No Shared Files');
    }
    let files: FileDto[] = [];
    this.shared.forEach((item: SharedFile) => {
      files.push(item.dto);
    });
    return jsonResponse(200, 'OK',
      ProtocolJson.buildPrepareDownloadResponse(this.selfInfo(), this.webSessionId, files));
  }

  private handleDownload(req: HttpRequest): HttpResponseData {
    let sessionId: string | undefined = req.query.get('sessionId');
    let fileId: string | undefined = req.query.get('fileId');
    if (sessionId === undefined || fileId === undefined || sessionId !== this.webSessionId) {
      return statusResponse(400, 'Missing Parameters');
    }
    let item: SharedFile | undefined = this.shared.get(fileId);
    if (item === undefined) {
      return statusResponse(404, 'File Not Found');
    }
    let response: HttpResponseData = {
      status: 200,
      reason: 'OK',
      body: item.data,
      contentType: item.dto.fileType
    };
    return response;
  }

  private handleWebIndex(): HttpResponseData {
    let html: string = '<!doctype html><html><head><meta charset="utf-8"><title>LocalSend</title></head>' +
      '<body><h1>LocalSend</h1><ul>';
    this.shared.forEach((item: SharedFile, key: string) => {
      html += '<li><a href="' + LsRoutes.DOWNLOAD + '?sessionId=' + this.webSessionId +
        '&amp;fileId=' + encodeURIComponent(key) + '">' + item.dto.fileName + '</a></li>';
    });
    html += '</ul></body></html>';
    let response: HttpResponseData = {
      status: 200,
      reason: 'OK',
      body: ByteUtil.encode(html),
      contentType: 'text/html; charset=utf-8'
    };
    return response;
  }
}
