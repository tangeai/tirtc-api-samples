import type { common } from '@kit.AbilityKit';
import {
  TiRtcLogging,
  TiCloudStorage,
  TiCloudStorageRecordingRange,
  TiCloudStorageReplaySpeed,
  TiCloudStorageVideoOutputView,
  TI_CLOUD_STORAGE_ERROR_OK,
} from 'tirtc/Index';
import {
  DEFAULT_AUDIO_STREAM_ID,
  DEFAULT_VIDEO_STREAM_ID,
  PLAYER_BOTTOM_PADDING,
  PLAYER_TOP_PADDING,
} from './ExampleConfig';
import { PlayerStageOverlay } from './ExamplePlayerChrome';
import { saveMediaFileToGallery } from './ExampleMediaGallery';
import { TiCloudStorageExampleFlow, TiCloudStorageExampleFlowListener } from './TiCloudStorageExampleFlow';

const NOTICE_AUTO_HIDE_MS: number = 3000;

function padCloudStorageClock(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function currentCloudStorageDateText(): string {
  const now = new Date(Date.now() + 8 * 60 * 60 * 1000);
  return `${now.getUTCFullYear()}-${padCloudStorageClock(now.getUTCMonth() + 1)}-${padCloudStorageClock(now.getUTCDate())}`;
}

function newestFirstRecordingRanges(
  ranges: ReadonlyArray<TiCloudStorageRecordingRange>,
): Array<TiCloudStorageRecordingRange> {
  const sorted: Array<TiCloudStorageRecordingRange> = [];
  ranges.forEach((range: TiCloudStorageRecordingRange): void => {
    sorted.push(range);
  });
  sorted.sort((left: TiCloudStorageRecordingRange, right: TiCloudStorageRecordingRange): number => {
    const startOrder = right.startTimeMs - left.startTimeMs;
    return startOrder !== 0 ? startOrder : right.endTimeMs - left.endTimeMs;
  });
  return sorted;
}

class CloudStorageDayBounds {
  readonly startTimeMs: number;
  readonly endTimeMs: number;

  constructor(
    startTimeMs: number,
    endTimeMs: number,
  ) {
    this.startTimeMs = startTimeMs;
    this.endTimeMs = endTimeMs;
  }
}

@Component
export struct TiCloudStorageExamplePage {
  @Prop appId: string = '';
  @Prop endpoint: string = '';
  @Prop token: string = '';
  @Prop audioChannelId: number = DEFAULT_AUDIO_STREAM_ID;
  @Prop videoChannelId: number = DEFAULT_VIDEO_STREAM_ID;
  @Prop consoleLogEnabled: boolean = false;
  onBack: () => void = () => {};
  @State private notice: string = '';
  @State private flowReady: boolean = false;
  @State private querying: boolean = false;
  @State private sheetVisible: boolean = false;
  @State private calendarVisible: boolean = true;
  @State private ranges: Array<TiCloudStorageRecordingRange> = [];
  @State private selectedIndex: number = -1;
  @State private currentTimeMs: number = 0;
  @State private replayState: string = 'idle';
  @State private paused: boolean = false;
  @State private muted: boolean = false;
  @State private speedIndex: number = 3;
  @State private recording: boolean = false;
  @State private mediaBusy: boolean = false;
  @State private latestMediaKind: string = '';
  @State private exportProgress: number = -1;
  @State private uploadingLogs: boolean = false;
  @State private dateText: string = currentCloudStorageDateText();
  @State private visibleMonth: string = currentCloudStorageDateText().slice(0, 7);
  @State private recordingDays: Array<string> = [];
  @State private monthLoading: boolean = false;
  @State private monthFailed: boolean = false;
  @State private queryFailed: boolean = false;
  private flow?: TiCloudStorageExampleFlow;
  private closing?: Promise<void>;
  private active: boolean = false;
  private generation: number = 0;
  private dayQueryGeneration: number = 0;
  private monthQueryGeneration: number = 0;
  private noticeTimer: number = -1;

  aboutToAppear(): void {
    this.active = true;
    this.generation += 1;
    void this.initialize(this.generation);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.generation += 1;
    this.stopNoticeTimer();
    void this.closeFlow();
  }

  build() {
    Stack() {
      Column() {
        this.topBar()
        Stack() {
          Stack({ alignContent: Alignment.Center }) {
            if (this.flowReady && this.flow !== undefined) {
              TiCloudStorageVideoOutputView({
                output: this.flow!.videoOutput,
              })
            }
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#252525')
          if (this.showStageOverlay()) {
            Stack({ alignContent: Alignment.Center }) {
              PlayerStageOverlay({
                statusLabel: this.stageStatusLabel(),
                detailLabel: '',
              })
            }
            .width('100%')
            .height('100%')
          }
          Column() {
            if (this.replayState === 'rendering') {
              Row() {
                Blank()
                Text('播放中')
                  .id('tirtc_example_ti_cloud_storage_rendering_state')
                  .fontSize(12)
                  .fontColor('#FFFFFF')
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor('#75000000')
                  .borderRadius(16)
              }
              .width('100%')
              .margin({ top: 16 })
            }
            if (this.notice.length > 0) {
              Row() {
                Blank()
                Text(this.notice)
                  .id('tirtc_example_ti_cloud_storage_status')
                  .fontSize(13)
                  .fontColor('#FFFFFF')
                  .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                  .backgroundColor('#666666')
                  .borderRadius(18)
                  .constraintSize({ maxWidth: '80%' })
              }
              .width('100%')
              .margin({ top: 16 })
            }
            Blank()
            if (this.selectedRange() !== undefined) {
              this.seekPanel()
              Blank().height(12)
            }
            this.controls()
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20, bottom: PLAYER_BOTTOM_PADDING })
          .linearGradient({
            angle: 180,
            colors: [['#33000000', 0.0], ['#00000000', 0.45], ['#66000000', 1.0]],
          })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#252525')
        .id('tirtc_example_ti_cloud_storage_video_stage')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#252525')
      if (this.sheetVisible) {
        this.recordingsSheet()
      }
    }
    .id('tirtc_example_ti_cloud_storage_page')
    .width('100%')
    .height('100%')
    .backgroundColor('#FFF8E8')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private topBar() {
    Row() {
      Button('<')
        .id('tirtc_example_ti_cloud_storage_back_button')
        .width(42)
        .height(36)
        .fontSize(18)
        .fontColor('#659287')
        .backgroundColor('#00FFFFFF')
        .onClick((): void => {
          void this.backToCloudStorageEntry();
        })
      Text('云录像')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#659287')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button('选择录像')
        .id('tirtc_example_ti_cloud_storage_choose_button')
        .height(36)
        .fontSize(12)
        .fontColor(this.flowReady ? '#659287' : '#777777')
        .backgroundColor('#00FFFFFF')
        .border({ width: 1, color: this.flowReady ? '#659287' : '#777777', radius: 10 })
        .enabled(this.flowReady)
        .onClick((): void => {
          this.calendarVisible = this.ranges.length === 0;
          this.sheetVisible = true;
        })
      Blank().width(8)
      Button(this.uploadingLogs ? '上传中' : '上传日志')
        .id('tirtc_example_ti_cloud_storage_log_upload_button')
        .height(36)
        .fontSize(12)
        .fontColor(this.flowReady && !this.uploadingLogs ? '#659287' : '#777777')
        .backgroundColor('#00FFFFFF')
        .border({
          width: 1,
          color: this.flowReady && !this.uploadingLogs ? '#659287' : '#777777',
          radius: 10,
        })
        .enabled(this.flowReady && !this.uploadingLogs)
        .onClick((): void => {
          void this.uploadLogs();
        })
    }
    .width('100%')
    .padding({ left: 8, right: 16, top: PLAYER_TOP_PADDING })
    .backgroundColor('#FFF8E8')
  }

  @Builder
  private seekPanel() {
    Row() {
      Text(this.formatClock(this.currentTimeMs))
        .fontSize(12)
        .fontColor('#CCFFFFFF')
      Slider({
        value: this.seekValue(),
        min: 0,
        max: 1000,
        step: 1,
      })
        .id('tirtc_example_ti_cloud_storage_seek_slider')
        .layoutWeight(1)
        .selectedColor('#659287')
        .trackColor('#4DFFFFFF')
        .onChange((value: number, mode: SliderChangeMode): void => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.seekTo(value);
          }
        })
      Text(this.formatClock(this.selectedRange()?.endTimeMs ?? 0))
        .fontSize(12)
        .fontColor('#CCFFFFFF')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor('#75000000')
    .border({ width: 1, color: '#33FFFFFF', radius: 24 })
  }

  @Builder
  private controls() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Blank()
        Button(this.recording ? '◉' : '●')
          .id('tirtc_example_ti_cloud_storage_recording_button')
          .accessibilityText(this.recording ? '停止本地保存' : '开始本地保存')
          .width(48)
          .height(48)
          .fontSize(18)
          .fontColor('#659287')
          .backgroundColor('#D9E5E2')
          .borderRadius(24)
          .enabled(this.canControl() && !this.mediaBusy)
          .onClick((): void => {
            void this.toggleRecording();
          })
        Button('▣')
          .id('tirtc_example_ti_cloud_storage_snapshot_button')
          .accessibilityText('截图')
          .width(48)
          .height(48)
          .fontSize(18)
          .fontColor('#659287')
          .backgroundColor('#D9E5E2')
          .borderRadius(24)
          .enabled(this.replayState === 'rendering' && !this.mediaBusy)
          .onClick((): void => {
            void this.takeSnapshot();
          })
        Button('▤')
          .id('tirtc_example_ti_cloud_storage_gallery_button')
          .accessibilityText('保存到系统相册')
          .width(48)
          .height(48)
          .fontSize(18)
          .fontColor('#659287')
          .backgroundColor('#D9E5E2')
          .borderRadius(24)
          .enabled(this.latestMediaKind.length > 0 && !this.mediaBusy)
          .onClick((): void => {
            void this.saveLatestToGallery();
          })
      }
      .width('100%')
      Row({ space: 10 }) {
        Blank()
        Button(this.muted ? '恢复声音' : '静音')
          .id('tirtc_example_ti_cloud_storage_mute_button')
          .height(50)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.muted ? '#FFFFFF' : '#659287')
          .backgroundColor(this.muted ? '#F59E0B' : '#FFFFFF')
          .borderRadius(25)
          .enabled(this.canControl() && this.speedIndex === 3)
          .onClick((): void => {
            this.toggleMuted();
          })
        Select([
          { value: '1/8×' },
          { value: '1/4×' },
          { value: '1/2×' },
          { value: '1×' },
          { value: '2×' },
          { value: '4×' },
          { value: '8×' },
        ])
          .id('tirtc_example_ti_cloud_storage_speed_selector')
          .selected(this.speedIndex)
          .value(this.speedLabel())
          .height(50)
          .font({ size: 13, weight: FontWeight.Medium })
          .fontColor('#659287')
          .backgroundColor('#FFFFFF')
          .borderRadius(25)
          .padding({ left: 14, right: 14 })
          .enabled(this.canControl())
          .onSelect((index: number): void => {
            this.changeSpeed(index);
          })
        Button(this.paused ? '继续播放' : '暂停播放')
          .id('tirtc_example_ti_cloud_storage_pause_button')
          .height(56)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor('#659287')
          .borderRadius(28)
          .enabled(this.canControl())
          .onClick((): void => {
            this.togglePause();
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private recordingCalendar() {
    Column() {
      Row() {
        Button('上个月')
          .id('tirtc_example_ti_cloud_storage_previous_month_button')
          .height(36)
          .fontSize(12)
          .fontColor('#659287')
          .backgroundColor('#00FFFFFF')
          .border({ width: 1, color: '#659287', radius: 10 })
          .onClick((): void => {
            this.shiftMonth(-1);
          })
        Text(this.visibleMonth)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#666666')
          .textAlign(TextAlign.Center)
        Button('下个月')
          .id('tirtc_example_ti_cloud_storage_next_month_button')
          .height(36)
          .fontSize(12)
          .fontColor('#659287')
          .backgroundColor('#00FFFFFF')
          .border({ width: 1, color: '#659287', radius: 10 })
          .onClick((): void => {
            this.shiftMonth(1);
          })
      }
      .width('100%')
      Text('自然日按 Asia/Shanghai 查询')
        .width('100%')
        .fontSize(12)
        .fontColor('#848282')
        .textAlign(TextAlign.Center)
        .margin({ top: 6, bottom: 6 })
      Row() {
        this.calendarWeekday('日')
        this.calendarWeekday('一')
        this.calendarWeekday('二')
        this.calendarWeekday('三')
        this.calendarWeekday('四')
        this.calendarWeekday('五')
        this.calendarWeekday('六')
      }
      .width('100%')
      Grid() {
        ForEach(this.monthCells(), (date: string, index: number) => {
          GridItem() {
            Button(this.calendarDayLabel(date))
              .id(date.length === 0 ? `tirtc_example_ti_cloud_storage_calendar_blank_${index}` :
                `tirtc_example_ti_cloud_storage_calendar_day_${date}`)
              .height(46)
              .fontSize(10)
              .fontColor(this.dateText === date ? '#FFFFFF' : '#666666')
              .backgroundColor(this.dateText === date ? '#659287' : '#24659287')
              .borderRadius(12)
              .enabled(date.length > 0 && this.recordingDays.indexOf(date) >= 0)
              .onClick((): void => {
                this.dateText = date;
                this.calendarVisible = false;
                void this.querySelectedDay();
              })
          }
        }, (date: string, index: number): string => `${date}-${index}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .columnsGap(2)
      .rowsGap(2)
      .width('100%')
      if (this.monthLoading) {
        Text('正在加载月份…').fontSize(12).fontColor('#848282')
      } else if (this.monthFailed) {
        Button('月份加载失败，重试')
          .fontSize(12)
          .fontColor('#B42318')
          .backgroundColor('#00FFFFFF')
          .onClick((): void => {
            void this.queryMonth();
          })
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 8, bottom: 8 })
  }

  @Builder
  private calendarWeekday(label: string) {
    Text(label)
      .layoutWeight(1)
      .fontSize(11)
      .fontColor('#848282')
      .textAlign(TextAlign.Center)
  }

  @Builder
  private recordingsSheet() {
    Column() {
      Blank()
      Column() {
        Row() {
          Text('')
            .id('tirtc_example_ti_cloud_storage_sheet_handle')
            .width(40)
            .height(4)
            .borderRadius(2)
            .backgroundColor('#E1DBCF')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 6, bottom: 2 })
        if (this.calendarVisible) {
          this.recordingCalendar()
        } else {
          Column() {
            Row() {
              Text(`${this.dateText} 的录像`)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#666666')
                .layoutWeight(1)
              Button('重新选择日期')
                .id('tirtc_example_ti_cloud_storage_reselect_date_button')
                .height(36)
                .fontSize(12)
                .fontColor('#659287')
                .backgroundColor('#00FFFFFF')
                .border({ width: 1, color: '#659287', radius: 10 })
                .onClick((): void => {
                  this.calendarVisible = true;
                })
            }
            .width('100%')
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            Divider().color('#E1DBCF')
            Scroll() {
              Column() {
                if (this.querying) {
                  Column() {
                    LoadingProgress()
                      .width(36)
                      .height(36)
                      .color('#659287')
                    Text('正在查询…')
                      .fontSize(13)
                      .fontColor('#848282')
                      .margin({ top: 12 })
                  }
                  .width('100%')
                  .padding(24)
                } else if (this.queryFailed) {
                  Column() {
                    Text('查询失败')
                      .fontSize(13)
                      .fontColor('#848282')
                    Button('重试')
                      .id('tirtc_example_ti_cloud_storage_query_retry_button')
                      .height(48)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#FFFFFF')
                      .backgroundColor('#659287')
                      .borderRadius(28)
                      .padding({ left: 20, right: 20 })
                      .margin({ top: 12 })
                      .enabled(this.flowReady)
                      .onClick((): void => {
                        void this.querySelectedDay();
                      })
                  }
                  .width('100%')
                  .padding(24)
                } else if (this.ranges.length === 0) {
                  Column() {
                    Text('当天没有可用录像')
                      .fontSize(13)
                      .fontColor('#848282')
                    Button('重新查询')
                      .id('tirtc_example_ti_cloud_storage_query_empty_retry_button')
                      .height(40)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#659287')
                      .backgroundColor('#00FFFFFF')
                      .border({ width: 1, color: '#659287', radius: 10 })
                      .padding({ left: 12, right: 12 })
                      .margin({ top: 12 })
                      .enabled(this.flowReady)
                      .onClick((): void => {
                        void this.querySelectedDay();
                      })
                  }
                  .width('100%')
                  .padding(24)
                } else {
                  ForEach(this.ranges, (range: TiCloudStorageRecordingRange, index: number) => {
                    Column() {
                      Row() {
                        Column() {
                          Text(`${this.formatClock(range.startTimeMs)} — ${this.formatClock(range.endTimeMs)}`)
                            .id(`tirtc_example_ti_cloud_storage_recording_rank_${index}`)
                            .fontSize(14)
                            .fontColor('#666666')
                          Text(`时长 ${this.formatDuration(range.endTimeMs - range.startTimeMs)}`)
                            .fontSize(12)
                            .fontColor('#848282')
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                        .onClick((): void => {
                          this.playRange(index);
                        })
                        Button(this.exportProgress >= 0 ? `${Math.round(this.exportProgress * 100)}%` : '下载')
                          .id(`tirtc_example_ti_cloud_storage_export_${range.startTimeMs}`)
                          .height(40)
                          .fontSize(12)
                          .fontWeight(FontWeight.Medium)
                          .fontColor('#659287')
                          .backgroundColor('#00FFFFFF')
                          .border({ width: 1, color: '#659287', radius: 10 })
                          .padding({ left: 12, right: 12 })
                          .enabled(this.exportProgress < 0)
                          .onClick((): void => {
                            void this.exportRange(index);
                          })
                      }
                      .width('100%')
                      .padding({ left: 8, right: 8, top: 12, bottom: 12 })
                      .onClick((): void => {
                        this.playRange(index);
                      })
                    }
                    .width('100%')
                    .id(`tirtc_example_ti_cloud_storage_recording_${range.startTimeMs}`)
                    Divider().color('#E1DBCF')
                  }, (range: TiCloudStorageRecordingRange): string => `${range.startTimeMs}-${range.endTimeMs}`)
                }
              }
              .width('100%')
            }
            .width('100%')
            .layoutWeight(1)
          }
          .id('tirtc_example_ti_cloud_storage_recording_list')
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('88%')
      .padding({ left: 0, right: 0, top: 6, bottom: 12 })
      .backgroundColor('#FFF8E8')
      .borderRadius({ topLeft: 24, topRight: 24 })
      .id('tirtc_example_ti_cloud_storage_sheet')
      .onClick((): void => {
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#55000000')
    .onClick((): void => {
      this.sheetVisible = false;
    })
  }

  private async initialize(generation: number): Promise<void> {
    if (this.closing !== undefined) {
      await this.closing;
    }
    if (!this.isCurrent(generation)) return;
    const context = getContext(this) as common.UIAbilityContext;
    const initCode = await TiCloudStorage.init({
      context,
      appId: this.appId.trim(),
      endpoint: this.endpoint.trim(),
      consoleLogEnabled: this.consoleLogEnabled,
    });
    if (!this.isCurrent(generation)) {
      if (initCode === TI_CLOUD_STORAGE_ERROR_OK) TiCloudStorage.shutdown();
      return;
    }
    if (initCode !== TI_CLOUD_STORAGE_ERROR_OK) {
      this.setNotice(`初始化失败 · ${TiCloudStorage.errorToString(initCode)} (${initCode})`);
      return;
    }
    const listener: TiCloudStorageExampleFlowListener = {
      onReplayState: (state: string): void => {
        if (!this.isCurrent(generation)) return;
        this.replayState = state;
      },
      onTimeChanged: (timeMs: number): void => {
        if (!this.isCurrent(generation)) return;
        this.currentTimeMs = timeMs;
      },
      onCompleted: (): void => {
        if (!this.isCurrent(generation)) return;
        this.replayState = 'completed';
      },
      onError: (code: number): void => {
        if (!this.isCurrent(generation)) return;
        this.setNotice(`操作失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
      },
      onExportProgress: (progress: number): void => {
        if (!this.isCurrent(generation)) return;
        this.exportProgress = progress;
      },
      onMediaChanged: (kind: string): void => {
        if (!this.isCurrent(generation)) return;
        this.latestMediaKind = kind;
      },
    };
    this.flow = new TiCloudStorageExampleFlow(this.token, listener);
    if (!this.isCurrent(generation)) {
      await this.closeFlow();
      return;
    }
    this.flowReady = true;
    this.sheetVisible = true;
    this.calendarVisible = true;
    await this.queryMonth();
  }

  private async querySelectedDay(): Promise<void> {
    const flow = this.flow;
    const bounds = this.selectedDayBounds();
    if (flow === undefined || bounds === undefined) {
      if (bounds === undefined) this.setNotice('请输入有效日期。');
      return;
    }
    const generation = ++this.dayQueryGeneration;
    this.querying = true;
    this.queryFailed = false;
    this.ranges = [];
    const result = await flow.query(bounds.startTimeMs, bounds.endTimeMs);
    if (this.flow !== flow || generation !== this.dayQueryGeneration) return;
    this.ranges = newestFirstRecordingRanges(result.recordings);
    this.querying = false;
    this.queryFailed = result.code !== TI_CLOUD_STORAGE_ERROR_OK;
    if (this.queryFailed) {
      this.setNotice('查询失败');
    }
  }

  private async queryMonth(): Promise<void> {
    const flow = this.flow;
    if (flow === undefined) return;
    const month = this.visibleMonth;
    const generation = ++this.monthQueryGeneration;
    this.monthLoading = true;
    this.monthFailed = false;
    this.recordingDays = [];
    const bounds = this.monthDateBounds(month);
    const result = await flow.queryDays(bounds[0], bounds[1], 'Asia/Shanghai');
    if (this.flow !== flow || generation !== this.monthQueryGeneration || month !== this.visibleMonth) return;
    const days: Array<string> = [];
    result.days.forEach((day): void => {
      if (day.hasRecording) days.push(day.date);
    });
    this.recordingDays = days;
    this.monthLoading = false;
    this.monthFailed = result.code !== TI_CLOUD_STORAGE_ERROR_OK;
  }

  private shiftMonth(delta: number): void {
    const parts = this.visibleMonth.split('-');
    const value = new Date(Date.UTC(Number(parts[0]), Number(parts[1]) - 1 + delta, 1));
    this.visibleMonth =
      `${value.getUTCFullYear()}-${padCloudStorageClock(value.getUTCMonth() + 1)}`;
    void this.queryMonth();
  }

  private monthDateBounds(month: string): Array<string> {
    const parts = month.split('-');
    const last = new Date(Date.UTC(Number(parts[0]), Number(parts[1]), 0)).getUTCDate();
    return [`${month}-01`, `${month}-${padCloudStorageClock(last)}`];
  }

  private monthCells(): Array<string> {
    const parts = this.visibleMonth.split('-');
    const year = Number(parts[0]);
    const month = Number(parts[1]);
    const leading = new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
    const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
    const cells: Array<string> = [];
    for (let index = 0; index < leading; index += 1) cells.push('');
    for (let day = 1; day <= last; day += 1) {
      cells.push(`${this.visibleMonth}-${padCloudStorageClock(day)}`);
    }
    return cells;
  }

  private calendarDayLabel(date: string): string {
    if (date.length === 0) return '';
    const state = this.recordingDays.indexOf(date) >= 0 ? '有录像' : '无录像';
    return `${Number(date.slice(-2))}\n${state}`;
  }

  private playRange(index: number): void {
    const flow = this.flow;
    const range = this.ranges[index];
    if (flow === undefined || range === undefined) return;
    const code = flow.play(range, this.videoChannelId, this.audioChannelId);
    if (code === TI_CLOUD_STORAGE_ERROR_OK) {
      this.selectedIndex = index;
      this.currentTimeMs = range.startTimeMs;
      this.replayState = 'buffering';
      this.paused = false;
      this.muted = false;
      this.speedIndex = 3;
      this.sheetVisible = false;
      this.setNotice('正在播放');
    } else {
      this.setNotice(`播放失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
    }
  }

  private togglePause(): void {
    const flow = this.flow;
    if (flow === undefined) return;
    const nextPaused = !this.paused;
    const code = nextPaused ? flow.pause() : flow.resume();
    if (code === TI_CLOUD_STORAGE_ERROR_OK) {
      this.paused = nextPaused;
      this.replayState = nextPaused ? 'paused' : 'buffering';
      this.setNotice(nextPaused ? '已暂停' : '已恢复播放');
    } else {
      this.setNotice(`暂停操作失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
    }
  }

  private toggleMuted(): void {
    const flow = this.flow;
    if (flow === undefined) return;
    const nextMuted = !this.muted;
    const code = flow.setMuted(nextMuted);
    if (code === TI_CLOUD_STORAGE_ERROR_OK) {
      this.muted = nextMuted;
      this.setNotice(nextMuted ? '已静音' : '已恢复声音');
    } else {
      this.setNotice(`音量设置失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
    }
  }

  private changeSpeed(index: number): void {
    const flow = this.flow;
    if (flow === undefined || index < 0 || index > 6) return;
    const speeds = [TiCloudStorageReplaySpeed.x0_125, TiCloudStorageReplaySpeed.x0_25,
      TiCloudStorageReplaySpeed.x0_5, TiCloudStorageReplaySpeed.x1, TiCloudStorageReplaySpeed.x2,
      TiCloudStorageReplaySpeed.x4, TiCloudStorageReplaySpeed.x8];
    const code = flow.setSpeed(speeds[index]);
    if (code === TI_CLOUD_STORAGE_ERROR_OK) {
      this.speedIndex = index;
      this.setNotice(`播放倍速已切换为 ${this.speedLabel()}`);
    } else {
      this.setNotice(`倍速设置失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
    }
  }

  private async toggleRecording(): Promise<void> {
    const flow = this.flow;
    if (flow === undefined || this.mediaBusy) return;
    if (!this.recording) {
      const code = flow.startRecording(this.videoChannelId, this.audioChannelId);
      if (code === TI_CLOUD_STORAGE_ERROR_OK) {
        this.recording = true;
        this.setNotice('已开始本地保存');
      } else {
        this.setNotice(`开始保存失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
      }
      return;
    }
    this.mediaBusy = true;
    const code = await flow.stopRecording();
    this.mediaBusy = false;
    this.recording = false;
    this.setNotice(code === TI_CLOUD_STORAGE_ERROR_OK ? '本地保存已完成' :
      `停止保存失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
  }

  private async takeSnapshot(): Promise<void> {
    const flow = this.flow;
    if (flow === undefined || this.mediaBusy) return;
    this.mediaBusy = true;
    const code = await flow.takeSnapshot();
    this.mediaBusy = false;
    this.setNotice(code === TI_CLOUD_STORAGE_ERROR_OK ? '截图已完成' :
      `截图失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
  }

  private async exportRange(index: number): Promise<void> {
    const flow = this.flow;
    const range = this.ranges[index];
    if (flow === undefined || range === undefined || this.exportProgress >= 0) return;
    this.exportProgress = 0;
    this.setNotice('正在下载录像…');
    const code = await flow.exportRecording(range, this.videoChannelId, this.audioChannelId);
    this.exportProgress = -1;
    this.setNotice(code === TI_CLOUD_STORAGE_ERROR_OK ? '范围录像已下载' :
      `导出失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
  }

  private async saveLatestToGallery(): Promise<void> {
    const flow = this.flow;
    if (flow === undefined || this.mediaBusy || flow.latestMediaPath().length === 0) return;
    this.mediaBusy = true;
    const context = getContext(this) as common.UIAbilityContext;
    const saved = await saveMediaFileToGallery(context, flow.latestMediaPath(), flow.latestMediaKind());
    if (!saved) {
      this.mediaBusy = false;
      this.setNotice('保存到系统相册失败，源文件已保留。');
      return;
    }
    const deleted = await flow.deleteLatestMedia();
    this.mediaBusy = false;
    this.setNotice(deleted === TI_CLOUD_STORAGE_ERROR_OK ? '已保存到系统相册' :
      `相册已保存，但源文件删除失败 · ${TiCloudStorage.errorToString(deleted)} (${deleted})`);
  }

  private async uploadLogs(): Promise<void> {
    if (this.uploadingLogs) return;
    this.uploadingLogs = true;
    this.setNotice('日志上传中');
    const result = await TiRtcLogging.upload();
    this.uploadingLogs = false;
    this.setNotice(result.code === TI_CLOUD_STORAGE_ERROR_OK ? `日志上传成功 · ${result.logId ?? ''}` :
      `日志上传失败 · ${result.code}`);
  }

  private seekTo(value: number): void {
    const flow = this.flow;
    const range = this.selectedRange();
    if (flow === undefined || range === undefined) return;
    const timeMs = range.startTimeMs + Math.round((range.endTimeMs - range.startTimeMs) * value / 1000);
    const code = flow.seek(timeMs);
    this.setNotice(code === TI_CLOUD_STORAGE_ERROR_OK ? '已跳转到所选位置' :
      `Seek 失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
  }

  private setNotice(text: string): void {
    this.notice = text;
    if (this.noticeTimer >= 0) {
      clearTimeout(this.noticeTimer);
      this.noticeTimer = -1;
    }
    this.noticeTimer = setTimeout((): void => {
      this.stopNoticeTimer();
      this.notice = '';
    }, NOTICE_AUTO_HIDE_MS);
  }

  private stopNoticeTimer(): void {
    if (this.noticeTimer < 0) {
      return;
    }
    clearTimeout(this.noticeTimer);
    this.noticeTimer = -1;
  }

  private async backToCloudStorageEntry(): Promise<void> {
    this.active = false;
    this.generation += 1;
    await this.closeFlow();
    this.onBack();
  }

  private closeFlow(): Promise<void> {
    if (this.closing !== undefined) return this.closing;
    const flow = this.flow;
    this.flow = undefined;
    this.dayQueryGeneration += 1;
    this.monthQueryGeneration += 1;
    this.flowReady = false;
    this.sheetVisible = false;
    this.querying = false;
    this.monthLoading = false;
    const started = (async (): Promise<void> => {
      if (flow !== undefined) {
        await flow.dispose();
        TiCloudStorage.shutdown();
      }
      this.recording = false;
      this.mediaBusy = false;
      this.exportProgress = -1;
      this.latestMediaKind = '';
    })();
    this.closing = started;
    void started.then((): void => {
      if (this.closing === started) this.closing = undefined;
    });
    return started;
  }

  private isCurrent(generation: number): boolean {
    return this.active && this.generation === generation;
  }

  private selectedRange(): TiCloudStorageRecordingRange | undefined {
    return this.selectedIndex < 0 ? undefined : this.ranges[this.selectedIndex];
  }

  private canControl(): boolean {
    return this.selectedRange() !== undefined;
  }

  private seekValue(): number {
    const range = this.selectedRange();
    if (range === undefined || range.endTimeMs <= range.startTimeMs) return 0;
    return Math.max(0, Math.min(1000,
      Math.round((this.currentTimeMs - range.startTimeMs) * 1000 / (range.endTimeMs - range.startTimeMs))));
  }

  private stageStatusLabel(): string {
    if (!this.flowReady) return '加载中';
    if (this.selectedRange() === undefined) return '请选择录像';
    if (this.replayState === 'buffering') return '缓冲中';
    if (this.replayState === 'paused') return '已暂停';
    if (this.replayState === 'completed') return '播放完成';
    if (this.replayState === 'failed') return '播放失败';
    if (this.replayState === 'idle') return '加载中';
    return '';
  }

  private showStageOverlay(): boolean {
    return this.stageStatusLabel().length > 0;
  }

  private selectedDayBounds(): CloudStorageDayBounds | undefined {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(this.dateText.trim());
    if (match === null) return undefined;
    const startTimeMs = Date.parse(`${this.dateText}T00:00:00+08:00`);
    if (!Number.isFinite(startTimeMs)) return undefined;
    return new CloudStorageDayBounds(startTimeMs, startTimeMs + 24 * 60 * 60 * 1000);
  }

  private speedLabel(): string {
    return ['1/8×', '1/4×', '1/2×', '1×', '2×', '4×', '8×'][this.speedIndex];
  }

  private formatClock(timeMs: number): string {
    if (timeMs <= 0) return '--:--:--';
    const date = new Date(timeMs + 8 * 60 * 60 * 1000);
    return `${padCloudStorageClock(date.getUTCHours())}:${padCloudStorageClock(date.getUTCMinutes())}:${padCloudStorageClock(date.getUTCSeconds())}`;
  }

  private formatDuration(durationMs: number): string {
    const seconds = Math.max(0, Math.round(durationMs / 1000));
    return `${padCloudStorageClock(Math.floor(seconds / 60))}:${padCloudStorageClock(seconds % 60)}`;
  }
}
