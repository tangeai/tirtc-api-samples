import React, {useCallback, useEffect, useState} from 'react';
import {PermissionsAndroid, Platform, Pressable, StyleSheet, Text, View} from 'react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {Camera} from 'react-native-vision-camera';
import {CommandPanelSheet} from './ExampleCommandPanel';
import type {ClientSession} from './ExampleClientSession';
import {DownlinkMetricsOverlay} from './ExampleDownlinkMetricsOverlay';
import type {DownlinkMetricsOverlayModel} from './ExampleDownlinkMetricsOverlayModel';
import {useExampleLogUpload} from './ExampleLogUpload';
import {StreamMessageBubble} from './ExampleStreamMessageBubble';
import {
  DiagnosticsPanel,
  OutlineButton,
  StageControlButton,
  TopBar,
  VideoStage,
  exampleTheme,
  uiStyles,
} from './ExampleUi';
import {validSize} from './ExampleSessionShared';
import type {ExampleConfig} from './ExampleTypes';

export function PlayerScreen({
  config,
  session,
  status,
  onBack,
}: {
  config: ExampleConfig;
  session: ClientSession;
  status: string;
  onBack: () => void;
}) {
  const insets = useSafeAreaInsets();
  const controlBottom = stageControlBottom(insets.bottom);
  const renderSize = validSize(session.renderSize ?? session.videoOutput?.renderSize ?? null);
  const failed = isPlayerFailed(status);
  const [commandPanelVisible, setCommandPanelVisible] = useState(false);
  const [talkbackRunning, setTalkbackRunning] = useState(session.talkbackRunning);
  const [talkbackBusy, setTalkbackBusy] = useState(false);
  const [audioMuted, setAudioMuted] = useState(session.audioOutputMuted);
  const [recording, setRecording] = useState(session.recordingTask !== null);
  const [mediaBusy, setMediaBusy] = useState(false);
  const [mediaStatus, setMediaStatus] = useState<string | null>(null);
  const [metricsOverlay, setMetricsOverlay] = useState<DownlinkMetricsOverlayModel | null>(null);
  const runLogUpload = useCallback(() => session.uploadLogs(), [session]);
  const {uploadingLogs, uploadLogs} = useExampleLogUpload(runLogUpload);
  const metricsTop = stageMetricsTop(insets.top);
  const notice = playerStageNotice(status);
  useEffect(() => {
    setTalkbackRunning(session.talkbackRunning);
    session.onTalkbackStateChanged = setTalkbackRunning;
    return () => {
      if (session.onTalkbackStateChanged === setTalkbackRunning) {
        session.onTalkbackStateChanged = null;
      }
    };
  }, [session]);
  useEffect(() => {
    const updateMetrics = () => {
      setMetricsOverlay(session.readMetricsOverlay(config.videoDecoderPreference));
    };
    updateMetrics();
    const timer = setInterval(updateMetrics, 1000);
    return () => {
      clearInterval(timer);
    };
  }, [config.videoDecoderPreference, session]);
  const toggleTalkback = async () => {
    if (talkbackBusy) {
      return;
    }
    setTalkbackBusy(true);
    try {
      if (session.talkbackRunning) {
        await session.stopTalkback();
      } else {
        if (
          Platform.OS === 'android' &&
          !(await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO))
        ) {
          await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO);
          return;
        }
        if (Platform.OS === 'ios' && Camera.getMicrophonePermissionStatus() !== 'granted') {
          await Camera.requestMicrophonePermission();
          return;
        }
        await session.startTalkback(config);
      }
      setTalkbackRunning(session.talkbackRunning);
    } finally {
      setTalkbackBusy(false);
    }
  };
  const toggleAudioOutputMuted = () => {
    const nextMuted = !audioMuted;
    if (session.setAudioOutputMuted(nextMuted) === 0) {
      setAudioMuted(nextMuted);
    }
  };
  const toggleRecording = async () => {
    if (mediaBusy) return;
    setMediaBusy(true);
    const next = await session.toggleRecording();
    setRecording(session.recordingTask !== null);
    setMediaStatus(next);
    setMediaBusy(false);
  };
  const takeSnapshot = async () => {
    if (mediaBusy) return;
    setMediaBusy(true);
    try {
      const path = await session.takeSnapshot();
      setMediaStatus(path.length > 0
        ? `截图完成 · ${path}`
        : '截图失败');
    } catch {
      setMediaStatus('截图失败');
    } finally {
      setMediaBusy(false);
    }
  };
  const moveLatestMediaToGallery = async () => {
    if (mediaBusy) return;
    setMediaBusy(true);
    try {
      setMediaStatus(await session.moveLatestMediaToGallery() ? '已保存到系统相册' : '保存失败');
    } catch {
      setMediaStatus('保存失败');
    } finally {
      setMediaBusy(false);
    }
  };
  return (
    <View style={styles.stageRoot}>
      <VideoStage
        label={playerStageLabel(status)}
        failed={failed}
        showOverlay={shouldShowPlayerStageOverlay(status, renderSize)}>
        {session.videoOutput?.view({style: styles.videoView})}
      </VideoStage>
      <TopBar title={config.remoteId || 'TiRTC Player'} onBack={onBack}>
        <OutlineButton
          label="发送命令"
          accessibilityLabel="TiRTC Player Send Command"
          compact
          onPress={() => setCommandPanelVisible(true)}
        />
        <OutlineButton
          label={uploadingLogs ? '上传中' : '上传日志'}
          accessibilityLabel="TiRTC Player Upload Logs"
          busy={uploadingLogs}
          compact
          onPress={uploadLogs}
        />
      </TopBar>
      {metricsOverlay !== null ? (
        <View style={[styles.metricsWrap, {top: metricsTop}]}>
          <DownlinkMetricsOverlay metrics={metricsOverlay} />
        </View>
      ) : (
        <View style={[styles.diagnosticsWrap, {top: metricsTop}]}>
          <DiagnosticsPanel
            title="诊断"
            accessibilityLabel="TiRTC Player Diagnostics"
            lines={session.diagnostics()}
          />
        </View>
      )}
      {notice ? (
        <Text style={[styles.stageNotice, {bottom: controlBottom + STAGE_NOTICE_OFFSET}]}>
          {notice}
        </Text>
      ) : null}
      {mediaStatus ? <Text style={[styles.stageNotice, {bottom: controlBottom + STAGE_NOTICE_OFFSET}]}>{mediaStatus}</Text> : null}
      <View
        style={[
          styles.streamMessageBubbleWrap,
          uiStyles.noPointerEvents,
          {bottom: controlBottom + STREAM_MESSAGE_OFFSET},
        ]}>
        <StreamMessageBubble text={session.streamMessageText} />
      </View>
      <View style={[styles.stageControls, {bottom: controlBottom}]}>
        <View style={styles.stageControlRow}>
          <MediaActionButton symbol={recording ? '◉' : '●'} label={recording ? '停止本地保存' : '开始本地保存'} disabled={mediaBusy} onPress={toggleRecording} />
          <MediaActionButton symbol="▣" label="截图" disabled={mediaBusy} onPress={takeSnapshot} />
          <MediaActionButton symbol="▧" label="保存到系统相册" disabled={mediaBusy} onPress={moveLatestMediaToGallery} />
          <StageControlButton
            label={audioMuted ? '恢复声音' : '静音'}
            accessibilityLabel={audioMuted ? 'TiRTC Player Restore Audio' : 'TiRTC Player Mute Audio'}
            tone={audioMuted ? 'primary' : 'surface'}
            onPress={toggleAudioOutputMuted}
          />
          <StageControlButton
            label={talkbackBusy ? '处理中' : talkbackRunning ? '停止麦克风' : '启动麦克风'}
            accessibilityLabel={talkbackRunning ? 'TiRTC Player Stop Talkback' : 'TiRTC Player Start Talkback'}
            tone={talkbackRunning ? 'primary' : 'surface'}
            busy={talkbackBusy}
            onPress={toggleTalkback}
          />
          <StageControlButton
            label="停止播放"
            accessibilityLabel="TiRTC Player Stop"
            tone="danger"
            onPress={onBack}
          />
        </View>
      </View>
      <CommandPanelSheet
        visible={commandPanelVisible}
        title="发送命令"
        connected={session.commandConnected}
        events={session.commandEvents}
        onClose={() => setCommandPanelVisible(false)}
        onSendCommand={(commandId, payload) => session.sendCommand(commandId, payload)}
      />
    </View>
  );
}

