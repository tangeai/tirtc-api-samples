import React, {useMemo, useState} from 'react';
import {Alert, Pressable, StyleSheet, Text, View} from 'react-native';
import {automationTestId, exampleTheme} from './ExampleUi';
import {
  downlinkMetricsOverlayRows,
  type DownlinkMetricsOverlayModel,
  type DownlinkMetricsOverlayRow,
} from './ExampleDownlinkMetricsOverlayModel';

const STATS_PANEL_MAX_WIDTH = 430;

export const downlinkMetricsExplanationContent =
  '【连接耗时】：从点击开始连接，到 runtime 确认连接成功的时间。' +
  '只表示连接建立用了多久，不表示画面已经出来。\n\n' +
  '【首帧等待】：连接成功后，到第一个视频帧真正显示成功的等待时间。' +
  '如果只能拿到从点击连接开始计算的首帧时间，面板会明确显示为首帧总耗时。\n\n' +
  '【什么时候开始统计卡顿】：第一个视频帧真正显示成功后，才开始统计本次播放的卡顿。' +
  '连接中、等首帧、页面看不见、画面承载区域不可用、停止播放后的空窗，都不算卡顿。\n\n' +
  '【如何定义一次卡顿】：播放已经开始后，SDK 会观察视频帧成功显示的间隔。' +
  '先用最近几次正常显示的帧间隔估出“正常一帧应该隔多久”。' +
  '如果下一帧的显示间隔超过这个正常间隔的 3 倍，超过 3 倍的多出来时间才记为卡顿。' +
  '连续的一段停顿算 1 次；恢复显示后，如果后面又停住，再算下一次。\n\n' +
  '【本次播放卡顿次数】：从开始播放到现在，累计发生过多少段卡顿。' +
  '连续停住又恢复，算 1 次；恢复后再次停住，才算新的一次。\n\n' +
  '【本次播放最长卡顿】：本次播放里，单次卡顿中被计入的最长时长。' +
  '它用于判断最严重的一次停顿有多长。\n\n' +
  '【接收】：码率、视频接收 FPS 和音频 PPS 来自 runtime 最近一个已闭合 5 秒窗口。' +
  '这里只表达下行输入侧事实，不混入解码、渲染或音频输出回调。\n\n' +
  '【音频卡顿】：音频不用“帧率”判断体验。' +
  '这里展示最近窗口内，系统输出回调取不到可播放数据而产生的停滞次数和最长停滞。\n\n' +
  '【缓冲长度】：来自 runtime 最近一个已闭合 5 秒窗口。' +
  '它表示远端音视频数据在本机下行队列里等待被消费的大致时长。' +
  '调试日志仍保留更细分的内部阶段数据，面板只显示最常用的本地待消费长度。';

export function DownlinkMetricsOverlay({metrics}: {metrics: DownlinkMetricsOverlayModel}) {
  const [expanded, setExpanded] = useState(true);
  const rows = useMemo(() => downlinkMetricsOverlayRows(metrics), [metrics]);
  if (!expanded) {
    return (
      <View style={styles.collapsedWrap}>
        <Pressable
          accessible
          accessibilityRole="button"
          accessibilityLabel="TiRTC Downlink Metrics Expand"
          testID={automationTestId('TiRTC Downlink Metrics Expand')}
          onPress={() => setExpanded(true)}
          style={styles.collapsedButton}>
          <Text style={styles.collapsedIcon}>▥</Text>
          <Text style={styles.collapsedText}>即时统计</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View
      accessible
      accessibilityLabel="TiRTC Player Diagnostics"
      testID={automationTestId('TiRTC Player Diagnostics')}
      style={styles.panel}>
      <View style={styles.header}>
        <Text style={styles.title}>即时统计</Text>
        <Pressable
          accessible
          accessibilityRole="button"
          accessibilityLabel="TiRTC Downlink Metrics Help"
          testID={automationTestId('TiRTC Downlink Metrics Help')}
          onPress={() => Alert.alert('指标说明', downlinkMetricsExplanationContent)}
          style={styles.helpButton}>
          <Text style={styles.helpText}>?</Text>
        </Pressable>
        <Pressable
          accessible
          accessibilityRole="button"
          accessibilityLabel="TiRTC Downlink Metrics Collapse"
          testID={automationTestId('TiRTC Downlink Metrics Collapse')}
          onPress={() => setExpanded(false)}
          style={styles.collapseButton}>
          <Text style={styles.collapseIcon}>⌃</Text>
          <Text style={styles.collapseText}>收起</Text>
        </Pressable>
      </View>
      <View style={styles.rows}>
        {rows.map((row) => (
          <MetricLine key={row.rowKey} row={row} />
        ))}
      </View>
    </View>
  );
}

function MetricLine({row}: {row: DownlinkMetricsOverlayRow}) {
  return (
    <Text
      numberOfLines={1}
      ellipsizeMode="tail"
      testID={automationTestId(`TiRTC Downlink Metrics ${row.label}`)}
      style={styles.metricLine}>
      <Text style={styles.metricLabel}>{row.label}：</Text>
      <Text style={styles.metricValue}>{row.value}</Text>
    </Text>
  );
}

const styles = StyleSheet.create({
  panel: {
    width: '100%',
    maxWidth: STATS_PANEL_MAX_WIDTH,
    alignSelf: 'center',
    borderRadius: 20,
    backgroundColor: '#FFFFFF',
    paddingHorizontal: 12,
    paddingVertical: 8,
    shadowColor: '#000000',
    shadowOpacity: 0.16,
    shadowRadius: 14,
    shadowOffset: {width: 0, height: 5},
    elevation: 8,
  },
  header: {
    minHeight: 22,
    flexDirection: 'row',
    alignItems: 'center',
  },
  title: {
    flex: 1,
    color: 'rgba(17,17,17,0.87)',
    fontSize: 11,
    fontWeight: '900',
    lineHeight: 13,
  },
  helpButton: {
    width: 22,
    height: 22,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
  },
  helpText: {
    color: exampleTheme.primary,
    fontSize: 15,
    fontWeight: '800',
    lineHeight: 17,
  },
  collapseButton: {
    height: 18,
    borderRadius: 12,
    backgroundColor: '#4F86D9',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 8,
    marginLeft: 6,
  },
  collapseIcon: {
    color: '#FFFFFF',
    fontSize: 12,
    fontWeight: '800',
    lineHeight: 14,
    marginRight: 2,
  },
  collapseText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '800',
    lineHeight: 12,
  },
  rows: {
    marginTop: 6,
  },
  metricLine: {
    marginBottom: 4,
    lineHeight: 12,
  },
  metricLabel: {
    color: '#659287',
    fontSize: 10,
    fontWeight: '900',
    lineHeight: 12,
  },
  metricValue: {
    color: 'rgba(17,17,17,0.80)',
    fontSize: 10,
    fontWeight: '600',
    lineHeight: 12,
  },
  collapsedWrap: {
    alignItems: 'center',
  },
  collapsedButton: {
    height: 26,
    borderRadius: 18,
    backgroundColor: '#FFFFFF',
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    shadowColor: '#000000',
    shadowOpacity: 0.14,
    shadowRadius: 10,
    shadowOffset: {width: 0, height: 3},
    elevation: 7,
  },
  collapsedIcon: {
    color: '#4F86D9',
    fontSize: 14,
    fontWeight: '900',
    lineHeight: 15,
    marginRight: 5,
  },
  collapsedText: {
    color: 'rgba(17,17,17,0.87)',
    fontSize: 10,
    fontWeight: '800',
    lineHeight: 12,
  },
});
