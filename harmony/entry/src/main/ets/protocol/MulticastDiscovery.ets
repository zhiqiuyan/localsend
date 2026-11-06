import { socket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DeviceInfo } from '../common/Models';
import { LsConstants } from '../common/Constants';
import { ByteUtil } from '../util/ByteUtil';
import { LsLogger } from '../common/Logger';

export interface DiscoveryEvents {
  /** shouldReply is true for announcements (announce=true); the receiver must answer over HTTP /register. */
  onAnnounce(info: DeviceInfo, sourceIp: string, shouldReply: boolean): void;
  onError(message: string): void;
}

/**
 * UDP multicast discovery for LocalSend Protocol v2.2.
 * Upstream (packages/core/src/multicast) is announce-only: responses are
 * unicast HTTP /register requests, never multicast replies.
 */
export class MulticastDiscovery {
  private sock: socket.MulticastSocket | null = null;
  private timer: number = -1;
  private info: DeviceInfo | null = null;
  private events: DiscoveryEvents | null = null;

  async start(info: DeviceInfo, events: DiscoveryEvents): Promise<void> {
    this.info = info;
    this.events = events;
    let s = socket.constructMulticastSocketInstance();
    await s.bind({ address: '0.0.0.0', port: LsConstants.DEFAULT_PORT });
    await s.addMembership({ address: LsConstants.MULTICAST_GROUP, port: LsConstants.DEFAULT_PORT });
    try {
      await s.setMulticastTTL(2);
    } catch (e) {
      // TTL is best-effort; some devices reject it before the membership is fully active.
    }
    s.on('message', (data: socket.SocketMessageInfo) => {
      this.onMessage(data);
    });
    s.on('error', (err: BusinessError) => {
      if (this.events !== null) {
        this.events.onError('multicast error ' + err.code.toString() + ': ' + err.message);
      }
    });
    this.sock = s;
    await this.announce();
    this.timer = setInterval(() => {
      this.announce();
    }, LsConstants.ANNOUNCE_INTERVAL_MS);
  }

  async announce(): Promise<void> {
    if (this.sock === null || this.info === null) {
      return;
    }
    let payload: string = JSON.stringify(this.info);
    try {
      await this.sock.send({
        data: payload,
        address: { address: LsConstants.MULTICAST_GROUP, port: LsConstants.DEFAULT_PORT }
      });
    } catch (e) {
      LsLogger.warn('announce failed');
    }
  }

  private onMessage(data: socket.SocketMessageInfo): void {
    let text: string;
    let info: DeviceInfo;
    try {
      text = ByteUtil.decode(new Uint8Array(data.message));
      info = JSON.parse(text) as DeviceInfo;
    } catch (e) {
      LsLogger.warn('ignoring malformed multicast announcement');
      return;
    }
    if (info.fingerprint === undefined || info.version === undefined) {
      return;
    }
    // v1 messages are deliberately not parsed (upstream behaviour).
    if (!info.version.startsWith('2')) {
      return;
    }
    if (this.info !== null && info.fingerprint === this.info.fingerprint) {
      return;
    }
    if (this.events === null) {
      return;
    }
    let shouldReply: boolean = info.announce === true;
    this.events.onAnnounce(info, data.remoteInfo.address, shouldReply);
  }

  async stop(): Promise<void> {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    if (this.sock !== null) {
      try {
        await this.sock.close();
      } catch (e) {
        LsLogger.warn('multicast close failed');
      }
      this.sock = null;
    }
    this.info = null;
    this.events = null;
  }
}
