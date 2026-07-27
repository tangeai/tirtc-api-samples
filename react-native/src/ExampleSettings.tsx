import React, {useState} from 'react';
import {ScrollView} from 'react-native';
import {
  BackHeader,
  ConfigureShell,
  ExampleScreenRoot,
} from './ExampleUi';
import {
  AUDIO_PROCESSING_LEVEL_OPTIONS,
  LOCAL_AUDIO_CODEC_OPTIONS,
  LOCAL_AUDIO_SAMPLE_RATE_OPTIONS,
  MAX_LOCAL_AUDIO_STREAM_ID,
  MIN_LOCAL_AUDIO_STREAM_ID,
  OUTPUT_BUFFER_OPTIONS,
  VIDEO_DECODER_OPTIONS,
  isLocalAudioCodec,
  isLocalAudioProcessingLevel,
  isLocalAudioSampleRate,
  isOutputBufferPolicy,
  isVideoDecoderPreference,
  localAudioCodecLabel,
  localAudioProcessingLevelLabel,
  localAudioSampleRateLabel,
  outputBufferPolicyLabel,
  videoDecoderPreferenceLabel,
  type PreferenceOption,
} from './ExampleSettingsOptions';
import {
  PreferenceSheet,
  SettingsDivider,
  SettingsRow,
  SettingsSection,
  SettingsSwitchRow,
  StreamIdDialog,
  type PreferenceSheetState,
} from './ExampleSettingsUi';
import type {ExampleConfig} from './ExampleTypes';

type ExampleConfigChange = <K extends keyof ExampleConfig>(key: K, value: ExampleConfig[K]) => void;

export function SettingsScreen({
  config,
  onChange,
  onBack,
}: {
  config: ExampleConfig;
  onChange: ExampleConfigChange;
  onBack: () => void;
}) {
  const [sheet, setSheet] = useState<PreferenceSheetState | null>(null);
  const [streamDialogVisible, setStreamDialogVisible] = useState(false);
  const [streamDraft, setStreamDraft] = useState(config.localAudioStreamId);

  const openSheet = (
    title: string,
    currentValue: string,
    options: readonly PreferenceOption[],
    onSelect: (value: string) => void,
  ) => {
    setSheet({title, currentValue, options, onSelect});
  };

  const selectLocalAudioCodec = (value: string) => {
    if (isLocalAudioCodec(value)) {
      onChange('localAudioCodec', value);
      if (value === 'amr') {
        onChange('localAudioSampleRateHz', '8000');
      }
    }
  };

  const selectLocalAudioSampleRate = (value: string) => {
    if (isLocalAudioSampleRate(value)) {
      onChange('localAudioSampleRateHz', config.localAudioCodec === 'amr' ? '8000' : value);
    }
  };

  const openStreamDialog = () => {
    setStreamDraft(config.localAudioStreamId);
    setStreamDialogVisible(true);
  };

  const saveStreamDialog = () => {
    const value = Number.parseInt(streamDraft.trim(), 10);
    if (Number.isInteger(value) && value >= MIN_LOCAL_AUDIO_STREAM_ID && value <= MAX_LOCAL_AUDIO_STREAM_ID) {
      onChange('localAudioStreamId', String(value));
    }
    setStreamDialogVisible(false);
  };

  return (
    <ExampleScreenRoot>
      <ScrollView keyboardShouldPersistTaps="handled">
        <ConfigureShell>
          <BackHeader
            title="设置"
            accessibilityLabel="TiRTC Settings Back"
            onBack={onBack}
          />
          <ClientSettingsSection
            config={config}
            openSheet={openSheet}
            onChange={onChange}
          />
          <LocalAudioSettingsSection
            config={config}
            openSheet={openSheet}
            onChange={onChange}
            onOpenStreamDialog={openStreamDialog}
            onSelectCodec={selectLocalAudioCodec}
            onSelectSampleRate={selectLocalAudioSampleRate}
          />
          <GeneralSettingsSection
            config={config}
            onChange={onChange}
          />
        </ConfigureShell>
      </ScrollView>
      <PreferenceSheet
        state={sheet}
        onClose={() => setSheet(null)}
      />
      <StreamIdDialog
        visible={streamDialogVisible}
        value={streamDraft}
        placeholder={`${MIN_LOCAL_AUDIO_STREAM_ID}-${MAX_LOCAL_AUDIO_STREAM_ID}`}
        onChangeText={setStreamDraft}
        onCancel={() => setStreamDialogVisible(false)}
        onSave={saveStreamDialog}
      />
    </ExampleScreenRoot>
  );
}

