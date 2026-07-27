import abilityAccessCtrl, { Context, Permissions, PermissionRequestResult } from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import dataPreferences from '@ohos.data.preferences';
import {
  FlutterAbility,
  FlutterAbilityLaunchConfigs,
  FlutterEngine,
  FlutterShellArgs,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

const PERMISSIONS_CHANNEL_NAME = 'tirtc_example/permissions';
const PREFERENCES_CHANNEL_NAME = 'tirtc_example/preferences';
const PREFERENCES_NAME = 'tirtc_example_preferences';

class ExamplePermissionsHandler implements MethodCallHandler {
  private readonly context: Context;

  public constructor(context: Context) {
    this.context = context;
  }

  public onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'checkMicrophonePermission':
        this.checkPermission('ohos.permission.MICROPHONE', result);
        return;
      case 'requestMicrophonePermission':
        this.requestPermission('ohos.permission.MICROPHONE', result);
        return;
      case 'requestLocalNetworkPermission':
        result.success(true);
        return;
      default:
        result.notImplemented();
        return;
    }
  }

  private checkPermission(permission: Permissions, result: MethodResult): void {
    this.permissionGranted(permission)
      .then((granted: boolean): void => {
        result.success(granted);
      })
      .catch((error: Error): void => {
        result.error('permission_check_failed', error.message ?? '', null);
      });
  }

  private requestPermission(permission: Permissions, result: MethodResult): void {
    abilityAccessCtrl.createAtManager()
      .requestPermissionsFromUser(this.context, [permission])
      .then((permissionResult: PermissionRequestResult): void => {
        const granted = permissionResult.authResults.length === 1 &&
          permissionResult.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
        result.success(granted);
      })
      .catch((error: Error): void => {
        result.error('permission_request_failed', error.message ?? '', null);
      });
  }

  private async permissionGranted(permission: Permissions): Promise<boolean> {
    const bundleInfo = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
    );
    const tokenId = bundleInfo.appInfo.accessTokenId;
    const atManager = abilityAccessCtrl.createAtManager();
    const status = await atManager.checkAccessToken(tokenId, permission);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }
}

class ExamplePreferencesHandler implements MethodCallHandler {
  private readonly context: Context;
  private preferences?: dataPreferences.Preferences;

  public constructor(context: Context) {
    this.context = context;
  }

  public onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'putPreferencesInt':
        this.putInt(call, result);
        return;
      case 'getPreferencesInt':
        this.getInt(call, result);
        return;
      case 'putPreferencesString':
        this.putString(call, result);
        return;
      case 'getPreferencesString':
        this.getString(call, result);
        return;
      default:
        result.notImplemented();
        return;
    }
  }

  private putInt(call: MethodCall, result: MethodResult): void {
    const key: string = call.argument('key');
    const value: number = call.argument('value');
    if (key === null || value === null) {
      result.error('preferences_invalid_argument', 'key and value are required', null);
      return;
    }
    this.resolvePreferences()
      .then((preferences: dataPreferences.Preferences): Promise<void> => {
        preferences.put(key, value);
        return preferences.flush();
      })
      .then((): void => {
        result.success(null);
      })
      .catch((error: Error): void => {
        result.error('preferences_write_failed', error.message ?? '', null);
      });
  }

  private getInt(call: MethodCall, result: MethodResult): void {
    const key: string = call.argument('key');
    const defaultValue: number = call.argument('defaultValue');
    if (key === null || defaultValue === null) {
      result.error('preferences_invalid_argument', 'key and defaultValue are required', null);
      return;
    }
    this.resolvePreferences()
      .then((preferences: dataPreferences.Preferences): void => {
        result.success(preferences.getSync(key, defaultValue));
      })
      .catch((error: Error): void => {
        result.error('preferences_read_failed', error.message ?? '', null);
      });
  }

  private putString(call: MethodCall, result: MethodResult): void {
    const key: string = call.argument('key');
    const value: string = call.argument('value');
    if (key === null || value === null) {
      result.error('preferences_invalid_argument', 'key and value are required', null);
      return;
    }
    this.resolvePreferences()
      .then((preferences: dataPreferences.Preferences): Promise<void> => {
        preferences.put(key, value);
        return preferences.flush();
      })
      .then((): void => {
        result.success(null);
      })
      .catch((error: Error): void => {
        result.error('preferences_write_failed', error.message ?? '', null);
      });
  }

  private getString(call: MethodCall, result: MethodResult): void {
    const key: string = call.argument('key');
    const defaultValue: string = call.argument('defaultValue');
    if (key === null || defaultValue === null) {
      result.error('preferences_invalid_argument', 'key and defaultValue are required', null);
      return;
    }
    this.resolvePreferences()
      .then((preferences: dataPreferences.Preferences): void => {
        result.success(preferences.getSync(key, defaultValue));
      })
      .catch((error: Error): void => {
        result.error('preferences_read_failed', error.message ?? '', null);
      });
  }

  private async resolvePreferences(): Promise<dataPreferences.Preferences> {
    if (this.preferences !== undefined) {
      return this.preferences;
    }
    this.preferences = await dataPreferences.getPreferences(this.context, PREFERENCES_NAME);
    return this.preferences;
  }
}

export default class EntryAbility extends FlutterAbility {
  private permissionsChannel?: MethodChannel;
  private preferencesChannel?: MethodChannel;

  public configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    this.permissionsChannel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      PERMISSIONS_CHANNEL_NAME,
    );
    this.permissionsChannel.setMethodCallHandler(new ExamplePermissionsHandler(this.context));
    this.preferencesChannel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      PREFERENCES_CHANNEL_NAME,
    );
    this.preferencesChannel.setMethodCallHandler(new ExamplePreferencesHandler(this.context));
  }

  public getDartEntrypointArgs(): Array<string> {
    return new Array<string>();
  }

  public getFlutterShellArgs(): FlutterShellArgs {
    return new FlutterShellArgs();
  }

  public getDartEntrypointFunctionName(): string {
    return FlutterAbilityLaunchConfigs.DEFAULT_DART_ENTRYPOINT;
  }

  public getInitialRoute(): string {
    return '';
  }

  public shouldRestoreAndSaveState(): boolean {
    return true;
  }

  public getCachedEngineId(): string {
    return '';
  }

  public getCachedEngineGroupId(): string | null {
    return null;
  }
}
