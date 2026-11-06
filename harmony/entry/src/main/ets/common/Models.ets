/**
 * Wire models of LocalSend Protocol v2.2.
 * Field names and casing intentionally match the official REST API.
 *
 * ArkTS forbids index signatures and dynamic property access, so the protocol's
 * JSON dictionaries (`files`) are represented internally as arrays and are
 * encoded/decoded by protocol/ProtocolJson.ets.
 */
export interface DeviceInfo {
  alias: string;
  version: string;
  deviceModel: string;
  deviceType: string;
  fingerprint: string;
  port?: number;
  protocol?: string;
  download?: boolean;
  announce?: boolean;
}

export interface FileDto {
  id: string;
  fileName: string;
  size: number;
  fileType: string;
  sha256?: string;
  preview?: string;
}

export interface TokenEntry {
  id: string;
  token: string;
}

export interface PrepareUploadResult {
  sessionId: string;
  tokens: TokenEntry[];
}

export interface NearbyDevice {
  ip: string;
  port: number;
  protocol: string;
  info: DeviceInfo;
  lastSeen: number;
}

/** A file selected from the system document picker, ready to be sent. */
export interface SelectedFile {
  id: string;
  fileName: string;
  size: number;
  fileType: string;
  uri: string;
}

export enum TransferDirection {
  SEND = 'send',
  RECEIVE = 'receive'
}

export enum TransferStatus {
  PENDING = 'pending',
  RUNNING = 'running',
  DONE = 'done',
  FAILED = 'failed',
  DECLINED = 'declined'
}

export interface TransferRecord {
  id: string;
  fileName: string;
  size: number;
  peer: string;
  direction: TransferDirection;
  status: TransferStatus;
  timestamp: number;
  detail: string;
}

export function makeDeviceInfo(alias: string, fingerprint: string, port: number,
  announce: boolean, download: boolean): DeviceInfo {
  let info: DeviceInfo = {
    alias: alias,
    version: '2.2',
    deviceModel: 'HarmonyOS',
    deviceType: 'mobile',
    fingerprint: fingerprint,
    port: port,
    protocol: 'http',
    download: download,
    announce: announce
  };
  return info;
}
