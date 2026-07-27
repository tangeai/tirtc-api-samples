import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const LOG_DOMAIN: number = 0x5452;
const LOG_TAG: string = 'TIRTC_OHOS_EXAMPLE';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'ability_create want_action=%{public}s launch_reason=%{public}d',
      want.action ?? '',
      launchParam.launchReason);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.configureWindow(windowStage);
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(LOG_DOMAIN, LOG_TAG, 'load_content_failed code=%{public}d message=%{public}s',
          err.code, err.message);
        return;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG, 'load_content_done');
    });
  }

  private configureWindow(windowStage: window.WindowStage): void {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true)
        .then(() => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'window_layout_full_screen_done');
        })
        .catch((error: Error) => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'window_layout_full_screen_failed message=%{public}s',
            error.message);
        });
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#000000',
        navigationBarContentColor: '#000000',
      })
        .then(() => {
          hilog.info(LOG_DOMAIN, LOG_TAG, 'window_system_bar_properties_done');
        })
        .catch((error: Error) => {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'window_system_bar_properties_failed message=%{public}s',
            error.message);
        });
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'window_config_failed message=%{public}s',
        error instanceof Error ? error.message : String(error));
    }
  }

}
