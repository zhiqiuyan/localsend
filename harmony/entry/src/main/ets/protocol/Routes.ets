import { NearbyDevice } from '../common/Models';
import { LsConstants } from '../common/Constants';

/** Endpoint paths of LocalSend Protocol v2.2 (v1 endpoints are intentionally not served). */
export class LsRoutes {
  static readonly INFO: string = LsConstants.BASE_PATH + '/info';
  static readonly REGISTER: string = LsConstants.BASE_PATH + '/register';
  static readonly PREPARE_UPLOAD: string = LsConstants.BASE_PATH + '/prepare-upload';
  static readonly UPLOAD: string = LsConstants.BASE_PATH + '/upload';
  static readonly CANCEL: string = LsConstants.BASE_PATH + '/cancel';
  static readonly SHOW: string = LsConstants.BASE_PATH + '/show';
  static readonly PREPARE_DOWNLOAD: string = LsConstants.BASE_PATH + '/prepare-download';
  static readonly DOWNLOAD: string = LsConstants.BASE_PATH + '/download';

  static targetUrl(device: NearbyDevice, route: string, query: string): string {
    let scheme: string = device.protocol === 'https' ? 'https' : 'http';
    return scheme + '://' + device.ip + ':' + device.port.toString() + route + query;
  }

  static query(params: Map<string, string>): string {
    if (params.size === 0) {
      return '';
    }
    let first: boolean = true;
    let out: string = '?';
    params.forEach((value: string, key: string) => {
      out += (first ? '' : '&') + encodeURIComponent(key) + '=' + encodeURIComponent(value);
      first = false;
    });
    return out;
  }

  static parseQuery(raw: string): Map<string, string> {
    let result = new Map<string, string>();
    if (raw.length === 0) {
      return result;
    }
    let pairs: string[] = raw.split('&');
    for (let i = 0; i < pairs.length; i++) {
      let eq: number = pairs[i].indexOf('=');
      if (eq < 0) {
        result.set(FileUtilDecode(pairs[i]), '');
      } else {
        result.set(FileUtilDecode(pairs[i].substring(0, eq)), FileUtilDecode(pairs[i].substring(eq + 1)));
      }
    }
    return result;
  }
}

function FileUtilDecode(value: string): string {
  try {
    return decodeURIComponent(value.replace(/\+/g, ' '));
  } catch (e) {
    return value;
  }
}
