import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../demo_widget_keys.dart';
import 'downlink_metrics_overlay_model.dart';

const double _statsPanelMaxWidth = 430;

const String downlinkMetricsExplanationContent =
    '【连接耗时】：从点击开始连接，到 runtime 确认连接成功的时间。'
    '只表示连接建立用了多久，不表示画面已经出来。\n\n'
    '【首帧等待】：连接成功后，到第一个视频帧真正显示成功的等待时间。'
    '如果只能拿到从点击连接开始计算的首帧时间，面板会明确显示为首帧总耗时。\n\n'
    '【什么时候开始统计卡顿】：第一个视频帧真正显示成功后，才开始统计本次播放的卡顿。'
    '连接中、等首帧、页面看不见、画面承载区域不可用、停止播放后的空窗，都不算卡顿。\n\n'
    '【如何定义一次卡顿】：播放已经开始后，SDK 会观察视频帧成功显示的间隔。'
    '先用最近几次正常显示的帧间隔估出“正常一帧应该隔多久”。'
    '如果下一帧的显示间隔超过这个正常间隔的 3 倍，超过 3 倍的多出来时间才记为卡顿。'
    '连续的一段停顿算 1 次；恢复显示后，如果后面又停住，再算下一次。\n\n'
    '【本次播放卡顿次数】：从开始播放到现在，累计发生过多少段卡顿。'
    '连续停住又恢复，算 1 次；恢复后再次停住，才算新的一次。\n\n'
    '【本次播放最长卡顿】：本次播放里，单次卡顿中被计入的最长时长。'
    '它用于判断最严重的一次停顿有多长。\n\n'
    '【接收】：码率、视频接收 FPS 和音频 PPS 来自 runtime 最近一个已闭合 5 秒窗口。'
    '这里只表达下行输入侧事实，不混入解码、渲染或音频输出回调。\n\n'
    '【音频卡顿】：音频不用“帧率”判断体验。'
    '这里展示最近窗口内，系统输出回调取不到可播放数据而产生的停滞次数和最长停滞。\n\n'
    '【估算延迟】：来自 runtime 当前输出延迟估算，综合最近到达帧的单向传输延迟和本地待输出缓冲时长。'
    '面板按秒刷新；还没有有效数据时显示“--”。';

class DownlinkMetricsOverlay extends StatefulWidget {
  const DownlinkMetricsOverlay({super.key, required this.metrics, required this.onShowExplanation});

  final DownlinkMetricsOverlayModel metrics;
  final VoidCallback onShowExplanation;

  @override
  State<DownlinkMetricsOverlay> createState() => _DownlinkMetricsOverlayState();
}

class _DownlinkMetricsOverlayState extends State<DownlinkMetricsOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return Align(
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: DemoWidgetKeys.downlinkMetricsStatsExpandAction,
            borderRadius: BorderRadius.circular(ExampleTheme.radiusMedium),
            onTap: () {
              setState(() {
                _expanded = true;
              });
            },
            child: Container(
              constraints: BoxConstraints(minHeight: ExampleTheme.minimumTargetSize(context)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(ExampleTheme.radiusMedium),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Colors.black.withAlpha(35), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.bar_chart_rounded, size: 15, color: Color(0xFF4F86D9)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      _summaryText(widget.metrics),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xDD111111),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final DownlinkMetricsOverlayModel metrics = widget.metrics;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _statsPanelMaxWidth),
        child: IgnorePointer(
          ignoring: false,
          child: Container(
            key: DemoWidgetKeys.downlinkMetricsStatsPanel,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ExampleTheme.radiusLarge),
              boxShadow: <BoxShadow>[
                BoxShadow(color: Colors.black.withAlpha(40), blurRadius: 14, offset: const Offset(0, 5)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '即时统计',
                        style: TextStyle(
                          color: Color(0xDD111111),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '指标说明',
                      onPressed: widget.onShowExplanation,
                      style: IconButton.styleFrom(
                        foregroundColor: ExampleTheme.primary,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.square(ExampleTheme.minimumTargetSize(context)),
                      ),
                      icon: const Icon(Icons.help_outline_rounded, size: 16),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      key: DemoWidgetKeys.downlinkMetricsStatsCollapseAction,
                      onPressed: () {
                        setState(() {
                          _expanded = false;
                        });
                      },
                      tooltip: '收起即时统计',
                      style: IconButton.styleFrom(minimumSize: Size.square(ExampleTheme.minimumTargetSize(context))),
                      icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final DownlinkMetricsOverlayRow row in metrics.overlayRows)
                  _MetricLine(key: row.widgetKey, label: row.label, value: row.value),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _summaryText(DownlinkMetricsOverlayModel metrics) {
    final String fps = metrics.videoRenderFps == null ? '--' : metrics.videoRenderFps!.toStringAsFixed(1);
    final String latency =
        metrics.videoEstimatedOutputLatencyMs == null ? '--' : '${metrics.videoEstimatedOutputLatencyMs} ms';
    final String stutter = metrics.videoStutterCount == null ? '--' : '${metrics.videoStutterCount} 次';
    return '视频 $fps fps · 延迟 $latency · 卡顿 $stutter';
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '$label：',
              style: const TextStyle(color: Color(0xFF35675C), fontSize: 12, fontWeight: FontWeight.w800, height: 1.3),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Color(0xDD111111), fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
