import 'package:flutter/material.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../app_theme.dart';
import '../demo_widget_keys.dart';
import 'player_page_widgets.dart';

class CloudStoragePlaybackConsole extends StatelessWidget {
  const CloudStoragePlaybackConsole({
    super.key,
    required this.hasRange,
    required this.rangeStart,
    required this.rangeEnd,
    required this.current,
    required this.currentLabel,
    required this.endLabel,
    required this.playing,
    required this.paused,
    required this.audioEnabled,
    required this.audioMuted,
    required this.speed,
    required this.selectedVideoChannelId,
    this.selectedVideoPosition,
    required this.mediaBusy,
    required this.recording,
    required this.onSeekPreview,
    required this.onSeekEnd,
    required this.onTogglePause,
    required this.onToggleVolume,
    required this.onSetSpeed,
    required this.onToggleRecording,
    required this.onSnapshot,
  });

  final bool hasRange;
  final double rangeStart;
  final double rangeEnd;
  final double current;
  final String currentLabel;
  final String endLabel;
  final bool playing;
  final bool paused;
  final bool audioEnabled;
  final bool audioMuted;
  final TiCloudStorageReplaySpeed speed;
  final int? selectedVideoChannelId;
  final int? selectedVideoPosition;
  final bool mediaBusy;
  final bool recording;
  final ValueChanged<double> onSeekPreview;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onTogglePause;
  final VoidCallback onToggleVolume;
  final ValueChanged<TiCloudStorageReplaySpeed> onSetSpeed;
  final VoidCallback onToggleRecording;
  final VoidCallback onSnapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= ExampleTheme.compactBreakpoint;
        final bool showPrimaryLabel = constraints.maxWidth >= 720;
        final bool appleProfile = ExampleTheme.isAppleProfile(context);
        final Widget controls = _controls(context, showPrimaryLabel: showPrimaryLabel, compact: !wide);
        final String? mediaTarget =
            selectedVideoChannelId == null
                ? null
                : '视频 ${selectedVideoPosition ?? 1} · Channel ID $selectedVideoChannelId';
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: DemoWidgetKeys.cloudStorageControlSurface,
            constraints: const BoxConstraints(maxWidth: 860),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: appleProfile ? 4 : 8),
            decoration: ExampleTheme.videoPanelDecoration,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (mediaTarget != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                    child: MediaTargetStatus(
                      key: DemoWidgetKeys.cloudStorageMediaTarget,
                      targetLabel: mediaTarget,
                      recording: recording,
                    ),
                  ),
                if (wide)
                  SizedBox(
                    height: appleProfile ? 44 : 56,
                    child: Row(
                      children: <Widget>[
                        if (hasRange) Expanded(child: _seekRow(compact: false)),
                        if (hasRange) const SizedBox(width: 8),
                        controls,
                      ],
                    ),
                  )
                else ...<Widget>[
                  if (hasRange) SizedBox(height: appleProfile ? 44 : 48, child: _seekRow(compact: true)),
                  controls,
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _seekRow({required bool compact}) {
    final double safeEnd = rangeEnd > rangeStart ? rangeEnd : rangeStart + 1;
    final Widget slider = Slider(
      key: DemoWidgetKeys.cloudStorageSeekSlider,
      min: rangeStart,
      max: safeEnd,
      value: current.clamp(rangeStart, safeEnd),
      onChanged: playing ? onSeekPreview : null,
      onChangeEnd: playing ? onSeekEnd : null,
    );
    if (compact) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          slider,
          IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    currentLabel,
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1),
                  ),
                  Text(endLabel, maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Text(currentLabel, maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1)),
        Expanded(child: slider),
        Text(endLabel, maxLines: 1, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1)),
      ],
    );
  }

  Widget _controls(BuildContext context, {required bool showPrimaryLabel, required bool compact}) {
    final bool mediaEnabled = playing && !mediaBusy && selectedVideoChannelId != null;
    final double target = ExampleTheme.minimumTargetSize(context);
    final Widget? captureControls =
        selectedVideoChannelId == null
            ? null
            : MediaCaptureButtons(
              enabled: mediaEnabled,
              recording: recording,
              recordingButtonKey: DemoWidgetKeys.cloudStorageRecordingButton,
              snapshotButtonKey: DemoWidgetKeys.cloudStorageSnapshotButton,
              onToggleRecording: onToggleRecording,
              onSnapshot: onSnapshot,
            );
    final List<Widget> primaryControls = <Widget>[
      Tooltip(
        message: paused ? '继续播放' : '暂停播放',
        child: Semantics(
          key: DemoWidgetKeys.cloudStoragePauseButton,
          button: true,
          toggled: paused,
          label: paused ? '继续播放' : '暂停播放',
          child:
              showPrimaryLabel
                  ? FilledButton.icon(
                    onPressed: playing ? onTogglePause : null,
                    style: FilledButton.styleFrom(
                      minimumSize: Size(48, target),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: Icon(paused ? Icons.play_circle_fill_rounded : Icons.pause_circle_filled_rounded),
                    label: Text(paused ? '继续播放' : '暂停播放'),
                  )
                  : IconButton.filled(
                    onPressed: playing ? onTogglePause : null,
                    icon: Icon(paused ? Icons.play_circle_fill_rounded : Icons.pause_circle_filled_rounded),
                  ),
        ),
      ),
      AudioOutputVolumeButton(
        key: DemoWidgetKeys.cloudStorageAudioVolumeButton,
        enabled: audioEnabled,
        muted: audioMuted,
        onPressed: onToggleVolume,
      ),
      DropdownButtonHideUnderline(
        child: DropdownButton<TiCloudStorageReplaySpeed>(
          key: DemoWidgetKeys.cloudStorageSpeedSelector,
          value: speed,
          dropdownColor: ExampleTheme.videoBackground,
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white),
          items: TiCloudStorageReplaySpeed.values
              .map(
                (TiCloudStorageReplaySpeed value) =>
                    DropdownMenuItem<TiCloudStorageReplaySpeed>(value: value, child: Text(_speedLabel(value))),
              )
              .toList(growable: false),
          onChanged:
              !playing
                  ? null
                  : (TiCloudStorageReplaySpeed? value) {
                    if (value != null) onSetSpeed(value);
                  },
        ),
      ),
    ];
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Colors.white, minimumSize: Size.square(target)),
      ),
      child:
          compact
              ? Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(mainAxisSize: MainAxisSize.min, children: primaryControls),
                  if (captureControls != null) captureControls,
                ],
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[...primaryControls, if (captureControls != null) captureControls],
              ),
    );
  }

  String _speedLabel(TiCloudStorageReplaySpeed value) => switch (value) {
    TiCloudStorageReplaySpeed.x0_125 => '1/8×',
    TiCloudStorageReplaySpeed.x0_25 => '1/4×',
    TiCloudStorageReplaySpeed.x0_5 => '1/2×',
    TiCloudStorageReplaySpeed.x1 => '1×',
    TiCloudStorageReplaySpeed.x2 => '2×',
    TiCloudStorageReplaySpeed.x4 => '4×',
    TiCloudStorageReplaySpeed.x8 => '8×',
  };
}

class CloudStoragePlaybackViewport extends StatelessWidget {
  const CloudStoragePlaybackViewport({super.key, required this.console});

  final Widget console;

  @override
  Widget build(BuildContext context) {
    final bool appleProfile = ExampleTheme.isAppleProfile(context);
    return SafeArea(
      top: false,
      child: Padding(
        key: DemoWidgetKeys.cloudStoragePlaybackViewport,
        padding: EdgeInsets.fromLTRB(20, appleProfile ? 0 : 16, 20, appleProfile ? 0 : 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[const Spacer(), console]),
      ),
    );
  }
}
