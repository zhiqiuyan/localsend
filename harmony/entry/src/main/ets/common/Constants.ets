/**
 * Constants mirrored from LocalSend Protocol v2.2.
 * Reference: https://github.com/localsend/protocol (v2.2)
 * Upstream implementation: packages/localsend_isolates/lib/constants.dart
 */
export class LsConstants {
  static readonly PROTOCOL_VERSION: string = '2.2';
  static readonly DEFAULT_PORT: number = 53317;
  static readonly MULTICAST_GROUP: string = '224.0.0.167';
  static readonly BASE_PATH: string = '/api/localsend/v2';
  static readonly DEVICE_TYPE: string = 'mobile';
  static readonly DEVICE_MODEL: string = 'HarmonyOS';
  static readonly PROTOCOL: string = 'http';
  static readonly ANNOUNCE_INTERVAL_MS: number = 5000;
  static readonly DEVICE_TIMEOUT_MS: number = 30000;
  static readonly HTTP_CHUNK: number = 64 * 1024;
  /** The MVP buffers a whole upload in memory; oversized payloads are rejected with 413. */
  static readonly MAX_UPLOAD_BYTES: number = 64 * 1024 * 1024;
  static readonly HTTP_CONNECT_TIMEOUT_MS: number = 5000;
  static readonly HTTP_READ_TIMEOUT_MS: number = 60000;
}
