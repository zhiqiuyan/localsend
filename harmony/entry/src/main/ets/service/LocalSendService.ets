import { connection } from '@kit.NetworkKit';
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { AppContext } from '../common/AppContext';
import { AppSettings, SettingsStore } from '../common/Settings';
import { LsConstants } from '../common/Constants';
import { LsLogger } from '../common/Logger';
import {
  DeviceInfo, FileDto, NearbyDevice, SelectedFile, TransferDirection,
  TransferRecord, TransferStatus, makeDeviceInfo
} from '../common/Models';
import { ByteUtil } from '../util/ByteUtil';
import { FileUtil } from '../util/FileUtil';
import { LocalSendClient, LsHttpError } from '../protocol/LocalSendClient';
import { LocalSendServer, ServerEvents, SharedFile } from '../protocol/LocalSendServer';
import { MulticastDiscovery, DiscoveryEvents } from '../protocol/MulticastDiscovery';

export interface IncomingRequestInfo {
  id: string;
  alias: string;
  ip: string;
  fileCount: number;
  totalSize: number;
}

interface PendingDecision {
  id: string;
  resolve: (accept: boolean) => void;
}

/**
 * Facade wiring discovery, receiver, sender and UI state together.
 *
 * It implements both callback interfaces directly: ArkTS requires an explicit
 * class rather than an object literal when an interface exposes method types.
 * The UI polls lightweight state via listDevices/listRecords/drainIncoming.
 */
export class LocalSendService implements ServerEvents, DiscoveryEvents {
  private static instance: LocalSendService | null = null;

  settings: AppSettings = new AppSettings();
  statusMessage: string = '正在启动…';
  private lastError: string = '';
  private devices: Map<string, NearbyDevice> = new Map<string, NearbyDevice>();
  private records: TransferRecord[] = [];
  private pending: Map<string, PendingDecision> = new Map<string, PendingDecision>();
  private incomingQueue: IncomingRequestInfo[] = [];
  private fileCache: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  private server: LocalSendServer | null = null;
  private discovery: MulticastDiscovery | null = null;
  private cleanupTimer: number = -1;
  private started: boolean = false;

  static shared(): LocalSendService {
    if (LocalSendService.instance === null) {
      LocalSendService.instance = new LocalSendService();
    }
    return LocalSendService.instance as LocalSendService;
  }

  async start(): Promise<void> {
    if (this.started) {
      return;
    }
    this.settings = await SettingsStore.load(AppContext.get());
    this.server = new LocalSendServer(this.settings, this);
    await this.server.start();
    this.discovery = new MulticastDiscovery();
    await this.discovery.start(this.selfInfo(true), this);
    this.cleanupTimer = setInterval(() => {
      this.cleanupDevices();
    }, 10000);
    this.started = true;
    this.statusMessage = '已启动 · 端口 ' + this.settings.port.toString() + ' · HTTP 模式';
  }

