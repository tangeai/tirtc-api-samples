import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../demo_widget_keys.dart';
import 'downlink_center_loading.dart';

class PlayerCommandButton extends StatelessWidget {
  const PlayerCommandButton({super.key, required this.onOpenCommands, this.focusNode});

  final VoidCallback onOpenCommands;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      child: TextButton.icon(
        focusNode: focusNode,
        style: TextButton.styleFrom(minimumSize: Size.square(ExampleTheme.minimumTargetSize(context))),
        onPressed: onOpenCommands,
        icon: const Icon(Icons.terminal_rounded, size: 18),
        label: const Text('命令', style: TextStyle(fontSize: 12)),
      ),
    );
  }
}

class PlayerLogUploadButton extends StatelessWidget {
  const PlayerLogUploadButton({super.key, this.buttonKey, required this.uploadingLogs, required this.onUploadLogs});

  final Key? buttonKey;
  final bool uploadingLogs;
  final VoidCallback onUploadLogs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: TextButton(
        key: buttonKey,
        style: OutlinedButton.styleFrom(
          foregroundColor: ExampleTheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.square(ExampleTheme.minimumTargetSize(context)),
        ),
        onPressed: uploadingLogs ? null : onUploadLogs,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (uploadingLogs) ...<Widget>[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(ExampleTheme.primary.withAlpha(214)),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(uploadingLogs ? '上传中' : '上传日志', style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

final class DownlinkVideoLaneModel {
  const DownlinkVideoLaneModel({
    required this.streamId,
    required this.videoView,
    required this.statusLabel,
    required this.showStatus,
  });

  final int streamId;
  final Widget videoView;
  final String statusLabel;
  final bool showStatus;
}

class DownlinkVideoStage extends StatelessWidget {
  const DownlinkVideoStage({
    super.key,
    this.lanes = const <DownlinkVideoLaneModel>[],
    this.videoView,
    this.showStageOverlay = false,
    this.selectedStreamId,
    this.maximizedStreamId,
    required this.stageStatusLabel,
    required this.indicatorMode,
    this.onSelect,
  });

  final List<DownlinkVideoLaneModel> lanes;
  final Widget? videoView;
  final bool showStageOverlay;
  final int? selectedStreamId;
  final int? maximizedStreamId;
  final String stageStatusLabel;
  final DownlinkCenterIndicatorMode indicatorMode;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (lanes.isEmpty && videoView != null) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: ExampleTheme.videoBackground),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(child: videoView),
            if (showStageOverlay) Center(child: DownlinkCenterLoading(label: stageStatusLabel, mode: indicatorMode)),
          ],
        ),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: ExampleTheme.videoBackground),
      child:
          lanes.isEmpty
              ? Center(child: DownlinkCenterLoading(label: stageStatusLabel, mode: indicatorMode))
              : LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool compact = constraints.maxWidth < ExampleTheme.compactBreakpoint;
                  final int? activeMaximizedStreamId =
                      lanes.any((DownlinkVideoLaneModel lane) => lane.streamId == maximizedStreamId)
                          ? maximizedStreamId
                          : null;
                  final Map<int, Rect> laneRects = _laneRects(
                    size: constraints.biggest,
                    compact: compact,
                    activeMaximizedStreamId: activeMaximizedStreamId,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.hardEdge,
                    children: <Widget>[
                      for (final DownlinkVideoLaneModel lane in lanes)
                        Positioned.fromRect(
                          key: ValueKey<String>('downlink-video-lane-${lane.streamId}'),
                          rect: laneRects[lane.streamId]!,
                          child: IgnorePointer(
                            ignoring: activeMaximizedStreamId != null && lane.streamId != activeMaximizedStreamId,
                            child: ExcludeSemantics(
                              excluding: activeMaximizedStreamId != null && lane.streamId != activeMaximizedStreamId,
                              child: Opacity(
                                opacity:
                                    activeMaximizedStreamId != null && lane.streamId != activeMaximizedStreamId ? 0 : 1,
                                child: _buildLane(lane),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
    );
  }

  Map<int, Rect> _laneRects({required Size size, required bool compact, required int? activeMaximizedStreamId}) {
    if (activeMaximizedStreamId != null) {
      return <int, Rect>{
        for (final DownlinkVideoLaneModel lane in lanes)
          lane.streamId:
              lane.streamId == activeMaximizedStreamId ? Offset.zero & size : const Rect.fromLTWH(-2, -2, 1, 1),
      };
    }
    if (lanes.length == 1) {
      return <int, Rect>{lanes.single.streamId: Offset.zero & size};
    }
    if (lanes.length == 2) {
      return compact
          ? <int, Rect>{
            lanes[0].streamId: Rect.fromLTWH(0, 0, size.width, size.height / 2),
            lanes[1].streamId: Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2),
          }
          : <int, Rect>{
            lanes[0].streamId: Rect.fromLTWH(0, 0, size.width / 2, size.height),
            lanes[1].streamId: Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height),
          };
    }
    final DownlinkVideoLaneModel primary = lanes.firstWhere(
      (DownlinkVideoLaneModel lane) => lane.streamId == selectedStreamId,
      orElse: () => lanes.first,
    );
    final List<DownlinkVideoLaneModel> secondary =
        lanes.where((DownlinkVideoLaneModel lane) => lane.streamId != primary.streamId).toList();
    if (compact) {
      final double primaryHeight = size.height * 2 / 3;
      final double secondaryWidth = size.width / secondary.length;
      return <int, Rect>{
        primary.streamId: Rect.fromLTWH(0, 0, size.width, primaryHeight),
        for (final (int index, DownlinkVideoLaneModel lane) in secondary.indexed)
          lane.streamId: Rect.fromLTWH(
            secondaryWidth * index,
            primaryHeight,
            secondaryWidth,
            size.height - primaryHeight,
          ),
      };
    }
    final double primaryWidth = size.width * 2 / 3;
    final double secondaryHeight = size.height / secondary.length;
    return <int, Rect>{
      primary.streamId: Rect.fromLTWH(0, 0, primaryWidth, size.height),
      for (final (int index, DownlinkVideoLaneModel lane) in secondary.indexed)
        lane.streamId: Rect.fromLTWH(primaryWidth, secondaryHeight * index, size.width - primaryWidth, secondaryHeight),
    };
  }

  Widget _buildLane(DownlinkVideoLaneModel lane) {
    final bool selected = lane.streamId == selectedStreamId;
    return Semantics(
      button: true,
      selected: selected,
      label: '视频流 ${lane.streamId}${selected ? '，当前主画面' : ''}',
      value: lane.statusLabel,
      child: GestureDetector(
        onTap: () => onSelect?.call(lane.streamId),
        child: Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: ExampleTheme.videoBackground,
            border: Border.all(color: selected ? ExampleTheme.primary : Colors.transparent, width: 2),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              SizedBox.expand(child: lane.videoView),
              Positioned(
                top: 8,
                left: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black.withAlpha(145), borderRadius: BorderRadius.circular(6)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      '视频 ${lanes.indexOf(lane) + 1} · ID ${lane.streamId}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
              if (lane.showStatus) Center(child: DownlinkCenterLoading(label: lane.statusLabel, mode: indicatorMode)),
            ],
          ),
        ),
      ),
    );
  }
}

