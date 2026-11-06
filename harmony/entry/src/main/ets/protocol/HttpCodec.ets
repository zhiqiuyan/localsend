import { ByteUtil } from '../util/ByteUtil';
import { LsRoutes } from './Routes';
import { LsConstants } from '../common/Constants';

/**
 * Minimal HTTP/1.1 message codec for the TCPSocketServer-based receiver.
 * HarmonyOS exposes TCP/UDP/TLS sockets but no HTTP server kit, so the
 * request line, headers and Content-Length body are parsed here.
 */
export interface HttpRequest {
  method: string;
  path: string;
  route: string;
  query: Map<string, string>;
  headers: Map<string, string>;
  body: Uint8Array;
  remoteIp: string;
}

export interface HttpResponseData {
  status: number;
  reason: string;
  body?: Uint8Array;
  contentType?: string;
}

interface HeadState {
  method: string;
  route: string;
  query: Map<string, string>;
  headers: Map<string, string>;
  contentLength: number;
}

export type RequestHandler = (req: HttpRequest) => Promise<HttpResponseData>;
export type ResponseSender = (data: ArrayBuffer) => Promise<void>;

export function statusResponse(status: number, reason: string): HttpResponseData {
  let response: HttpResponseData = { status: status, reason: reason };
  return response;
}

export function jsonResponse(status: number, reason: string, json: string): HttpResponseData {
  let response: HttpResponseData = {
    status: status,
    reason: reason,
    body: ByteUtil.encode(json),
    contentType: 'application/json; charset=utf-8'
  };
  return response;
}

export function buildResponse(resp: HttpResponseData): Uint8Array {
  let head: string = 'HTTP/1.1 ' + resp.status.toString() + ' ' + resp.reason + '\r\n';
  let bodyLength: number = resp.body === undefined ? 0 : resp.body.length;
  if (resp.body !== undefined) {
    let type: string = resp.contentType === undefined ? 'application/octet-stream' : resp.contentType;
    head += 'Content-Type: ' + type + '\r\n';
  }
  head += 'Content-Length: ' + bodyLength.toString() + '\r\n';
  head += 'Connection: close\r\n';
  head += 'Access-Control-Allow-Origin: *\r\n';
  head += '\r\n';
  let headBytes: Uint8Array = ByteUtil.encode(head);
  if (resp.body === undefined) {
    return headBytes;
  }
  return ByteUtil.concat([headBytes, resp.body]);
}

function findHeaderEnd(data: Uint8Array): number {
  for (let i = 0; i + 3 < data.length; i++) {
    if (data[i] === 13 && data[i + 1] === 10 && data[i + 2] === 13 && data[i + 3] === 10) {
      return i;
    }
  }
  return -1;
}

function parseHead(text: string): HeadState {
  let lines: string[] = text.split('\r\n');
  let requestLine: string[] = lines[0].split(' ');
  let method: string = requestLine.length > 0 ? requestLine[0] : '';
  let fullPath: string = requestLine.length > 1 ? requestLine[1] : '/';
  let q: number = fullPath.indexOf('?');
  let route: string = q >= 0 ? fullPath.substring(0, q) : fullPath;
  let rawQuery: string = q >= 0 ? fullPath.substring(q + 1) : '';
  let headers = new Map<string, string>();
  for (let i = 1; i < lines.length; i++) {
    let colon: number = lines[i].indexOf(':');
    if (colon > 0) {
      headers.set(lines[i].substring(0, colon).trim().toLowerCase(), lines[i].substring(colon + 1).trim());
    }
  }
  let contentLength: number = 0;
  let lengthText: string | undefined = headers.get('content-length');
  if (lengthText !== undefined) {
    contentLength = Number.parseInt(lengthText);
    if (isNaN(contentLength) || contentLength < 0) {
      contentLength = 0;
    }
  }
  let state: HeadState = {
    method: method,
    route: route,
    query: LsRoutes.parseQuery(rawQuery),
    headers: headers,
    contentLength: contentLength
  };
  return state;
}

/** Per-connection state machine. One request per connection (Connection: close). */
export class HttpConnection {
  private pending: Uint8Array = new Uint8Array(0);
  private head: HeadState | null = null;
  private handler: RequestHandler;
  private sender: ResponseSender;
  private remoteIp: string;
  private finished: boolean = false;

  constructor(handler: RequestHandler, sender: ResponseSender, remoteIp: string) {
    this.handler = handler;
    this.sender = sender;
    this.remoteIp = remoteIp;
  }

  async feed(chunk: ArrayBuffer): Promise<void> {
    if (this.finished) {
      return;
    }
    this.pending = ByteUtil.concat([this.pending, new Uint8Array(chunk)]);
    if (this.pending.length > LsConstants.MAX_UPLOAD_BYTES + 8192) {
      this.finished = true;
      await this.sender(ByteUtil.toArrayBuffer(buildResponse(statusResponse(413, 'Payload Too Large'))));
      return;
    }
    if (this.head === null) {
      let end: number = findHeaderEnd(this.pending);
      if (end < 0) {
        return;
      }
      let headText: string = ByteUtil.decode(this.pending.subarray(0, end));
      this.head = parseHead(headText);
      this.pending = this.pending.subarray(end + 4);
      let encoding: string | undefined = this.head.headers.get('transfer-encoding');
      if (encoding !== undefined && encoding.toLowerCase().indexOf('chunked') >= 0) {
        this.finished = true;
        await this.sender(ByteUtil.toArrayBuffer(buildResponse(statusResponse(400, 'Chunked Body Not Supported'))));
        return;
      }
    }
    if (this.head.contentLength > LsConstants.MAX_UPLOAD_BYTES) {
      this.finished = true;
      await this.sender(ByteUtil.toArrayBuffer(buildResponse(statusResponse(413, 'Payload Too Large'))));
      return;
    }
    if (this.pending.length < this.head.contentLength) {
      return;
    }
    this.finished = true;
    let request: HttpRequest = {
      method: this.head.method,
      path: this.head.route,
      route: this.head.route,
      query: this.head.query,
      headers: this.head.headers,
      body: this.pending.subarray(0, this.head.contentLength),
      remoteIp: this.remoteIp
    };
    let response: HttpResponseData;
    try {
      response = await this.handler(request);
    } catch (e) {
      response = statusResponse(500, 'Internal Server Error');
    }
    await this.sender(ByteUtil.toArrayBuffer(buildResponse(response)));
  }
}
