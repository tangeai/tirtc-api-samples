import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'downlink_center_loading.dart';

class PlayerCommandButton extends StatelessWidget {
  const PlayerCommandButton({
    super.key,
    required this.onOpenCommands,
  });

  final VoidCallback onOpenCommands;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: ExampleTheme.primary,
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(92, 28),
          side: const BorderSide(color: ExampleTheme.primary, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onOpenCommands,
        child: const Text(
          '发送命令',
          style: TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class PlayerLogUploadButton extends StatelessWidget {
  const PlayerLogUploadButton({
    super.key,
    required this.uploadingLogs,
    required this.onUploadLogs,
  });

  final bool uploadingLogs;
  final VoidCallback onUploadLogs;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: ExampleTheme.primary,
          backgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          minimumSize: const Size(84, 28),
          side: const BorderSide(
            color: ExampleTheme.primary,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                  valueColor: AlwaysStoppedAnimation<Color>(
                    ExampleTheme.primary.withAlpha(214),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              uploadingLogs ? '上传中' : '上传日志',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class DownlinkVideoStage extends StatelessWidget {
  const DownlinkVideoStage({
    super.key,
    required this.videoView,
    required this.showStageOverlay,
    required this.stageStatusLabel,
    required this.indicatorMode,
  });

  final Widget videoView;
  final bool showStageOverlay;
  final String stageStatusLabel;
  final DownlinkCenterIndicatorMode indicatorMode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: ExampleTheme.videoBackground),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(child: videoView),
          if (showStageOverlay)
            Center(
              child: DownlinkCenterLoading(
                label: stageStatusLabel,
                mode: indicatorMode,
              ),
            ),
        ],
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
            colors: <Color>[
              Colors.black.withAlpha(117),
              Colors.transparent,
              Colors.black.withAlpha(153),
            ],
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
  });

  final bool connecting;
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: connecting ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        backgroundColor: playing ? Colors.redAccent.shade200 : ExampleTheme.primary,
      ),
      icon: connecting
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(
              playing ? Icons.stop_circle_outlined : Icons.play_circle_fill_rounded,
            ),
      label: Text(
        connecting ? '连接中' : (playing ? '停止播放' : '开始播放'),
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
  })  : _buttonKey = key,
        super(key: null);

  final Key? _buttonKey;
  final bool enabled;
  final bool busy;
  final bool running;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      key: _buttonKey,
      onPressed: enabled && !busy ? onPressed : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        backgroundColor: running ? Colors.orangeAccent.shade700 : ExampleTheme.surface,
        foregroundColor: running ? Colors.white : ExampleTheme.primary,
      ),
      icon: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  running ? Colors.white : ExampleTheme.primary,
                ),
              ),
            )
          : Icon(running ? Icons.mic_off_rounded : Icons.mic_rounded),
      label: Text(running ? '停止麦克风' : '启动麦克风'),
    );
  }
}

class AudioOutputVolumeButton extends StatelessWidget {
  const AudioOutputVolumeButton({
    super.key,
    required this.enabled,
    required this.muted,
    required this.onPressed,
  });

  final bool enabled;
  final bool muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        backgroundColor: muted ? Colors.orangeAccent.shade700 : ExampleTheme.surface,
        foregroundColor: muted ? Colors.white : ExampleTheme.primary,
      ),
      icon: Icon(muted ? Icons.volume_up_rounded : Icons.volume_off_rounded),
      label: Text(muted ? '恢复声音' : '静音'),
    );
  }
}
