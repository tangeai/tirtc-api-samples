import abilityAccessCtrl, { Context, Permissions, PermissionRequestResult } from '@ohos.abilityAccessCtrl';

const MICROPHONE_PERMISSIONS: Permissions[] = [
  'ohos.permission.MICROPHONE',
];

export async function requestMicrophonePermission(context: Context): Promise<boolean> {
  try {
    const result: PermissionRequestResult =
      await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, MICROPHONE_PERMISSIONS);
    return result.authResults.length === MICROPHONE_PERMISSIONS.length &&
      result.authResults.every((status: number): boolean =>
        status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
  } catch (_) {
    return false;
  }
}
