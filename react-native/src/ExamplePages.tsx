import React from 'react';
import {Platform, Pressable, ScrollView, StyleSheet, Text, useWindowDimensions, View} from 'react-native';
import {
  ConfigureHeader,
  ConfigureShell,
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
  tiCloudStorageOnOpen,
  onOpenSettings,
  onScanToken,
}: {
  config: ExampleConfig;
  product: 'rtc' | 'tiCloudStorage';
  busy: boolean;
  status: string;
  onChange: ExampleConfigChange;
  onSelectProduct: (product: 'rtc' | 'tiCloudStorage') => void;
  onStart: () => void;
  tiCloudStorageOnOpen: () => void;
  onOpenSettings: () => void;
  onScanToken: () => void;
}) {
  const window = useWindowDimensions();
  const wide = window.width >= 840;
  const visibleStatus = visibleConfigureStatus(status);
  return (
    <ExampleScreenRoot style={styles.safe}>
      <ScrollView keyboardShouldPersistTaps="handled">
        <ConfigureShell>
          <ConfigureHeader actionLabel="偏好设置" onAction={onOpenSettings} />
          <View style={styles.productTabs} accessibilityRole="tablist">
            <ProductTab label="RTC" selected={product === 'rtc'} onPress={() => onSelectProduct('rtc')} />
            <ProductTab label="云录像" selected={product === 'tiCloudStorage'} onPress={() => onSelectProduct('tiCloudStorage')} />
          </View>
          <View testID={wide ? 'configure-layout-wide' : 'configure-layout-compact'}>
          {product === 'rtc' ? (
            <View style={[styles.formGrid, wide ? styles.formGridWide : null]}>
              <View style={styles.formColumn}>
              <ConfigSection title="连接" accessibilityLabel="TiRTC Config Connection Section">
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
              </ConfigSection>
              <ConfigSection title="音视频" accessibilityLabel="TiRTC Config Media Section">
              <MediaSelectionFields
                audioLabel="audio_stream_id"
                videoLabel="video_stream_id"
                audioValue={config.audioStreamId}
                videoValues={config.videoStreamIds}
                onAudioChange={(value) => onChange('audioStreamId', value)}
                onVideosChange={(value) => onChange('videoStreamIds', value)}
                accessibilityPrefix="TiRTC Config"
              />
              </ConfigSection>
              </View>
              <View style={styles.formColumn}>
              <ConfigSection title="鉴权" accessibilityLabel="TiRTC Config Authentication Section">
              <View style={styles.tokenRow}>
                <InputField
                  label="一次性连接 Token"
                  hint="粘贴 v1.xxx 一次性 Token，或点右侧扫码。"
                  value={config.token}
                  accessibilityLabel="TiRTC Config token"
                  autoCapitalize="none"
                  autoCorrect={false}
                  secureTextEntry
                  secureToggleAccessibilityLabel="TiRTC Config"
                  onChangeText={(value) => onChange('token', value)}
                  style={styles.tokenField}
                />
                <Pressable
                  accessible
                  accessibilityRole="button"
                  accessibilityLabel="TiRTC QR Input"
                  testID="TiRTC_Scan_Token_QR"
                  onPress={onScanToken}
                  style={styles.scanTokenButton}
                >
                  <Text style={styles.scanTokenButtonText}>扫码 / 粘贴</Text>
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
              </ConfigSection>
              <PrimaryButton
                label={busy ? '初始化中' : '开始连接、拉流播放'}
                accessibilityLabel="TiRTC Start Downlink"
                busy={busy}
                onPress={onStart}
              />
              </View>
            </View>
          ) : (
            <View style={[styles.formGrid, wide ? styles.formGridWide : null]}>
              <View style={styles.formColumn}>
              <ConfigSection title="连接" accessibilityLabel="Ti Cloud Storage Config Connection Section">
              <InputField
                label="app_id"
                hint="Ti Cloud Storage 应用标识"
                value={config.appId}
                accessibilityLabel="Ti Cloud Storage Config appId"
                onChangeText={(value) => onChange('appId', value)}
              />
              <InputField
                label="endpoint"
                hint="留空则使用默认环境"
                value={config.endpoint}
                keyboardType="url"
                accessibilityLabel="Ti Cloud Storage Config endpoint"
                onChangeText={(value) => onChange('endpoint', value)}
              />
              </ConfigSection>
              <ConfigSection title="音视频" accessibilityLabel="Ti Cloud Storage Config Media Section">
              <MediaSelectionFields
                audioLabel="audio_channel_id"
                videoLabel="video_channel_id"
                audioValue={config.tiCloudStorageAudioChannelId}
                videoValues={config.tiCloudStorageVideoChannelIds}
                onAudioChange={(value) => onChange('tiCloudStorageAudioChannelId', value)}
                onVideosChange={(value) => onChange('tiCloudStorageVideoChannelIds', value)}
                accessibilityPrefix="Ti Cloud Storage Config"
              />
              </ConfigSection>
              </View>
              <View style={styles.formColumn}>
              <ConfigSection title="鉴权" accessibilityLabel="Ti Cloud Storage Config Authentication Section">
              <View style={styles.tokenRow}>
                <InputField
                  label="token"
                  hint="粘贴用于云录像查询的 APP Token"
                  value={config.tiCloudStorageToken}
                  accessibilityLabel="Ti Cloud Storage Config token"
                  autoCapitalize="none"
                  autoCorrect={false}
                  secureTextEntry
                  secureToggleAccessibilityLabel="Ti Cloud Storage Config"
                  onChangeText={(value) => onChange('tiCloudStorageToken', value)}
                  style={styles.tokenField}
                />
                <Pressable
                  accessible
                  accessibilityRole="button"
                  accessibilityLabel="Ti Cloud Storage QR Input"
                  onPress={onScanToken}
                  style={styles.scanTokenButton}
                >
                  <Text style={styles.scanTokenButtonText}>扫码 / 粘贴</Text>
                </Pressable>
              </View>
              </ConfigSection>
              <PrimaryButton
                label={busy ? '初始化中' : '播放云录像'}
                accessibilityLabel="Ti Cloud Storage Open"
                busy={busy}
                onPress={tiCloudStorageOnOpen}
              />
              </View>
            </View>
          )}
          </View>
          {visibleStatus ? <StatusText>{visibleStatus}</StatusText> : null}
        </ConfigureShell>
      </ScrollView>
    </ExampleScreenRoot>
  );
}

