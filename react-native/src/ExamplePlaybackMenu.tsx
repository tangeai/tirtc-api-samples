import React, {useCallback, useEffect, useRef, useState} from 'react';
import {
  Modal,
  AccessibilityInfo,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
  findNodeHandle,
} from 'react-native';
import {automationTestId, exampleTheme} from './ExampleUi';

export type PlaybackMenuAction = Readonly<{
  label: string;
  accessibilityLabel: string;
  disabled?: boolean;
  onPress: () => void;
}>;

export function PlaybackActionMenu({
  accessibilityLabel,
  actions,
  triggerRef,
}: {
  accessibilityLabel: string;
  actions: readonly PlaybackMenuAction[];
  triggerRef?: React.MutableRefObject<View | null>;
}) {
  const [visible, setVisible] = useState(false);
  const trigger = useRef<View>(null);
  const visibleRef = useRef(false);
  const restoreAfterDismissRef = useRef(false);
  const androidRestoreTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (visible && actions.every((action) => action.disabled)) setVisible(false);
  }, [actions, visible]);

  const restoreTriggerFocus = useCallback(() => {
    const handle = findNodeHandle(trigger.current);
    if (handle !== null) {
      if (Platform.OS === 'android') {
        trigger.current?.setNativeProps({hasTVPreferredFocus: true});
        requestAnimationFrame(() => trigger.current?.setNativeProps({hasTVPreferredFocus: false}));
      } else {
        trigger.current?.focus?.();
      }
      AccessibilityInfo.setAccessibilityFocus(handle);
      return true;
    }
    return false;
  }, []);

  const consumePendingFocusRestore = useCallback(() => {
    if (!restoreAfterDismissRef.current || visibleRef.current) return;
    if (restoreTriggerFocus()) restoreAfterDismissRef.current = false;
  }, [restoreTriggerFocus]);

  const setTrigger = useCallback((node: View | null) => {
    trigger.current = node;
    if (triggerRef) triggerRef.current = node;
  }, [triggerRef]);

  const open = () => {
    if (androidRestoreTimerRef.current !== null) clearTimeout(androidRestoreTimerRef.current);
    androidRestoreTimerRef.current = null;
    restoreAfterDismissRef.current = false;
    visibleRef.current = true;
    setVisible(true);
  };

  const close = (restoreFocus: boolean) => {
    visibleRef.current = false;
    restoreAfterDismissRef.current = restoreFocus;
    setVisible(false);
    if (Platform.OS === 'android' && restoreFocus) {
      if (androidRestoreTimerRef.current !== null) clearTimeout(androidRestoreTimerRef.current);
      androidRestoreTimerRef.current = setTimeout(() => {
        androidRestoreTimerRef.current = null;
        consumePendingFocusRestore();
      }, 100);
    }
  };

  useEffect(() => () => {
    if (androidRestoreTimerRef.current !== null) clearTimeout(androidRestoreTimerRef.current);
  }, []);

  return <>
    <Pressable
      ref={setTrigger}
      accessible
      focusable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityHint="打开更多播放操作"
      testID={automationTestId(accessibilityLabel)}
      onPress={open}
      style={({pressed}) => [styles.trigger, Platform.OS === 'ios' ? styles.appleTrigger : styles.materialTrigger, pressed && styles.pressed]}>
      <Text style={styles.triggerText}>•••</Text>
    </Pressable>
    <Modal transparent visible={visible} animationType="fade" onRequestClose={() => close(true)} onDismiss={consumePendingFocusRestore}>
      <View style={styles.backdrop}>
        <Pressable
          accessible
          accessibilityRole="button"
          accessibilityLabel={`${accessibilityLabel} Cancel`}
          testID={automationTestId(`${accessibilityLabel} Cancel`)}
          style={styles.dismissScrim}
          onPress={() => close(true)}
        />
        <View style={[styles.menu, Platform.OS === 'ios' ? styles.appleMenu : styles.materialMenu]}>
          {actions.map((action) => (
            <Pressable
              key={action.accessibilityLabel}
              accessible
              accessibilityRole="menuitem"
              accessibilityLabel={action.accessibilityLabel}
              accessibilityState={{disabled: action.disabled}}
              testID={automationTestId(action.accessibilityLabel)}
              disabled={action.disabled}
              onPress={() => {
                close(false);
                action.onPress();
              }}
              style={({pressed}) => [styles.item, action.disabled && styles.disabled, pressed && styles.pressed]}>
              <Text style={styles.itemText}>{action.label}</Text>
            </Pressable>
          ))}
        </View>
      </View>
    </Modal>
  </>;
}

const styles = StyleSheet.create({
  trigger: {width: Platform.OS === 'ios' ? 44 : 48, height: Platform.OS === 'ios' ? 44 : 48, alignItems: 'center', justifyContent: 'center'},
  materialTrigger: {borderRadius: 24, backgroundColor: 'rgba(37,37,37,0.88)'},
  appleTrigger: {borderRadius: 12, backgroundColor: 'rgba(37,37,37,0.72)'},
  triggerText: {color: '#FFFFFF', fontSize: 18, fontWeight: '800', letterSpacing: 1},
  backdrop: {flex: 1, justifyContent: 'flex-end', alignItems: 'center', backgroundColor: 'rgba(0,0,0,0.26)', padding: 16},
  dismissScrim: {position: 'absolute', left: 0, right: 0, top: 0, bottom: 0},
  menu: {width: '100%', maxWidth: 420, padding: 8, backgroundColor: exampleTheme.background},
  materialMenu: {borderRadius: 24, elevation: 12},
  appleMenu: {borderRadius: 14, shadowColor: '#000', shadowOpacity: 0.22, shadowRadius: 18, shadowOffset: {width: 0, height: 8}},
  item: {minHeight: Platform.OS === 'ios' ? 44 : 48, borderRadius: 12, paddingHorizontal: 16, justifyContent: 'center'},
  itemText: {color: exampleTheme.textPrimary, fontSize: 15, fontWeight: '600'},
  disabled: {opacity: 0.42},
  pressed: {opacity: 0.7},
});