function MediaActionButton({symbol, label, disabled, onPress}: {
  symbol: string;
  label: string;
  disabled: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable accessibilityRole="button" accessibilityLabel={label} disabled={disabled} onPress={onPress}
      style={({pressed}) => [styles.mediaAction, (disabled || pressed) && styles.mediaActionDimmed]}>
      <Text style={styles.mediaActionSymbol}>{symbol}</Text>
    </Pressable>
  );
}

const STAGE_CONTROL_BOTTOM_GAP = 28;
const STREAM_MESSAGE_OFFSET = 62;
const STAGE_NOTICE_OFFSET = 74;
const STAGE_METRICS_TOP_GAP = 78;

function stageControlBottom(safeAreaBottom: number): number {
  return Math.max(safeAreaBottom, 0) + STAGE_CONTROL_BOTTOM_GAP;
}

function stageMetricsTop(safeAreaTop: number): number {
  return Math.max(safeAreaTop, 0) + STAGE_METRICS_TOP_GAP;
}

function playerStageLabel(status: string): string {
  if (isPlayerFailed(status)) {
    return '启动失败';
  }
  if (status.includes('rendering') || status.includes('playing')) {
    return '播放中';
  }
  if (status.startsWith('stream message')) {
    return '播放中';
  }
  return '连接中';
}

