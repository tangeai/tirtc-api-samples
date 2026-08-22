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
  product,
  busy,
  status,
  onChange,
  onSelectProduct,
  onStart,
  onOpenStore,
  onOpenSettings,
  onScanToken,
}: {
  config: ExampleConfig;
  product: 'rtc' | 'store';
  busy: boolean;
  status: string;
  onChange: ExampleConfigChange;
  onSelectProduct: (product: 'rtc' | 'store') => void;
  onStart: () => void;
  onOpenStore: () => void;
  onOpenSettings: () => void;
  onScanToken: () => void;
}) {
  const visibleStatus = visibleConfigureStatus(status);
  return (
    <ExampleScreenRoot style={styles.safe}>
      <ScrollView keyboardShouldPersistTaps="handled">
        <ConfigureShell>
          <ConfigureHeader actionLabel="偏好设置" onAction={onOpenSettings} />
          <View style={styles.productTabs} accessibilityRole="tablist">
            <ProductTab label="RTC" selected={product === 'rtc'} onPress={() => onSelectProduct('rtc')} />
            <ProductTab label="云录像" selected={product === 'store'} onPress={() => onSelectProduct('store')} />
          </View>
          {product === 'rtc' ? (
            <>
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
                  style={styles.scanTokenButton}
                >
                  <Text style={styles.scanTokenButtonText}>扫码</Text>
                </Pressable>
              </View>
              <Text style={styles.orLabel}>或</Text>
              <InputField
                label="TiRTC DevTools 服务地址"
                hint="例如 http://192.168.1.10:8966"
                value={config.tokenServerAddress}
                accessibilityLabel="TiRTC Config tokenServerAddress"
                keyboardType="url"
                autoCapitalize="none"
                autoCorrect={false}
                onChangeText={(value) => onChange('tokenServerAddress', value)}
              />
              <PrimaryButton
                label={busy ? '初始化中' : '开始连接、拉流播放'}
                accessibilityLabel="TiRTC Start Downlink"
                busy={busy}
                onPress={onStart}
              />
            </>
          ) : (
            <>
              <InputField
                label="app_id"
                hint="TiStore 应用标识"
                value={config.appId}
                accessibilityLabel="TiStore Config appId"
                onChangeText={(value) => onChange('appId', value)}
              />
              <InputField
                label="endpoint"
                hint="留空则使用默认环境"
                value={config.endpoint}
                keyboardType="url"
                accessibilityLabel="TiStore Config endpoint"
                onChangeText={(value) => onChange('endpoint', value)}
              />
              <View style={styles.tokenRow}>
                <InputField
                  label="token"
                  hint="粘贴用于云录像查询的 APP Token"
                  value={config.storeToken}
                  accessibilityLabel="TiStore Config token"
                  autoCapitalize="none"
                  autoCorrect={false}
                  secureTextEntry
                  onChangeText={(value) => onChange('storeToken', value)}
                  style={styles.tokenField}
                />
                <Pressable
                  accessible
                  accessibilityRole="button"
                  accessibilityLabel="TiStore Scan Token QR"
                  onPress={onScanToken}
                  style={styles.scanTokenButton}
                >
                  <Text style={styles.scanTokenButtonText}>扫码</Text>
                </Pressable>
              </View>
              <FieldRow>
                <InputField
                  label="audio_channel_id"
                  hint="默认 10"
                  value={config.audioStreamId}
                  keyboardType="number-pad"
                  accessibilityLabel="TiStore Config audioChannelId"
                  onChangeText={(value) => onChange('audioStreamId', value)}
                />
                <InputField
                  label="video_channel_id"
                  hint="默认 11"
                  value={config.videoStreamId}
                  keyboardType="number-pad"
                  accessibilityLabel="TiStore Config videoChannelId"
                  onChangeText={(value) => onChange('videoStreamId', value)}
                />
              </FieldRow>
              <PrimaryButton
                label={busy ? '初始化中' : '播放云录像'}
                accessibilityLabel="TiStore Open"
                busy={busy}
                onPress={onOpenStore}
              />
            </>
          )}
          {visibleStatus ? <StatusText>{visibleStatus}</StatusText> : null}
        </ConfigureShell>
      </ScrollView>
    </ExampleScreenRoot>
  );
}

function ProductTab({label, selected, onPress}: {label: string; selected: boolean; onPress: () => void}) {
  return (
    <Pressable
      accessibilityRole="tab"
      accessibilityState={{selected}}
      onPress={onPress}
      style={[styles.productTab, selected ? styles.productTabSelected : null]}
    >
      <Text style={[styles.productTabText, selected ? styles.productTabTextSelected : null]}>{label}</Text>
    </Pressable>
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
  productTabs: {
    flexDirection: 'row',
    height: 44,
    padding: 3,
    borderRadius: 22,
    backgroundColor: 'rgba(101,146,135,0.10)',
    gap: 3,
  },
  productTab: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 19,
  },
  productTabSelected: {backgroundColor: exampleTheme.primary},
  productTabText: {color: exampleTheme.textSecondary, fontWeight: '600'},
  productTabTextSelected: {color: exampleTheme.foreground},
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
    minHeight: 56,
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
  orLabel: {color: exampleTheme.textHint, fontSize: 12, fontWeight: '600', textAlign: 'center'},
});