class DownlinkOverlayGradient extends StatelessWidget {
  const DownlinkOverlayGradient({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.black.withAlpha(117), Colors.transparent, Colors.black.withAlpha(153)],
          ),
        ),
      ),
    );
  }
}

class DownlinkControlButton extends StatelessWidget {
  const DownlinkControlButton({
    super.key,
    required this.connecting,
    required this.playing,
    required this.onPressed,
    this.compact = false,
  });

  final bool connecting;
  final bool playing;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final String label = connecting ? '正在连接' : (playing ? '停止播放' : '开始播放');
    final Widget icon =
        connecting
            ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
            )
            : Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_fill_rounded);
    return Semantics(
      button: true,
      label: label,
      child:
          compact
              ? IconButton.filled(
                tooltip: label,
                onPressed: connecting ? null : onPressed,
                style: IconButton.styleFrom(
                  minimumSize: Size.square(ExampleTheme.minimumTargetSize(context)),
                  backgroundColor: playing ? Colors.redAccent.shade200 : ExampleTheme.primary,
                ),
                icon: icon,
              )
              : FilledButton.icon(
                onPressed: connecting ? null : onPressed,
                style: FilledButton.styleFrom(
                  minimumSize: Size(ExampleTheme.minimumTargetSize(context), ExampleTheme.minimumTargetSize(context)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: playing ? Colors.redAccent.shade200 : ExampleTheme.primary,
                ),
                icon: icon,
                label: Text(label),
              ),
    );
  }
}

class LocalAudioControlButton extends StatelessWidget {
  const LocalAudioControlButton({
    Key? key,
    required this.enabled,
    required this.busy,
    required this.running,
    required this.onPressed,
  }) : _buttonKey = key,
       super(key: null);

