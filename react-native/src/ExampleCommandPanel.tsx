import React, {useMemo, useState} from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from 'react-native';
import {TiRtc} from 'tirtc-react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {automationTestId, exampleTheme} from './ExampleUi';
import {commandPanelStyles as styles} from './ExampleCommandPanelStyles';
import {
  demoCommonCommandPresets,
  formatCommandId,
  formatCommandPayloadHex,
  parseCommandId,
  parseCommandPayload,
  trimCommandEvents,
  type CommandPanelEvent,
  type CommandPayloadMode,
  type CommandPreset,
} from './ExampleCommandPanelModel';

export function CommandPanelSheet({
  visible,
  title,
  connected,
  events,
  onClose,
  onSendCommand,
}: {
  visible: boolean;
  title: string;
  connected: boolean;
  events: readonly CommandPanelEvent[];
  onClose: () => void;
  onSendCommand: (commandId: number, payload: Uint8Array) => Promise<number> | number;
}) {
  const [commandIdText, setCommandIdText] = useState('0x00000000');
  const [payloadText, setPayloadText] = useState('');
  const [payloadMode, setPayloadMode] = useState<CommandPayloadMode>('hex');
  const [inputError, setInputError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const insets = useSafeAreaInsets();
  const panelEvents = useMemo(() => trimCommandEvents(events).reverse(), [events]);

  const applyPreset = (preset: CommandPreset) => {
    if (sending) {
      return;
    }
    setCommandIdText(formatCommandId(preset.commandId));
    setPayloadMode(preset.payloadMode);
    setPayloadText(preset.payloadText);
    setInputError(null);
  };

  const send = async () => {
    const commandId = parseCommandId(commandIdText);
    if (!commandId.valid) {
      setInputError(commandId.error);
      return;
    }
    const payload = parseCommandPayload(payloadText, payloadMode);
    if (!payload.valid) {
      setInputError(payload.error);
      return;
    }
    setInputError(null);
    setSending(true);
    try {
      await onSendCommand(commandId.value, payload.value);
    } finally {
      setSending(false);
    }
  };

  return (
    <Modal visible={visible} transparent animationType="slide" onRequestClose={onClose}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={styles.root}>
        <Pressable
          accessible={false}
          importantForAccessibility="no-hide-descendants"
          style={styles.backdrop}
          onPress={onClose}
        />
        <View style={[styles.sheet, {paddingBottom: insets.bottom}]}>
          <View style={styles.header}>
            <Text style={styles.title}>{title}</Text>
            <Pressable
              accessible
              accessibilityRole="button"
              accessibilityLabel="TiRTC Command Panel Close"
              testID={automationTestId('TiRTC Command Panel Close')}
              onPress={onClose}
              style={styles.closeButton}>
              <Text style={styles.closeText}>×</Text>
            </Pressable>
          </View>
          <View style={styles.divider} />
          <ScrollView
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={styles.body}
            showsVerticalScrollIndicator={false}>
            <ConnectionPill connected={connected} />
            <View style={styles.commandRow}>
              <View style={styles.commandIdWrap}>
                <Text style={styles.inputLabel}>命令 ID</Text>
                <TextInput
                  accessibilityLabel="TiRTC Command Panel Command ID"
                  value={commandIdText}
                  editable={!sending}
                  onChangeText={setCommandIdText}
                  placeholder="0x00000000"
                  placeholderTextColor={exampleTheme.textHint}
                  autoCapitalize="none"
                  style={styles.input}
                />
              </View>
              <View style={styles.segmented}>
                <ModeButton
                  label="HEX"
                  selected={payloadMode === 'hex'}
                  disabled={sending}
                  onPress={() => {
                    setPayloadMode('hex');
                    setInputError(null);
                  }}
                />
                <ModeButton
                  label="文本"
                  selected={payloadMode === 'text'}
                  disabled={sending}
                  onPress={() => {
                    setPayloadMode('text');
                    setInputError(null);
                  }}
                />
              </View>
            </View>
            <View style={styles.payloadWrap}>
              <Text style={styles.inputLabel}>命令内容</Text>
              <TextInput
                accessibilityLabel="TiRTC Command Panel Payload"
                value={payloadText}
                editable={!sending}
                multiline
                onChangeText={setPayloadText}
                placeholder={payloadMode === 'hex' ? '00 FF, 10 20' : '输入文本内容'}
                placeholderTextColor={exampleTheme.textHint}
                autoCapitalize="none"
                style={[styles.input, styles.payloadInput]}
              />
            </View>
            {inputError ? <Text style={styles.errorText}>{inputError}</Text> : null}
            <View style={styles.presets}>
              <Text style={styles.presetsTitle}>常用命令</Text>
              <View style={styles.presetRow}>
                {demoCommonCommandPresets.map((preset) => (
                  <Pressable
                    key={`${preset.label}-${preset.commandId}`}
                    accessible
                    accessibilityRole="button"
                    accessibilityLabel={
                      preset.label === 'Echo'
                        ? 'TiRTC Command Panel Echo Preset'
                        : `TiRTC Command Panel ${preset.label} Preset`
                    }
                    testID={automationTestId(
                      preset.label === 'Echo'
                        ? 'TiRTC Command Panel Echo Preset'
                        : `TiRTC Command Panel ${preset.label} Preset`,
                    )}
                    disabled={sending}
                    onPress={() => applyPreset(preset)}
                    style={[styles.presetChip, sending ? styles.disabledChip : null]}>
                    <Text style={styles.presetText}>{preset.label}</Text>
                  </Pressable>
                ))}
              </View>
            </View>
            <View style={styles.sendRow}>
              <Pressable
                accessible
                accessibilityRole="button"
                accessibilityLabel="TiRTC Command Panel Send Command"
                testID={automationTestId('TiRTC Command Panel Send Command')}
                disabled={!connected || sending}
                onPress={send}
                style={[styles.sendButton, !connected || sending ? styles.disabledSendButton : null]}>
                {sending ? <ActivityIndicator color={exampleTheme.foreground} size="small" /> : null}
                <Text style={styles.sendText}>{sending ? '发送中' : '发送'}</Text>
              </Pressable>
            </View>
            <View style={styles.events}>
              {panelEvents.length === 0 ? (
                <Text style={styles.emptyEvents}>暂无命令记录</Text>
              ) : (
                panelEvents.map((event) => (
                  <CommandEventRow key={`${event.createdAt}-${event.direction}-${event.commandId}`} event={event} />
                ))
              )}
            </View>
          </ScrollView>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

function ModeButton({
  label,
  selected,
  disabled,
  onPress,
}: {
  label: string;
  selected: boolean;
  disabled: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessible
      accessibilityRole="button"
      accessibilityLabel={`TiRTC Command Panel Payload Mode ${label}`}
      disabled={disabled}
      onPress={onPress}
      style={[styles.modeButton, selected ? styles.modeButtonSelected : null]}>
      <Text style={[styles.modeText, selected ? styles.modeTextSelected : null]}>{label}</Text>
    </Pressable>
  );
}

function ConnectionPill({connected}: {connected: boolean}) {
  return (
    <View style={[styles.connectionPill, connected ? styles.connectionPillReady : null]}>
      <Text style={[styles.connectionText, connected ? styles.connectionTextReady : null]}>
        {connected ? '已连接' : '未连接'}
      </Text>
    </View>
  );
}

function CommandEventRow({event}: {event: CommandPanelEvent}) {
  const sent = event.direction === 'sent';
  const color = sent ? exampleTheme.primary : exampleTheme.textPrimary;
  const payload = formatCommandPayloadHex(event.payload);
  return (
    <View style={[styles.eventRow, {backgroundColor: sent ? 'rgba(101,146,135,0.10)' : 'rgba(102,102,102,0.08)'}]}>
      <View style={styles.eventTitleRow}>
        <Text style={[styles.eventDirection, {color}]}>{sent ? '↗' : '↙'}</Text>
        <Text style={[styles.eventTitle, {color}]}>
          {sent ? '已发送' : '已收到'} {formatCommandId(event.commandId)}
        </Text>
        {event.resultCode !== undefined ? (
          <Text style={styles.eventCode}>{event.resultCode === 0 ? '#0' : TiRtc.formatError(event.resultCode)}</Text>
        ) : null}
      </View>
      <Text style={styles.eventPayload}>{payload.length === 0 ? '内容：空' : `内容：${payload}`}</Text>
    </View>
  );
}
