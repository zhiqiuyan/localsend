import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContext } from '../common/AppContext';
import { LocalSendService } from '../service/LocalSendService';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppContext.set(this.context);
    hilog.info(0x5A31, 'LocalSendOH', '%{public}s', 'EntryAbility.onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code !== 0) {
        hilog.error(0x5A31, 'LocalSendOH', '%{public}s', 'loadContent failed: ' + err.message);
      }
    });
  }

  onWindowStageDestroy(): void {
    // The receiver is stopped together with the page lifecycle.
  }

  onForeground(): void {
    hilog.info(0x5A31, 'LocalSendOH', '%{public}s', 'EntryAbility.onForeground');
  }

  onBackground(): void {
    hilog.info(0x5A31, 'LocalSendOH', '%{public}s', 'EntryAbility.onBackground');
  }

  onDestroy(): void {
    LocalSendService.shared().stop();
  }
}