  final Key? _buttonKey;
  final bool enabled;
  final bool busy;
  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: running,
      label: running ? '停止麦克风' : '启动麦克风',
      child: IconButton(
        key: _buttonKey,
        onPressed: enabled && !busy ? onPressed : null,
        tooltip: running ? '停止麦克风' : '启动麦克风',
        style: IconButton.styleFrom(
          minimumSize: Size(ExampleTheme.minimumTargetSize(context), ExampleTheme.minimumTargetSize(context)),
          foregroundColor: running ? Colors.orangeAccent.shade100 : Colors.white,
        ),
        icon:
            busy
                ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(running ? Colors.white : ExampleTheme.primary),
                  ),
                )
                : Icon(running ? Icons.mic_off_rounded : Icons.mic_rounded),
      ),
    );
  }
}

class AudioOutputVolumeButton extends StatelessWidget {
  const AudioOutputVolumeButton({super.key, required this.enabled, required this.muted, required this.onPressed});

  final bool enabled;
  final bool muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: muted,
      label: muted ? '恢复声音' : '静音',
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        tooltip: muted ? '恢复声音' : '静音',
        style: IconButton.styleFrom(
          minimumSize: Size(ExampleTheme.minimumTargetSize(context), ExampleTheme.minimumTargetSize(context)),
          foregroundColor: muted ? Colors.orangeAccent.shade100 : Colors.white,
        ),
        icon: Icon(muted ? Icons.volume_up_rounded : Icons.volume_off_rounded),
      ),
    );
  }
}

class MediaTargetStatus extends StatelessWidget {
  const MediaTargetStatus({super.key, required this.targetLabel, required this.recording});

  final String targetLabel;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final String label = recording ? '$targetLabel · 录屏中' : targetLabel;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: recording ? Colors.orangeAccent.shade100 : Colors.white70,
          fontSize: 12,
          fontWeight: recording ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class MediaCaptureButtons extends StatelessWidget {
  const MediaCaptureButtons({
    super.key,
    required this.enabled,
    required this.recording,
    required this.recordingButtonKey,
    required this.snapshotButtonKey,
    required this.onToggleRecording,
    required this.onSnapshot,
  });

  final bool enabled;
  final bool recording;
  final Key recordingButtonKey;
  final Key snapshotButtonKey;
  final VoidCallback onToggleRecording;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    final String recordingLabel = recording ? '结束录屏' : '开始录屏';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          button: true,
          toggled: recording,
          label: recordingLabel,
          child: IconButton(
            key: recordingButtonKey,
            tooltip: recordingLabel,
            onPressed: enabled ? onToggleRecording : null,
            icon: Icon(recording ? Icons.stop_circle_outlined : Icons.fiber_manual_record),
          ),
        ),
        Semantics(
          button: true,
          label: '截图',
          child: IconButton(
            key: snapshotButtonKey,
            tooltip: '截图',
            onPressed: enabled ? onSnapshot : null,
            icon: const Icon(Icons.camera_alt_outlined),
          ),
        ),
      ],
    );
  }
}

class PlayerControlPanel extends StatelessWidget {
  const PlayerControlPanel({
    super.key,
    required this.connecting,
    required this.playing,
    required this.audioOutputEnabled,
    required this.audioMuted,
    required this.localAudioControl,
    required this.selectedVideoPosition,
    required this.selectedVideoStreamId,
    required this.mediaBusy,
    required this.recording,
    required this.canExecuteMedia,
    required this.onToggleDownlink,
    required this.onToggleAudioOutput,
    required this.onToggleRecording,
    required this.onSnapshot,
    required this.onGallery,
    required this.onMediaUnavailable,
  });

