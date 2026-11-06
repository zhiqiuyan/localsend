import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x5A31;
const LOG_TAG: string = 'LocalSendOH';

export class LsLogger {
  static info(message: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  static warn(message: string): void {
    hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }

  static error(message: string): void {
    hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', message);
  }
}
