const KEYCODE_DPAD_CENTER = 2016;
const KEYCODE_SPACE = 2050;
const KEYCODE_ENTER = 2054;

export function isActivationKey(event: KeyEvent): boolean {
  if (event.type !== KeyType.Up) {
    return false;
  }
  return event.keyCode === KEYCODE_ENTER ||
    event.keyCode === KEYCODE_SPACE ||
    event.keyCode === KEYCODE_DPAD_CENTER;
}

export function runOnActivationKey(event: KeyEvent, action: () => void): boolean {
  if (!isActivationKey(event)) {
    return false;
  }
  action();
  return true;
}