  async stop(): Promise<void> {
    if (this.cleanupTimer >= 0) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = -1;
    }
    if (this.discovery !== null) {
      await this.discovery.stop();
      this.discovery = null;
    }
    if (this.server !== null) {
      await this.server.stop();
      this.server = null;
    }
    this.fileCache.clear();
    this.pending.clear();
    this.started = false;
  }

  // ----- ServerEvents -----

  onRegister(info: DeviceInfo, ip: string, port: number): void {
    this.addDevice(info, ip, port);
  }

  onIncomingRequest(info: DeviceInfo, files: FileDto[], ip: string): Promise<boolean> {
    return this.askIncoming(info, files, ip);
  }

  onFileReceived(name: string, size: number, ip: string, path: string): void {
    this.addRecord(this.newRecord(name, size, ip, TransferDirection.RECEIVE,
      TransferStatus.DONE, path));
  }

  onCancel(sessionId: string, ip: string): void {
    this.statusMessage = '会话已取消: ' + sessionId.substring(0, 8);
  }

  onError(message: string): void {
    this.lastError = message;
  }

  // ----- DiscoveryEvents -----

  onAnnounce(info: DeviceInfo, ip: string, shouldReply: boolean): void {
    let port: number = info.port === undefined ? LsConstants.DEFAULT_PORT : info.port;
    this.addDevice(info, ip, port);
    if (!shouldReply) {
      return;
    }
    // UDP is announce-only: the answer is a unicast HTTP /register request.
    let target: NearbyDevice = {
      ip: ip,
      port: port,
      protocol: info.protocol === undefined ? 'http' : info.protocol,
      info: info,
      lastSeen: Date.now()
    };
    LocalSendClient.register(target, this.selfInfo(false)).then((remote: DeviceInfo | null) => {
      if (remote !== null) {
        this.addDevice(remote, ip, port);
      }
    }).catch(() => {
      LsLogger.warn('unicast register reply failed for ' + ip);
    });
  }

  // ----- UI-facing helpers -----

  isStarted(): boolean {
    return this.started;
  }

  consumeError(): string {
    let message: string = this.lastError;
    this.lastError = '';
    return message;
  }

  drainIncoming(): IncomingRequestInfo | null {
    if (this.incomingQueue.length === 0) {
      return null;
    }
    let first: IncomingRequestInfo | undefined = this.incomingQueue.shift();
    return first === undefined ? null : first;
  }

  selfInfo(announce: boolean): DeviceInfo {
    return makeDeviceInfo(this.settings.alias, this.settings.fingerprint,
      this.settings.port, announce, this.settings.webSend);
  }

  listDevices(): NearbyDevice[] {
    let list: NearbyDevice[] = [];
    this.devices.forEach((device: NearbyDevice) => {
      list.push(device);
    });
    list.sort((a: NearbyDevice, b: NearbyDevice) => {
      return a.info.alias.localeCompare(b.info.alias);
    });
    return list;
  }

  listRecords(): TransferRecord[] {
    return this.records.slice();
  }

  async refresh(): Promise<void> {
    if (this.discovery !== null) {
      await this.discovery.announce();
      this.statusMessage = '已发送多播公告';
    }
  }

  async localIp(): Promise<string> {
    try {
      let net = await connection.getDefaultNet();
      let props = await connection.getConnectionProperties(net);
      for (let i = 0; i < props.linkAddresses.length; i++) {
        let address: string = props.linkAddresses[i].address.address;
        if (address.indexOf(':') < 0 && address !== '127.0.0.1' && address.length > 0) {
          return address;
        }
      }
    } catch (e) {
      LsLogger.warn('failed to resolve local IPv4 address');
    }
    return '127.0.0.1';
  }

  async pickFiles(): Promise<SelectedFile[]> {
    let context: common.UIAbilityContext = AppContext.get();
    let view = new picker.DocumentViewPicker(context);
    let options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 10;
    let uris: string[] = await view.select(options);
    let result: SelectedFile[] = [];
    for (let i = 0; i < uris.length; i++) {
      let uri: string = uris[i];
      let data = await FileUtil.readAllFromUri(uri);
      let name: string = FileUtil.fileNameFromUri(uri);
      this.fileCache.set(uri, data);
      let item: SelectedFile = {
        id: ByteUtil.randomId(),
        fileName: name,
        size: data.length,
        fileType: FileUtil.mimeOf(name),
        uri: uri
      };
      result.push(item);
    }
    return result;
  }

  async sendFiles(device: NearbyDevice, files: SelectedFile[], pin: string): Promise<void> {
    let dtos: FileDto[] = [];
    let bodies: Map<string, Uint8Array> = new Map<string, Uint8Array>();
    let totalSize: number = 0;
    for (let i = 0; i < files.length; i++) {
      let file: SelectedFile = files[i];
      let data: Uint8Array | undefined = this.fileCache.get(file.uri);
      if (data === undefined) {
        data = await FileUtil.readAllFromUri(file.uri);
      }
      let sha: string = await ByteUtil.sha256Hex(data);
      let dto: FileDto = {
        id: file.id,
        fileName: file.fileName,
        size: data.length,
        fileType: file.fileType,
        sha256: sha
      };
      dtos.push(dto);
      bodies.set(file.id, data);
      totalSize += data.length;
    }
    let record: TransferRecord = this.newRecord(files.length.toString() + ' 个文件', totalSize,
      device.info.alias, TransferDirection.SEND, TransferStatus.RUNNING, '');
    this.addRecord(record);

    let sessionId: string = '';
    try {
      await LocalSendClient.register(device, this.selfInfo(false));
      let response = await LocalSendClient.prepareUpload(device, this.selfInfo(false), dtos, pin);
      sessionId = response.sessionId;
      for (let i = 0; i < response.tokens.length; i++) {
        let entry = response.tokens[i];
        let body: Uint8Array | undefined = bodies.get(entry.id);
        if (body === undefined) {
          throw new Error('missing file body for ' + entry.id);
        }
        await LocalSendClient.upload(device, sessionId, entry.id, entry.token, body);
      }
      record.status = TransferStatus.DONE;
      record.detail = '发送完成';
      this.records = this.records.slice();
      this.statusMessage = '发送完成';
    } catch (e) {
      if (sessionId.length > 0) {
        await LocalSendClient.cancel(device, sessionId);
      }
      record.status = TransferStatus.FAILED;
      record.detail = e instanceof LsHttpError ? 'HTTP ' + e.status.toString() : '发送失败';
      this.records = this.records.slice();
      this.lastError = record.detail;
    }
  }

  async shareViaLink(files: SelectedFile[]): Promise<string> {
    if (this.server === null) {
      throw new Error('receiver is not running');
    }
    let shared: SharedFile[] = [];
    for (let i = 0; i < files.length; i++) {
      let file: SelectedFile = files[i];
      let data: Uint8Array | undefined = this.fileCache.get(file.uri);
      if (data === undefined) {
        data = await FileUtil.readAllFromUri(file.uri);
      }
      let dto: FileDto = {
        id: file.id,
        fileName: file.fileName,
        size: data.length,
        fileType: file.fileType,
        sha256: await ByteUtil.sha256Hex(data)
      };
      let item: SharedFile = { dto: dto, data: data };
      shared.push(item);
    }
    this.server.setWebShare(shared);
    let ip: string = await this.localIp();
    return 'http://' + ip + ':' + this.settings.port.toString() + '/';
  }

  respondToIncoming(id: string, accept: boolean): void {
    let decision: PendingDecision | undefined = this.pending.get(id);
    if (decision === undefined) {
      return;
    }
    this.pending.delete(id);
    decision.resolve(accept);
  }

  async updateSettings(settings: AppSettings): Promise<void> {
    this.settings = settings;
    await SettingsStore.save(AppContext.get(), settings);
  }

  // ----- internals -----

  private askIncoming(info: DeviceInfo, files: FileDto[], ip: string): Promise<boolean> {
    let total: number = 0;
    for (let i = 0; i < files.length; i++) {
      total += files[i].size;
    }
    if (this.settings.autoAccept) {
      let resolved: Promise<boolean> = new Promise<boolean>((resolve: (v: boolean) => void) => {
        resolve(true);
      });
      return resolved;
    }
    return new Promise<boolean>((resolve: (accept: boolean) => void) => {
      let id: string = ByteUtil.randomId();
      let decision: PendingDecision = { id: id, resolve: resolve };
      this.pending.set(id, decision);
      let view: IncomingRequestInfo = {
        id: id,
        alias: info.alias,
        ip: ip,
        fileCount: files.length,
        totalSize: total
      };
      this.incomingQueue.push(view);
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          resolve(false);
        }
      }, 30000);
    });
  }

  private addDevice(info: DeviceInfo, ip: string, port: number): void {
    if (info.fingerprint === this.settings.fingerprint) {
      return;
    }
    let protocol: string = info.protocol === undefined ? 'http' : info.protocol;
    let device: NearbyDevice = {
      ip: ip,
      port: port,
      protocol: protocol,
      info: info,
      lastSeen: Date.now()
    };
    this.devices.set(info.fingerprint + '@' + ip, device);
  }

  private cleanupDevices(): void {
    let now: number = Date.now();
    let expired: string[] = [];
    this.devices.forEach((device: NearbyDevice, key: string) => {
      if (now - device.lastSeen > LsConstants.DEVICE_TIMEOUT_MS) {
        expired.push(key);
      }
    });
    for (let i = 0; i < expired.length; i++) {
      this.devices.delete(expired[i]);
    }
  }

  private newRecord(name: string, size: number, peer: string, direction: TransferDirection,
    status: TransferStatus, detail: string): TransferRecord {
    let record: TransferRecord = {
      id: ByteUtil.randomId(),
      fileName: name,
      size: size,
      peer: peer,
      direction: direction,
      status: status,
      timestamp: Date.now(),
      detail: detail
    };
    return record;
  }

  private addRecord(record: TransferRecord): void {
    this.records.unshift(record);
    if (this.records.length > 100) {
      this.records = this.records.slice(0, 100);
    }
  }
}
