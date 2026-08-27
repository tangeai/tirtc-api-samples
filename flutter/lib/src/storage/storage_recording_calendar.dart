import 'package:flutter/material.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../app_theme.dart';
import '../demo_widget_keys.dart';

final class DemoCloudStorageRecordingCalendar extends StatelessWidget {
  const DemoCloudStorageRecordingCalendar({
    super.key,
    required this.visibleMonth,
    required this.selectedDate,
    required this.today,
    required this.days,
    required this.loading,
    required this.errorCode,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onRetry,
    required this.onSelectDay,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final List<TiCloudStorageRecordingDay> days;
  final bool loading;
  final int? errorCode;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onRetry;
  final ValueChanged<int> onSelectDay;

  @override
  Widget build(BuildContext context) {
    if (errorCode != null && errorCode != 0) {
      return SizedBox(
        height: 290,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('月份查询失败 · ${TiCloudStorage.errorToString(errorCode!)} ($errorCode)'),
              const SizedBox(height: 12),
              FilledButton(
                key: DemoWidgetKeys.cloudStorageCalendarRetryButton,
                onPressed: onRetry,
                child: const Text('重试月份'),
              ),
            ],
          ),
        ),
      );
    }
    final int firstWeekday = DateTime.utc(visibleMonth.year, visibleMonth.month, 1).weekday % 7;
    final int dayCount = DateTime.utc(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final Map<String, bool> availability = <String, bool>{
      for (final TiCloudStorageRecordingDay day in days) day.date: day.hasRecording,
    };
    final String month = _monthText(visibleMonth);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                key: DemoWidgetKeys.cloudStorageCalendarMonthPrevious,
                tooltip: '上个月',
                onPressed: loading ? null : onPreviousMonth,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${visibleMonth.year} 年 ${visibleMonth.month} 月',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: DemoWidgetKeys.cloudStorageCalendarMonthNext,
                tooltip: '下个月',
                onPressed: loading ? null : onNextMonth,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              for (final String weekday in <String>['日', '一', '二', '三', '四', '五', '六'])
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(weekday, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 46,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: 42,
            itemBuilder: (BuildContext context, int index) {
              final int dayNumber = index - firstWeekday + 1;
              if (dayNumber < 1 || dayNumber > dayCount) return const SizedBox.shrink();
              final String date = _dateText(visibleMonth.year, visibleMonth.month, dayNumber);
              final bool hasRecording = availability[date] == true;
              final bool enabled = !loading && hasRecording;
              final bool selected =
                  selectedDate.year == visibleMonth.year &&
                  selectedDate.month == visibleMonth.month &&
                  selectedDate.day == dayNumber;
              final bool isToday =
                  today.year == visibleMonth.year && today.month == visibleMonth.month && today.day == dayNumber;
              final Color foreground =
                  selected
                      ? Colors.white
                      : hasRecording
                      ? ExampleTheme.primary
                      : Theme.of(context).disabledColor;
              return Semantics(
                button: true,
                enabled: enabled,
                selected: selected,
                label: '$date，${hasRecording ? '有录像' : '无录像'}${isToday ? '，今天' : ''}',
                child: InkWell(
                  key: DemoWidgetKeys.cloudStorageCalendarDay(date),
                  borderRadius: BorderRadius.circular(12),
                  onTap: enabled ? () => onSelectDay(dayNumber) : null,
                  child: AnimatedContainer(
                    duration:
                        MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 140),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? ExampleTheme.primary
                              : hasRecording
                              ? ExampleTheme.primary.withAlpha(24)
                              : Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(150),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isToday ? Theme.of(context).colorScheme.secondary : Colors.transparent,
                        width: isToday ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text('$dayNumber', style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
                        Text(
                          loading
                              ? '加载'
                              : hasRecording
                              ? '有录像'
                              : '无录像',
                          style: TextStyle(color: foreground, fontSize: 8),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          Semantics(
            liveRegion: true,
            child: Text(
              loading ? '$month 正在加载' : '${availability.values.where((bool value) => value).length} 天有录像，灰色日期不可选择',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }

  static String _dateText(int year, int month, int day) =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  static String _monthText(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';
}
