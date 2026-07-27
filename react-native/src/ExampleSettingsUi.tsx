import React from 'react';
import {
  Modal,
  Pressable,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';
import {exampleTheme} from './ExampleUi';
import type {PreferenceOption} from './ExampleSettingsOptions';

export type PreferenceSheetState = Readonly<{
  title: string;
  currentValue: string;
  options: readonly PreferenceOption[];
  onSelect: (value: string) => void;
}>;

export function SettingsSection({title, children}: {title: string; children: React.ReactNode}) {
  return (
    <View>
      <Text style={styles.sectionTitle}>{title}</Text>
      <View style={styles.surface}>{children}</View>
    </View>
  );
}

export function SettingsRow({
  title,
  value,
  accessibilityLabel,
  onPress,
  disabled,
}: {
  title: string;
  value: string;
  accessibilityLabel: string;
  onPress: () => void;
  disabled?: boolean;
}) {
  return (
    <Pressable
      accessible
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      testID={automationTestId(accessibilityLabel)}
      disabled={disabled}
      onPress={onPress}
      style={[styles.row, disabled ? styles.rowDisabled : null]}>
      <View style={styles.rowText}>
        <Text style={[styles.rowTitle, disabled ? styles.disabledText : null]}>{title}</Text>
        <Text style={[styles.rowValue, disabled ? styles.disabledText : null]}>{value}</Text>
      </View>
      <Text style={[styles.chevron, disabled ? styles.disabledText : null]}>›</Text>
    </Pressable>
  );
}

export function SettingsSwitchRow({
  title,
  value,
  accessibilityLabel,
  onValueChange,
}: {
  title: string;
  value: boolean;
  accessibilityLabel: string;
  onValueChange: (value: boolean) => void;
}) {
  return (
    <View
      accessible
      accessibilityLabel={accessibilityLabel}
      testID={automationTestId(accessibilityLabel)}
      style={styles.switchRow}>
      <Text style={styles.rowTitle}>{title}</Text>
      <Switch
        value={value}
        onValueChange={onValueChange}
        trackColor={{false: '#D8D1C5', true: 'rgba(101,146,135,0.45)'}}
        thumbColor={value ? exampleTheme.primary : exampleTheme.surface}
      />
    </View>
  );
}

export function SettingsDivider() {
  return <View style={styles.divider} />;
}

export function PreferenceSheet({
  state,
  onClose,
}: {
  state: PreferenceSheetState | null;
  onClose: () => void;
}) {
  if (state === null) {
    return null;
  }
  return (
    <Modal
      visible
      transparent
      animationType="slide"
      onRequestClose={onClose}>
      <Pressable style={styles.modalBackdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={(event) => event.stopPropagation()}>
          <Text style={styles.sheetTitle}>{state.title}</Text>
          {state.options.map((option) => (
            <Pressable
              key={option.value}
              accessibilityRole="button"
              accessibilityLabel={`TiRTC Settings Option ${option.label}`}
              testID={automationTestId(`TiRTC Settings Option ${option.label}`)}
              onPress={() => {
                state.onSelect(option.value);
                onClose();
              }}
              style={styles.optionRow}>
              <Text style={styles.optionMark}>{option.value === state.currentValue ? '●' : '○'}</Text>
              <Text style={styles.optionText}>{option.label}</Text>
            </Pressable>
          ))}
        </Pressable>
      </Pressable>
    </Modal>
  );
}

export function StreamIdDialog({
  visible,
  value,
  placeholder,
  onChangeText,
  onCancel,
  onSave,
}: {
  visible: boolean;
  value: string;
  placeholder: string;
  onChangeText: (value: string) => void;
  onCancel: () => void;
  onSave: () => void;
}) {
  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onCancel}>
      <View style={styles.modalBackdrop}>
        <View style={styles.dialog}>
          <Text style={styles.sheetTitle}>传输 Stream ID</Text>
          <TextInput
            accessibilityLabel="TiRTC Settings Local Audio Stream ID Input"
            testID={automationTestId('TiRTC Settings Local Audio Stream ID Input')}
            value={value}
            onChangeText={onChangeText}
            placeholder={placeholder}
            placeholderTextColor={exampleTheme.textSecondary}
            keyboardType="number-pad"
            style={styles.dialogInput}
          />
          <View style={styles.dialogActions}>
            <Pressable style={styles.dialogButton} onPress={onCancel}>
              <Text style={styles.dialogButtonText}>取消</Text>
            </Pressable>
            <Pressable style={[styles.dialogButton, styles.dialogPrimaryButton]} onPress={onSave}>
              <Text style={[styles.dialogButtonText, styles.dialogPrimaryButtonText]}>保存</Text>
            </Pressable>
          </View>
        </View>
      </View>
    </Modal>
  );
}

