import React, {useCallback, useEffect, useRef, useState} from 'react';
import {PermissionsAndroid, Platform, Pressable, StyleSheet, Text, useWindowDimensions, View} from 'react-native';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {Camera} from 'react-native-vision-camera';
import {CommandPanelSheet} from './ExampleCommandPanel';
import type {ClientSession} from './ExampleClientSession';
import {DownlinkMetricsOverlay} from './ExampleDownlinkMetricsOverlay';
import type {DownlinkMetricsOverlayModel} from './ExampleDownlinkMetricsOverlayModel';
import {useExampleLogUpload} from './ExampleLogUpload';
import {StreamMessageBubble} from './ExampleStreamMessageBubble';
import {PlaybackActionMenu} from './ExamplePlaybackMenu';
import {
  DiagnosticsPanel,
  RawDumpStageControl,
  StageControlButton,
  TopBar,
  VideoStage,
  exampleTheme,
  uiStyles,
} from './ExampleUi';
import {validSize} from './ExampleSessionShared';
import type {ExampleConfig} from './ExampleTypes';
import {TiRtcVideoOutputState} from 'tirtc-react-native';

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
  const window = useWindowDimensions();
  const controlBottom = stageControlBottom(insets.bottom);
  const videoStreamIds = [...session.videoOutputs.keys()];
  const [selectedVideoStreamId, setSelectedVideoStreamId] = useState<number | null>(session.selectedVideoStreamId);
  const [maximizedVideoStreamId, setMaximizedVideoStreamId] = useState<number | null>(null);
  const [commandPanelVisible, setCommandPanelVisible] = useState(false);
  const moreButtonRef = useRef<View | null>(null);
  const [talkbackRunning, setTalkbackRunning] = useState(session.talkbackRunning);
  const [talkbackBusy, setTalkbackBusy] = useState(false);
  const [audioMuted, setAudioMuted] = useState(session.audioOutputMuted);
  const [recording, setRecording] = useState(session.recordingTask !== null);
  const [mediaBusy, setMediaBusy] = useState(false);
  const [rawDumpBusy, setRawDumpBusy] = useState(false);
  const [rawDumpCapturing, setRawDumpCapturing] = useState(false);
  const [rawDumpUploadPending, setRawDumpUploadPending] = useState(false);
  const [mediaStatus, setMediaStatus] = useState<string | null>(null);
  const [metricsOverlay, setMetricsOverlay] = useState<DownlinkMetricsOverlayModel | null>(null);
  const runLogUpload = useCallback(() => session.uploadLogs(), [session]);
  const {uploadingLogs, uploadLogs} = useExampleLogUpload(runLogUpload);
  const metricsTop = stageMetricsTop(insets.top);
  const notice = playerStageNotice(status);
  const selectedVideoReady = selectedVideoStreamId !== null &&
    session.videoStateFor(selectedVideoStreamId) === TiRtcVideoOutputState.rendering;
  const compact = window.width < 600;
  const primaryVideoStreamId = videoStreamIds.find((streamId) => streamId === selectedVideoStreamId)
    ?? videoStreamIds[0]
    ?? null;
  const secondaryVideoStreamIds = videoStreamIds.filter((streamId) => streamId !== primaryVideoStreamId);
  const sessionSelectedVideoStreamId = session.selectedVideoStreamId;
  const videoLaneLayout = (streamId: number) => {
    if (maximizedVideoStreamId !== null) {
      return streamId === maximizedVideoStreamId ? styles.videoLaneFill : styles.videoLaneParked;
    }
    if (streamId === primaryVideoStreamId) {
      if (secondaryVideoStreamIds.length === 0) return styles.videoLaneFill;
      return compact ? styles.videoLanePrimaryCompact : styles.videoLanePrimaryWide;
    }
    const secondaryIndex = secondaryVideoStreamIds.indexOf(streamId);
    if (compact) {
      if (secondaryVideoStreamIds.length === 1) return styles.videoLaneSecondaryCompactSingle;
      return secondaryIndex === 0
        ? styles.videoLaneSecondaryCompactLeading
        : styles.videoLaneSecondaryCompactTrailing;
    }
    if (secondaryVideoStreamIds.length === 1) return styles.videoLaneSecondaryWideSingle;
    return secondaryIndex === 0
      ? styles.videoLaneSecondaryWideLeading
      : styles.videoLaneSecondaryWideTrailing;
  };
  useEffect(() => {
    if (sessionSelectedVideoStreamId !== null) {
      setSelectedVideoStreamId((current) => current ?? sessionSelectedVideoStreamId);
    }
  }, [sessionSelectedVideoStreamId]);
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
  const toggleRawDump = async () => {
    if (rawDumpBusy || uploadingLogs) return;
    setRawDumpBusy(true);
    const result = await session.toggleRawDump();
    setRawDumpCapturing(result.capturing);
    setMediaStatus(result.status);
    setRawDumpBusy(false);
    if (result.upload) {
      const success = await uploadLogs();
      session.finishRawDumpUpload(success);
      setRawDumpUploadPending(session.isRawDumpUploadPending());
      setMediaStatus(success ? '诊断数据上传成功' : '诊断数据上传失败 · 点击重试上传');
    }
  };
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
  const renderVideoLane = (streamId: number) => {
    const output = session.videoOutputs.get(streamId)!;
    const state = session.videoStateFor(streamId);
    const size = validSize(session.renderSizeFor(streamId) ?? output.renderSize);
    const selected = selectedVideoStreamId === streamId;
    const laneFailed = state === TiRtcVideoOutputState.failed;
    const rendered = state === TiRtcVideoOutputState.rendering || size !== null;
    const laneStatus = laneFailed
      ? session.videoFailureFor(streamId)
      : state === TiRtcVideoOutputState.rendering
        ? '播放中'
        : state === TiRtcVideoOutputState.buffering
          ? '缓冲中'
          : '等待视频';
    return (
      <View collapsable={false} style={[styles.videoTile, selected ? styles.videoTileSelected : null]}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Video Stream ${streamId}`}
          accessibilityValue={{text: laneStatus}}
          accessibilityState={{selected}}
          testID={`video-stream-${streamId}`}
          onPress={() => {
            if (selected) {
              setMaximizedVideoStreamId((current) => current === streamId ? null : streamId);
            } else {
              session.selectVideoStream(streamId);
              setSelectedVideoStreamId(streamId);
            }
          }}
          onLongPress={() => setMaximizedVideoStreamId((current) => current === streamId ? null : streamId)}
          style={styles.videoTileContent}>
          {output.view({style: styles.videoView})}
          {laneFailed || !rendered ? (
            <View pointerEvents="none" style={styles.videoLaneOverlay}>
              <Text style={styles.videoLaneStatus}>{laneStatus}</Text>
            </View>
          ) : null}
          <Text style={styles.videoLaneLabel}>视频 {videoStreamIds.indexOf(streamId) + 1} · Stream {streamId}</Text>
        </Pressable>
      </View>
    );
  };
  return (
    <View style={styles.stageRoot}>
      <View style={styles.videoGrid}>
        {videoStreamIds.length === 0 ? (
          <VideoStage
            label={config.audioStreamId.trim().length === 0
              ? '未配置音视频'
              : session.audioOutput === null ? '音频不可用' : '仅音频播放'}
            showOverlay
            failed={false}
          />
        ) : (
          <View style={styles.mosaic}>
            {videoStreamIds.map((streamId) => {
              const parked = maximizedVideoStreamId !== null && streamId !== maximizedVideoStreamId;
              return (
                <View
                  key={streamId}
                  collapsable={false}
                  pointerEvents={parked ? 'none' : 'auto'}
                  accessibilityElementsHidden={parked}
                  importantForAccessibility={parked ? 'no-hide-descendants' : 'auto'}
                  style={videoLaneLayout(streamId)}>
                  {renderVideoLane(streamId)}
                </View>
              );
            })}
          </View>
        )}
      </View>
      <TopBar title={config.remoteId || 'TiRTC Player'} onBack={onBack} />
      {selectedVideoStreamId !== null ? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={maximizedVideoStreamId === selectedVideoStreamId ? '返回宫格' : '放大视频'}
          testID={maximizedVideoStreamId === selectedVideoStreamId ? 'video-grid-restore' : 'video-maximize'}
          onPress={() => setMaximizedVideoStreamId((current) => current === selectedVideoStreamId ? null : selectedVideoStreamId)}
          style={[styles.maximizeButton, {top: insets.top + 76}]}>
          <Text style={styles.maximizeButtonText}>{maximizedVideoStreamId === selectedVideoStreamId ? '宫格' : '放大'}</Text>
        </Pressable>
      ) : null}
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
        <Text
          testID="tirtc-player-status"
          accessible
          accessibilityLabel="TiRTC Player Status"
          accessibilityValue={{text: notice}}
          style={[styles.stageNotice, {bottom: controlBottom + STAGE_NOTICE_OFFSET}]}>
          {notice}
        </Text>
      ) : null}
      {mediaStatus ? <Text style={[styles.stageNotice, {bottom: controlBottom + STAGE_NOTICE_OFFSET}]}>{mediaStatus}</Text> : null}
      <RawDumpStageControl
        capturing={rawDumpCapturing}
        uploadPending={rawDumpUploadPending}
        busy={rawDumpBusy || uploadingLogs}
        accessibilityLabel="TiRTC Player Raw Dump"
        onPress={() => void toggleRawDump()}
      />
      <View
        style={[
          styles.streamMessageBubbleWrap,
          uiStyles.noPointerEvents,
          {bottom: controlBottom + STREAM_MESSAGE_OFFSET},
        ]}>
        <StreamMessageBubble text={session.streamMessageText} />
      </View>
      <View testID="tirtc-player-control-surface" collapsable={false} style={[styles.stageControls, {bottom: controlBottom}]}>
        <View style={styles.stageControlRow}>
          <StageControlButton
            playbackProfile
            compactPlayback={compact}
            label={compact ? '音' : (audioMuted ? '恢复声音' : '静音')}
            accessibilityLabel={audioMuted ? 'TiRTC Player Restore Audio' : 'TiRTC Player Mute Audio'}
            tone={audioMuted ? 'primary' : 'surface'}
            busy={session.audioOutput === null}
            onPress={toggleAudioOutputMuted}
          />
          <StageControlButton
            playbackProfile
            compactPlayback={compact}
            label={compact ? '麦' : (talkbackBusy ? '处理中' : talkbackRunning ? '停止麦克风' : '启动麦克风')}
            accessibilityLabel={talkbackRunning ? 'TiRTC Player Stop Talkback' : 'TiRTC Player Start Talkback'}
            tone={talkbackRunning ? 'primary' : 'surface'}
            busy={talkbackBusy}
            onPress={toggleTalkback}
          />
          <StageControlButton
            playbackProfile
            compactPlayback={compact}
            label={compact ? '■' : '停止播放'}
            accessibilityLabel="TiRTC Player Stop"
            tone="danger"
            onPress={onBack}
          />
          <PlaybackActionMenu
            accessibilityLabel="TiRTC Player More"
            triggerRef={moreButtonRef}
            actions={[
              {label: '发送命令', accessibilityLabel: 'TiRTC Player Send Command', onPress: () => setCommandPanelVisible(true)},
              ...(videoStreamIds.length > 0 ? [
                {label: recording ? '停止本地保存' : `开始本地保存 · ${selectedVideoStreamId ?? ''}`, accessibilityLabel: 'TiRTC Player Recording', disabled: mediaBusy || (!recording && !selectedVideoReady), onPress: () => void toggleRecording()},
                {label: `截图 · ${selectedVideoStreamId ?? ''}`, accessibilityLabel: 'TiRTC Player Snapshot', disabled: mediaBusy || !selectedVideoReady, onPress: () => void takeSnapshot()},
                {label: '保存到系统相册', accessibilityLabel: 'TiRTC Player Save Gallery', disabled: mediaBusy || !session.hasLatestMedia, onPress: () => void moveLatestMediaToGallery()},
              ] : []),
              {label: uploadingLogs ? '上传中…' : '上传日志', accessibilityLabel: 'TiRTC Player Upload Logs', disabled: uploadingLogs, onPress: uploadLogs},
            ]}
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
        returnFocusRef={moreButtonRef}
      />
    </View>
  );
}

const STAGE_CONTROL_BOTTOM_GAP = Platform.OS === 'ios' ? 0 : 8;
const STREAM_MESSAGE_OFFSET = 62;
const STAGE_NOTICE_OFFSET = 74;
const STAGE_METRICS_TOP_GAP = 78;

function stageControlBottom(safeAreaBottom: number): number {
  return Math.max(safeAreaBottom, 0) + STAGE_CONTROL_BOTTOM_GAP;
}

function stageMetricsTop(safeAreaTop: number): number {
  return Math.max(safeAreaTop, 0) + STAGE_METRICS_TOP_GAP;
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
  videoGrid: {flex: 1, backgroundColor: exampleTheme.videoBackground},
  mosaic: {flex: 1, position: 'relative'},
  videoLaneFill: {position: 'absolute', left: 0, right: 0, top: 0, bottom: 0},
  videoLanePrimaryCompact: {position: 'absolute', left: 0, right: 0, top: 0, bottom: '33.333%'},
  videoLanePrimaryWide: {position: 'absolute', left: 0, right: '33.333%', top: 0, bottom: 0},
  videoLaneSecondaryCompactSingle: {position: 'absolute', left: 0, right: 0, top: '66.667%', bottom: 0},
  videoLaneSecondaryCompactLeading: {position: 'absolute', left: 0, width: '50%', top: '66.667%', bottom: 0},
  videoLaneSecondaryCompactTrailing: {position: 'absolute', left: '50%', right: 0, top: '66.667%', bottom: 0},
  videoLaneSecondaryWideSingle: {position: 'absolute', left: '66.667%', right: 0, top: 0, bottom: 0},
  videoLaneSecondaryWideLeading: {position: 'absolute', left: '66.667%', right: 0, top: 0, height: '50%'},
  videoLaneSecondaryWideTrailing: {position: 'absolute', left: '66.667%', right: 0, top: '50%', bottom: 0},
  videoLaneParked: {position: 'absolute', left: -2, top: -2, width: 1, height: 1, opacity: 0},
  videoTile: {flex: 1, position: 'relative', overflow: 'hidden', backgroundColor: '#252525', borderWidth: 2, borderColor: 'transparent'},
  videoTileContent: {flex: 1, position: 'relative'},
  videoTileSelected: {borderColor: '#659287'},
  videoLaneOverlay: {position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, alignItems: 'center', justifyContent: 'center', backgroundColor: '#252525'},
  videoLaneStatus: {color: '#CCFFFFFF', fontSize: 13},
  videoLaneLabel: {position: 'absolute', left: 8, top: 8, zIndex: 1, elevation: 1, color: '#FFFFFF', backgroundColor: '#75000000', borderRadius: 10, paddingHorizontal: 8, paddingVertical: 4, fontSize: 11},
  maximizeButton: {position: 'absolute', right: 8, zIndex: 11, elevation: 11, minWidth: Platform.OS === 'ios' ? 44 : 48, minHeight: Platform.OS === 'ios' ? 44 : 48, alignItems: 'center', justifyContent: 'center', backgroundColor: '#75000000', borderRadius: 10, paddingHorizontal: 8, paddingVertical: 4},
  maximizeButtonText: {color: '#FFFFFF', fontSize: 11},
  stageControls: {
    position: 'absolute',
    left: 12,
    right: 12,
    zIndex: 10,
    elevation: 10,
    alignItems: 'flex-end',
    padding: Platform.OS === 'ios' ? 4 : 8,
    borderRadius: Platform.OS === 'ios' ? 12 : 20,
    backgroundColor: Platform.OS === 'ios' ? 'rgba(37,37,37,0.72)' : 'rgba(37,37,37,0.92)',
  },
  stageControlRow: {
    flexDirection: 'row',
    width: '100%',
    maxWidth: 620,
    alignSelf: 'center',
    justifyContent: 'flex-end',
    alignItems: 'center',
    gap: Platform.OS === 'ios' ? 6 : 8,
  },
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