function ClientSettingsSection({
  config,
  openSheet,
  onChange,
}: {
  config: ExampleConfig;
  openSheet: OpenPreferenceSheet;
  onChange: ExampleConfigChange;
}) {
  return (
    <SettingsSection title="客户端播放">
      <SettingsRow
        title="视频解码偏好"
        value={videoDecoderPreferenceLabel(config.videoDecoderPreference)}
        accessibilityLabel="TiRTC Settings Video Decoder Preference"
        onPress={() =>
          openSheet('视频解码偏好', config.videoDecoderPreference, VIDEO_DECODER_OPTIONS, (value) => {
            if (isVideoDecoderPreference(value)) {
              onChange('videoDecoderPreference', value);
            }
          })
        }
      />
      <SettingsDivider />
      <SettingsRow
        title="输出缓冲策略"
        value={outputBufferPolicyLabel(config.outputBufferPolicy)}
        accessibilityLabel="TiRTC Settings Output Buffer Policy"
        onPress={() =>
          openSheet('输出缓冲策略', config.outputBufferPolicy, OUTPUT_BUFFER_OPTIONS, (value) => {
            if (isOutputBufferPolicy(value)) {
              onChange('outputBufferPolicy', value);
            }
          })
        }
      />
    </SettingsSection>
  );
}

function LocalAudioSettingsSection({
  config,
  openSheet,
  onChange,
  onOpenStreamDialog,
  onSelectCodec,
  onSelectSampleRate,
}: {
  config: ExampleConfig;
  openSheet: OpenPreferenceSheet;
  onChange: ExampleConfigChange;
  onOpenStreamDialog: () => void;
  onSelectCodec: (value: string) => void;
  onSelectSampleRate: (value: string) => void;
}) {
  return (
    <SettingsSection title="客户端语音对讲">
      <SettingsRow
        title="编码格式"
        value={localAudioCodecLabel(config.localAudioCodec)}
        accessibilityLabel="TiRTC Settings Local Audio Codec"
        onPress={() => openSheet('编码格式', config.localAudioCodec, LOCAL_AUDIO_CODEC_OPTIONS, onSelectCodec)}
      />
      <SettingsDivider />
      <SettingsRow
        title="采样率"
        value={localAudioSampleRateLabel(config.localAudioSampleRateHz)}
        accessibilityLabel="TiRTC Settings Local Audio Sample Rate"
        onPress={() =>
          openSheet('采样率', config.localAudioSampleRateHz, LOCAL_AUDIO_SAMPLE_RATE_OPTIONS, onSelectSampleRate)
        }
      />
      <SettingsDivider />
      <SettingsRow
        title="传输 Stream ID"
        value={config.localAudioStreamId}
        accessibilityLabel="TiRTC Settings Local Audio Stream ID"
        onPress={onOpenStreamDialog}
      />
      <SettingsDivider />
      <SettingsSwitchRow
        title="AEC"
        value={config.localAudioAecEnabled}
        accessibilityLabel="TiRTC Settings Local Audio AEC"
        onValueChange={(value) => onChange('localAudioAecEnabled', value)}
      />
      <SettingsDivider />
      <SettingsRow
        title="AGC"
        value={localAudioProcessingLevelLabel(config.localAudioAgcLevel)}
        accessibilityLabel="TiRTC Settings Local Audio AGC"
        onPress={() =>
          openSheet('AGC', config.localAudioAgcLevel, AUDIO_PROCESSING_LEVEL_OPTIONS, (value) => {
            if (isLocalAudioProcessingLevel(value)) {
              onChange('localAudioAgcLevel', value);
            }
          })
        }
      />
      <SettingsDivider />
      <SettingsRow
        title="ANS"
        value={localAudioProcessingLevelLabel(config.localAudioAnsLevel)}
        accessibilityLabel="TiRTC Settings Local Audio ANS"
        onPress={() =>
          openSheet('ANS', config.localAudioAnsLevel, AUDIO_PROCESSING_LEVEL_OPTIONS, (value) => {
            if (isLocalAudioProcessingLevel(value)) {
              onChange('localAudioAnsLevel', value);
            }
          })
        }
      />
    </SettingsSection>
  );
}

function GeneralSettingsSection({
  config,
  onChange,
}: {
  config: ExampleConfig;
  onChange: ExampleConfigChange;
}) {
  return (
    <SettingsSection title="通用">
      <SettingsSwitchRow
        title="启用控制台输出"
        value={config.consoleLogEnabled}
        accessibilityLabel="TiRTC Settings Console Log Enabled"
        onValueChange={(value) => onChange('consoleLogEnabled', value)}
      />
    </SettingsSection>
  );
}

type OpenPreferenceSheet = (
  title: string,
  currentValue: string,
  options: readonly PreferenceOption[],
  onSelect: (value: string) => void,
) => void;