function shouldShowPlayerStageOverlay(
  status: string,
  renderSize: {width: number; height: number} | null,
): boolean {
  if (isPlayerFailed(status)) {
    return true;
  }
  if (status.includes('video rendering')) {
    return false;
  }
  if (renderSize !== null) {
    return false;
  }
  return true;
}

function isPlayerFailed(status: string): boolean {
  return status.includes('failed') || status.includes('失败');
}

function playerStageNotice(status: string): string | null {
  if (isPlayerFailed(status)) {
    return status;
  }
  if (status.startsWith('command')) {
    return status;
  }
  if (status.startsWith('麦克风')) {
    return status;
  }
  return null;
}

const styles = StyleSheet.create({
  stageRoot: {
    flex: 1,
    backgroundColor: exampleTheme.videoBackground,
  },
  videoView: {
    width: '100%',
    height: '100%',
  },
  stageControls: {
    position: 'absolute',
    right: 20,
    zIndex: 10,
    elevation: 10,
    alignItems: 'flex-end',
  },
  stageControlRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    alignItems: 'center',
    gap: 12,
  },
  mediaAction: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: '#D9E5E2',
    alignItems: 'center',
    justifyContent: 'center',
  },
  mediaActionDimmed: {opacity: 0.55},
  mediaActionSymbol: {color: '#659287', fontSize: 18, fontWeight: '700'},
  streamMessageBubbleWrap: {
    position: 'absolute',
    right: 20,
    zIndex: 10,
    elevation: 10,
    alignItems: 'flex-end',
    maxWidth: '72%',
  },
  diagnosticsWrap: {
    position: 'absolute',
    left: 20,
    zIndex: 9,
    elevation: 9,
    maxWidth: '54%',
  },
  metricsWrap: {
    position: 'absolute',
    left: 18,
    right: 18,
    zIndex: 9,
    elevation: 9,
    alignItems: 'center',
  },
  stageNotice: {
    position: 'absolute',
    left: 20,
    right: 20,
    zIndex: 10,
    elevation: 10,
    alignSelf: 'flex-start',
    borderRadius: 18,
    overflow: 'hidden',
    backgroundColor: 'rgba(0,0,0,0.46)',
    paddingHorizontal: 14,
    paddingVertical: 9,
    color: exampleTheme.foreground,
    fontSize: 13,
    fontWeight: '600',
    textShadowColor: 'rgba(0,0,0,0.55)',
    textShadowOffset: {width: 0, height: 1},
    textShadowRadius: 4,
  },
});