function automationTestId(label: string): string {
  return label.replace(/[^A-Za-z0-9_]+/g, '_').replace(/^_+|_+$/g, '');
}

const styles = StyleSheet.create({
  sectionTitle: {
    color: exampleTheme.primary,
    fontSize: 14,
    fontWeight: '700',
    marginBottom: 8,
    marginLeft: 4,
    marginTop: 4,
  },
  surface: {
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.88)',
    overflow: 'hidden',
  },
  row: {
    minHeight: 62,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  rowDisabled: {
    opacity: 0.58,
  },
  rowText: {
    flex: 1,
    minWidth: 0,
    gap: 3,
  },
  rowTitle: {
    color: exampleTheme.textPrimary,
    fontSize: 15,
    fontWeight: '500',
  },
  rowValue: {
    color: exampleTheme.textSecondary,
    fontSize: 13,
  },
  disabledText: {
    color: exampleTheme.textHint,
  },
  chevron: {
    color: exampleTheme.textSecondary,
    fontSize: 26,
    fontWeight: '300',
    marginLeft: 12,
  },
  switchRow: {
    minHeight: 62,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  divider: {
    height: 1,
    marginLeft: 16,
    marginRight: 16,
    backgroundColor: exampleTheme.inputBorder,
  },
  modalBackdrop: {
    flex: 1,
    justifyContent: 'flex-end',
    backgroundColor: 'rgba(0,0,0,0.22)',
  },
  sheet: {
    borderTopLeftRadius: 22,
    borderTopRightRadius: 22,
    backgroundColor: exampleTheme.background,
    paddingHorizontal: 20,
    paddingTop: 16,
    paddingBottom: 24,
  },
  sheetTitle: {
    color: exampleTheme.textPrimary,
    fontSize: 17,
    fontWeight: '700',
    marginBottom: 10,
  },
  optionRow: {
    minHeight: 52,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
  },
  optionMark: {
    width: 30,
    color: exampleTheme.primary,
    fontSize: 18,
  },
  optionText: {
    color: exampleTheme.textPrimary,
    fontSize: 15,
  },
  dialog: {
    marginHorizontal: 24,
    marginBottom: 120,
    borderRadius: 18,
    backgroundColor: exampleTheme.background,
    padding: 18,
  },
  dialogInput: {
    minHeight: 48,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: exampleTheme.inputBorder,
    backgroundColor: exampleTheme.surface,
    color: exampleTheme.textPrimary,
    fontSize: 15,
    paddingHorizontal: 12,
  },
  dialogActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: 10,
    marginTop: 16,
  },
  dialogButton: {
    minHeight: 40,
    borderRadius: 18,
    paddingHorizontal: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dialogPrimaryButton: {
    backgroundColor: exampleTheme.primary,
  },
  dialogButtonText: {
    color: exampleTheme.primary,
    fontSize: 14,
    fontWeight: '600',
  },
  dialogPrimaryButtonText: {
    color: exampleTheme.foreground,
  },
});