  final bool connecting;
  final bool playing;
  final bool audioOutputEnabled;
  final bool audioMuted;
  final Widget localAudioControl;
  final int? selectedVideoPosition;
  final int? selectedVideoStreamId;
  final bool mediaBusy;
  final bool recording;
  final bool Function() canExecuteMedia;
  final VoidCallback onToggleDownlink;
  final VoidCallback onToggleAudioOutput;
  final VoidCallback onToggleRecording;
  final VoidCallback onSnapshot;
  final VoidCallback onGallery;
  final VoidCallback onMediaUnavailable;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 720;
        final bool mediaEnabled = playing && !mediaBusy;
        final String? mediaTarget =
            selectedVideoStreamId == null
                ? null
                : '视频 ${selectedVideoPosition ?? 1} · Stream ID $selectedVideoStreamId';
        final Widget coreControls = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DownlinkControlButton(
              connecting: connecting,
              playing: playing,
              compact: !wide,
              onPressed: onToggleDownlink,
            ),
            const SizedBox(width: 4),
            AudioOutputVolumeButton(
              key: DemoWidgetKeys.playerAudioVolumeButton,
              enabled: audioOutputEnabled,
              muted: audioMuted,
              onPressed: onToggleAudioOutput,
            ),
            localAudioControl,
          ],
        );
        final Widget? captureControls =
            mediaTarget == null
                ? null
                : MediaCaptureButtons(
                  enabled: mediaEnabled,
                  recording: recording,
                  recordingButtonKey: DemoWidgetKeys.playerRecordingButton,
                  snapshotButtonKey: DemoWidgetKeys.playerSnapshotButton,
                  onToggleRecording: onToggleRecording,
                  onSnapshot: onSnapshot,
                );
        final Widget? more =
            mediaTarget == null
                ? null
                : PlayerMediaMenuButton(
                  enabled: mediaEnabled,
                  statusLabel:
                      mediaEnabled
                          ? '$mediaTarget · 可保存到相册'
                          : playing
                          ? '媒体操作进行中'
                          : '播放停止 · 媒体操作不可用',
                  canExecute: canExecuteMedia,
                  onUnavailable: onMediaUnavailable,
                  onGallery: onGallery,
                );
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: DemoWidgetKeys.playerControlSurface,
            constraints: const BoxConstraints(maxWidth: 760),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: ExampleTheme.isAppleProfile(context) ? 4 : 8),
            decoration: ExampleTheme.videoPanelDecoration,
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: Size.square(ExampleTheme.minimumTargetSize(context)),
                ),
              ),
              child:
                  wide
                      ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          coreControls,
                          if (mediaTarget != null) ...<Widget>[
                            const VerticalDivider(width: 16, indent: 8, endIndent: 8),
                            Flexible(
                              child: MediaTargetStatus(
                                key: DemoWidgetKeys.playerMediaTarget,
                                targetLabel: mediaTarget,
                                recording: recording,
                              ),
                            ),
                            captureControls!,
                            more!,
                          ],
                        ],
                      )
                      : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (mediaTarget != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                              child: MediaTargetStatus(
                                key: DemoWidgetKeys.playerMediaTarget,
                                targetLabel: mediaTarget,
                                recording: recording,
                              ),
                            ),
                          coreControls,
                          if (captureControls != null || more != null)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[if (captureControls != null) captureControls, if (more != null) more],
                            ),
                        ],
                      ),
            ),
          ),
        );
      },
    );
  }
}

enum PlayerMediaAction { gallery }

class PlayerMediaMenuButton extends StatefulWidget {
  const PlayerMediaMenuButton({
    super.key,
    required this.enabled,
    required this.statusLabel,
    required this.canExecute,
    required this.onUnavailable,
    required this.onGallery,
    this.focusNode,
  });

  final bool enabled;
  final String statusLabel;
  final bool Function() canExecute;
  final VoidCallback onUnavailable;
  final VoidCallback onGallery;
  final FocusNode? focusNode;

  @override
  State<PlayerMediaMenuButton> createState() => _PlayerMediaMenuButtonState();
}

class _PlayerMediaMenuButtonState extends State<PlayerMediaMenuButton> {
  final FocusNode _fallbackFocusNode = FocusNode(debugLabel: 'player-media-more');
  bool _menuOpen = false;

  FocusNode get _focusNode => widget.focusNode ?? _fallbackFocusNode;

  @override
  void didUpdateWidget(PlayerMediaMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_menuOpen && oldWidget.enabled && !widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !_menuOpen) return;
        _menuOpen = false;
        await Navigator.of(context).maybePop();
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _fallbackFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      child: PopupMenuButton<PlayerMediaAction>(
        key: DemoWidgetKeys.playerMoreButton,
        tooltip: '更多媒体操作',
        icon: const Icon(Icons.more_horiz_rounded),
        onOpened: () => _menuOpen = true,
        onCanceled: _restoreFocus,
        onSelected: (PlayerMediaAction action) {
          _menuOpen = false;
          _restoreFocus();
          if (!widget.canExecute()) {
            widget.onUnavailable();
            return;
          }
          widget.onGallery();
        },
        itemBuilder:
            (BuildContext context) => <PopupMenuEntry<PlayerMediaAction>>[
              PopupMenuItem<PlayerMediaAction>(enabled: false, child: Text(widget.statusLabel)),
              PopupMenuItem<PlayerMediaAction>(
                key: DemoWidgetKeys.playerGalleryButton,
                value: PlayerMediaAction.gallery,
                enabled: widget.enabled,
                child: const Text('保存到系统相册'),
              ),
            ],
      ),
    );
  }

  void _restoreFocus() {
    _menuOpen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }
}
