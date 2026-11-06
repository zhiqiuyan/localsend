import { http } from '@kit.NetworkKit';
import {
  DeviceInfo, FileDto, NearbyDevice, PrepareUploadResult
} from '../common/Models';
import { LsConstants } from '../common/Constants';
import { LsLogger } from '../common/Logger';
import { ByteUtil } from '../util/ByteUtil';
import { ProtocolJson } from './ProtocolJson';
import { LsRoutes } from './Routes';

export class LsHttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

interface LsHttpResult {
  status: number;
  body: string;
}

/** Sender side of LocalSend Protocol v2.2, built on the system HTTP client. */
export class LocalSendClient {
  static async register(device: NearbyDevice, self: DeviceInfo): Promise<DeviceInfo | null> {
    let url: string = LsRoutes.targetUrl(device, LsRoutes.REGISTER, '');
    let result = await LocalSendClient.request(url, http.RequestMethod.POST,
      'application/json', JSON.stringify(self), LsConstants.HTTP_CONNECT_TIMEOUT_MS);
    if (result.status !== 200) {
      LsLogger.warn('register failed with ' + result.status.toString());
      return null;
    }
    try {
      return JSON.parse(result.body) as DeviceInfo;
    } catch (e) {
      return null;
    }
  }

  static async prepareUpload(device: NearbyDevice, self: DeviceInfo,
    files: FileDto[], pin: string): Promise<PrepareUploadResult> {
    let params = new Map<string, string>();
    if (pin.length > 0) {
      params.set('pin', pin);
    }
    let url: string = LsRoutes.targetUrl(device, LsRoutes.PREPARE_UPLOAD, LsRoutes.query(params));
    let body: string = ProtocolJson.buildPrepareUploadBody(self, files);
    let result = await LocalSendClient.request(url, http.RequestMethod.POST,
      'application/json', body, LsConstants.HTTP_CONNECT_TIMEOUT_MS);
    if (result.status !== 200) {
      throw new LsHttpError(result.status, 'prepare-upload failed: ' + result.status.toString());
    }
    let parsed: PrepareUploadResult = ProtocolJson.parsePrepareUploadResult(result.body);
    if (parsed.sessionId.length === 0) {
      throw new LsHttpError(result.status, 'invalid prepare-upload response');
    }
    return parsed;
  }

  static async upload(device: NearbyDevice, sessionId: string, fileId: string,
    token: string, data: Uint8Array): Promise<void> {
    let params = new Map<string, string>();
    params.set('sessionId', sessionId);
    params.set('fileId', fileId);
    params.set('token', token);
    let url: string = LsRoutes.targetUrl(device, LsRoutes.UPLOAD, LsRoutes.query(params));
    let result = await LocalSendClient.request(url, http.RequestMethod.POST,
      'application/octet-stream', ByteUtil.toArrayBuffer(data), LsConstants.HTTP_READ_TIMEOUT_MS);
    if (result.status < 200 || result.status >= 300) {
      throw new LsHttpError(result.status, 'upload failed: ' + result.status.toString());
    }
  }

  static async cancel(device: NearbyDevice, sessionId: string): Promise<void> {
    let params = new Map<string, string>();
    params.set('sessionId', sessionId);
    let url: string = LsRoutes.targetUrl(device, LsRoutes.CANCEL, LsRoutes.query(params));
    try {
      await LocalSendClient.request(url, http.RequestMethod.POST,
        'application/json', '{}', LsConstants.HTTP_CONNECT_TIMEOUT_MS);
    } catch (e) {
      LsLogger.warn('cancel request failed');
    }
  }

  static async info(device: NearbyDevice): Promise<DeviceInfo | null> {
    let url: string = LsRoutes.targetUrl(device, LsRoutes.INFO, '');
    let result = await LocalSendClient.request(url, http.RequestMethod.GET,
      'application/json', '', LsConstants.HTTP_CONNECT_TIMEOUT_MS);
    if (result.status !== 200) {
      return null;
    }
    try {
      return JSON.parse(result.body) as DeviceInfo;
    } catch (e) {
      return null;
    }
  }

  private static async request(url: string, method: http.RequestMethod, contentType: string,
    payload: string | ArrayBuffer, readTimeout: number): Promise<LsHttpResult> {
    let request = http.createHttp();
    try {
      let options: http.HttpRequestOptions = {
        method: method,
        header: { 'Content-Type': contentType },
        extraData: payload,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: LsConstants.HTTP_CONNECT_TIMEOUT_MS,
        readTimeout: readTimeout,
        usingProxy: false
      };
      let response = await request.request(url, options);
      let result: LsHttpResult = {
        status: response.responseCode,
        body: response.result as string
      };
      return result;
    } finally {
      request.destroy();
    }
  }
}
