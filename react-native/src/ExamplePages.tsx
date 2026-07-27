import React from 'react';
import {Pressable, ScrollView, StyleSheet, Text, View} from 'react-native';
import {
  ConfigureHeader,
  ConfigureShell,
  FieldRow,
  InputField,
  ExampleScreenRoot,
  PrimaryButton,
  StatusText,
  exampleTheme,
} from './ExampleUi';
import type {ExampleConfig} from './ExampleTypes';

type ExampleConfigChange = <K extends keyof ExampleConfig>(key: K, value: ExampleConfig[K]) => void;

export function ConfigureScreen({
  config,
  busy,
  status,
  onChange,
  onStart,
  onOpenSettings,
  onScanToken,
}: {
  config: ExampleConfig;
  busy: boolean;
  status: string;
  onChange: ExampleConfigChange;
  onStart: () => void;
  onOpenSettings: () => void;
  onScanToken: () => void;
}) {
  const visibleStatus = visibleConfigureStatus(status);
  return (
    <ExampleScreenRoot style={styles.safe}>
      <ScrollView keyboardShouldPersistTaps="handled">
        <ConfigureShell>
          <ConfigureHeader actionLabel="偏好设置" onAction={onOpenSettings} />
          <InputField
            label="endpoint"
            hint="接入的云端环境，留空则使用默认环境。"
            value={config.endpoint}
            keyboardType="url"
            accessibilityLabel="TiRTC Config endpoint"
            onChangeText={(value) => onChange('endpoint', value)}
          />
          <InputField
            label="app_id"
            hint="TiRTC 应用标识，进入播放页前必须提供。"
            value={config.appId}
            accessibilityLabel="TiRTC Config appId"
            onChangeText={(value) => onChange('appId', value)}
          />
          <InputField
            label="remote_id"
            hint="待连接的设备 ID"
            value={config.remoteId}
            accessibilityLabel="TiRTC Config remoteId"
            onChangeText={(value) => onChange('remoteId', value)}
          />
          <FieldRow>
            <InputField
              label="audio_stream_id"
              hint="音频流 ID，默认 10"
              value={config.audioStreamId}
              keyboardType="number-pad"
              accessibilityLabel="TiRTC Config audioStreamId"
              onChangeText={(value) => onChange('audioStreamId', value)}
            />
            <InputField
              label="video_stream_id"
              hint="视频流 ID，默认 11"
              value={config.videoStreamId}
              keyboardType="number-pad"
              accessibilityLabel="TiRTC Config videoStreamId"
              onChangeText={(value) => onChange('videoStreamId', value)}
            />
          </FieldRow>
          <View style={styles.tokenRow}>
            <InputField
              label="一次性连接 Token"
              hint="粘贴 v1.xxx 一次性 Token，或点右侧扫码。"
              value={config.token}
              accessibilityLabel="TiRTC Config token"
              autoCapitalize="none"
              autoCorrect={false}
              onChangeText={(value) => onChange('token', value)}
              style={styles.tokenField}
            />
            <Pressable
              accessible
              accessibilityRole="button"
              accessibilityLabel="TiRTC Scan Token QR"
              testID="TiRTC_Scan_Token_QR"
              onPress={onScanToken}
              style={styles.scanTokenButton}>
              <Text style={styles.scanTokenButtonText}>扫码</Text>
            </Pressable>
          </View>
          <PrimaryButton
            label={busy ? '初始化中' : '开始连接、拉流播放'}
            accessibilityLabel="TiRTC Start Downlink"
            busy={busy}
            onPress={onStart}
          />
          {visibleStatus ? <StatusText>{visibleStatus}</StatusText> : null}
        </ConfigureShell>
      </ScrollView>
    </ExampleScreenRoot>
  );
}

function visibleConfigureStatus(status: string): string | null {
  const normalized = status.trim();
  if (!normalized || normalized === 'idle') {
    return null;
  }
  return normalized;
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: exampleTheme.background,
  },
  tokenRow: {
    flexDirection: 'row',
    alignItems: 'stretch',
    gap: 10,
  },
  tokenField: {
    flex: 1,
  },
  scanTokenButton: {
    width: 68,
    minHeight: 74,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(101,146,135,0.28)',
    backgroundColor: 'rgba(255,255,255,0.90)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  scanTokenButtonText: {
    color: exampleTheme.primary,
    fontSize: 13,
    fontWeight: '700',
  },
});