function ConfigSection({title, accessibilityLabel, children}: {title: string; accessibilityLabel: string; children: React.ReactNode}) {
  return (
    <View testID={accessibilityLabel.replace(/\s+/g, '_')} style={styles.configSection}>
      <Text accessible accessibilityRole="header" accessibilityLabel={accessibilityLabel} style={styles.configSectionTitle}>{title}</Text>
      {children}
    </View>
  );
}

function MediaSelectionFields({
  audioLabel,
  videoLabel,
  audioValue,
  videoValues,
  onAudioChange,
  onVideosChange,
  accessibilityPrefix,
}: {
  audioLabel: string;
  videoLabel: string;
  audioValue: string;
  videoValues: readonly string[];
  onAudioChange: (value: string) => void;
  onVideosChange: (value: string[]) => void;
  accessibilityPrefix: string;
}) {
  return (
    <View style={styles.mediaSection}>
      <Text style={styles.mediaTitle}>音视频流</Text>
      <InputField
        label={audioLabel}
        hint="留空不接收音频"
        value={audioValue}
        keyboardType="number-pad"
        accessibilityLabel={`${accessibilityPrefix} audioId`}
        onChangeText={onAudioChange}
      />
      {videoValues.map((value, index) => (
        <View key={`${videoLabel}-${index}`} style={styles.videoRow}>
          <View style={styles.videoField}>
            <InputField
              label={`${videoLabel} ${index + 1}`}
              hint="留空行请删除"
              value={value}
              keyboardType="number-pad"
              accessibilityLabel={`${accessibilityPrefix} videoId ${index + 1}`}
              onChangeText={(next) => onVideosChange(videoValues.map((item, itemIndex) => itemIndex === index ? next : item))}
            />
          </View>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`${accessibilityPrefix} remove video ${index + 1}`}
            onPress={() => onVideosChange(videoValues.filter((_, itemIndex) => itemIndex !== index))}
            style={styles.removeVideoButton}>
            <Text style={styles.removeVideoText}>删除</Text>
          </Pressable>
        </View>
      ))}
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`${accessibilityPrefix} add video`}
        disabled={videoValues.length >= 3}
        onPress={() => onVideosChange([...videoValues, ''])}
        style={[styles.addVideoButton, videoValues.length >= 3 ? styles.disabledButton : null]}>
        <Text style={styles.addVideoText}>＋ 添加视频（{videoValues.length}/3）</Text>
      </Pressable>
    </View>
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
  formGrid: {gap: 16},
  formGridWide: {flexDirection: 'row', alignItems: 'flex-start'},
  formColumn: {flex: 1, minWidth: 0, gap: 16},
  configSection: {gap: 12, borderRadius: 20, backgroundColor: 'rgba(255,255,255,0.55)', padding: 14},
  configSectionTitle: {fontSize: 15, fontWeight: '800', color: exampleTheme.primary},
  mediaSection: {gap: 12},
  mediaTitle: {fontSize: 14, fontWeight: '700', color: exampleTheme.primary},
  videoRow: {flexDirection: 'row', alignItems: 'flex-end', gap: 10},
  videoField: {flex: 1},
  removeVideoButton: {minWidth: Platform.OS === 'ios' ? 44 : 48, minHeight: Platform.OS === 'ios' ? 44 : 48, justifyContent: 'center', paddingHorizontal: 12},
  removeVideoText: {color: '#B45309', fontSize: 13, fontWeight: '600'},
  addVideoButton: {alignSelf: 'flex-start', minHeight: Platform.OS === 'ios' ? 44 : 48, justifyContent: 'center', paddingHorizontal: 12},
  addVideoText: {color: exampleTheme.primary, fontSize: 13, fontWeight: '600'},
  disabledButton: {opacity: 0.45},
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
    minHeight: Platform.OS === 'ios' ? 44 : 48,
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
