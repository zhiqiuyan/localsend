import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ByteUtil } from '../util/ByteUtil';
import { LsConstants } from './Constants';

const STORE_NAME: string = 'localsend_settings';

export class AppSettings {
  alias: string = 'Harmony Device';
  port: number = LsConstants.DEFAULT_PORT;
  autoAccept: boolean = true;
  pin: string = '';
  fingerprint: string = '';
  /** Reverse (link sharing) HTTP server, unencrypted by protocol design. */
  webSend: boolean = false;
}

export class SettingsStore {
  static async load(context: common.Context): Promise<AppSettings> {
    let prefs = await preferences.getPreferences(context, STORE_NAME);
    let s = new AppSettings();
    s.alias = await prefs.get('alias', s.alias) as string;
    s.port = await prefs.get('port', s.port) as number;
    s.autoAccept = await prefs.get('autoAccept', s.autoAccept) as boolean;
    s.pin = await prefs.get('pin', s.pin) as string;
    s.fingerprint = await prefs.get('fingerprint', s.fingerprint) as string;
    s.webSend = await prefs.get('webSend', s.webSend) as boolean;
    if (s.fingerprint.length === 0) {
      // Encryption is off in HTTP mode, so the protocol uses a random persistent string.
      s.fingerprint = ByteUtil.randomId();
      await SettingsStore.save(context, s);
    }
    return s;
  }

  static async save(context: common.Context, s: AppSettings): Promise<void> {
    let prefs = await preferences.getPreferences(context, STORE_NAME);
    await prefs.put('alias', s.alias);
    await prefs.put('port', s.port);
    await prefs.put('autoAccept', s.autoAccept);
    await prefs.put('pin', s.pin);
    await prefs.put('fingerprint', s.fingerprint);
    await prefs.put('webSend', s.webSend);
    await prefs.flush();
  }
}
