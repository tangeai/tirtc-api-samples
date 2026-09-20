import type { common } from '@kit.AbilityKit';
import {
  TiRtcLogging,
  TiCloudStorage,
  TiCloudStorageRecordingRange,
  TiCloudStorageReplaySpeed,
  TiCloudStorageVideoOutputView,
  TI_CLOUD_STORAGE_ERROR_IN_USE,
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
const VIDEO_OUTPUT_MOUNT_OBSERVE_MS: number = 700;
const FLOW_CLEANUP_RETRY_DELAY_MS: number = 250;

function parseCloudAreaDimension(value: Length): number {
  if (typeof value === 'number') return value;
  return typeof value === 'string' ? Number.parseFloat(value) : 0;
}

function observeCloudStorageVideoOutputMount(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, VIDEO_OUTPUT_MOUNT_OBSERVE_MS);
  });
}

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
  @Prop audioChannelId: number | null = DEFAULT_AUDIO_STREAM_ID;
  @Prop videoChannelIds: Array<number> = [DEFAULT_VIDEO_STREAM_ID];
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
  @State private videoStates: Array<string> = ['idle'];
  @State private selectedVideoChannelId: number = DEFAULT_VIDEO_STREAM_ID;
  @State private maximizedVideoChannelId: number = -1;
  @State private paused: boolean = false;
  @State private muted: boolean = false;
  @State private speedIndex: number = 3;
  @State private recording: boolean = false;
  @State private mediaBusy: boolean = false;
  @State private latestMediaKind: string = '';
  @State private exportProgress: number = -1;
  @State private uploadingLogs: boolean = false;
  @State private rawDumpCapturing: boolean = false;
  @State private rawDumpBusy: boolean = false;
  @State private rawDumpUploadPending: boolean = false;
  @State private dateText: string = currentCloudStorageDateText();
  @State private visibleMonth: string = currentCloudStorageDateText().slice(0, 7);
  @State private recordingDays: Array<string> = [];
  @State private monthLoading: boolean = false;
  @State private monthFailed: boolean = false;
  @State private queryFailed: boolean = false;
  @State private stageWidth: number = 0;
  private flow?: TiCloudStorageExampleFlow;
  private closing?: Promise<boolean>;
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
    void this.closeFlowUntilReleased();
  }

  build() {
    Stack() {
      Column() {
        this.topBar()
        Stack() {
          Stack({ alignContent: Alignment.Center }) {
            if (this.videoChannelIds.length === 0) {
              Text(this.audioChannelId === null ? '未配置音视频' : '仅音频回放')
                .fontSize(14)
                .fontColor('#CCFFFFFF')
            } else if (this.flowReady && this.flow !== undefined) {
              this.videoMosaic()
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
                  .borderRadius(16)
                  .constraintSize({ maxWidth: '80%' })
              }
              .width('100%')
              .margin({ top: 16 })
            }
            Blank()
            this.controls()
          }
          .width('100%')
          .height('100%')
          .padding({ left: 20, right: 20, bottom: PLAYER_BOTTOM_PADDING })
          .linearGradient({
            angle: 180,
            colors: [['#33000000', 0.0], ['#00000000', 0.45], ['#66000000', 1.0]],
          })
          .hitTestBehavior(HitTestMode.Transparent)
          Row() {
            Column({ space: 5 }) {
              Button(this.rawDumpCapturing ? '结束上传' : (this.rawDumpUploadPending ? '重试上传' : '抓数据'))
                .id('tirtc_example_ti_cloud_storage_raw_dump_button')
                .accessibilityText(this.rawDumpCapturing ? '停止云录像诊断抓取' : '开始云录像诊断抓取')
                .width(56)
                .height(56)
                .fontSize(11)
                .fontColor('#FFFFFF')
                .backgroundColor(this.rawDumpCapturing ? '#E68A35' : '#659287')
                .borderRadius(28)
                .enabled(this.canControl() && !this.rawDumpBusy && !this.uploadingLogs)
                .onClick((): void => {
                  void this.toggleRawDump();
                })
            }
            .alignItems(HorizontalAlign.Start)
            Blank()
          }
          .width('100%')
          .padding({ left: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#252525')
        .id('tirtc_example_ti_cloud_storage_video_stage')
        .onAreaChange((oldArea: Area, newArea: Area): void => {
          this.stageWidth = parseCloudAreaDimension(newArea.width);
        })
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
  private videoMosaic() {
    if (this.selectedVideoChannelId === this.videoChannelIds[1]) {
      this.videoMosaicForPrimary(1)
    } else if (this.selectedVideoChannelId === this.videoChannelIds[2]) {
      this.videoMosaicForPrimary(2)
    } else {
      this.videoMosaicForPrimary(0)
    }
  }

  @Builder
  private videoMosaicForPrimary(primaryIndex: number) {
    if (this.videoChannelIds.length === 1) {
      this.videoLane(0)
    } else if (this.videoChannelIds.length === 2) {
      if (this.stageWidth >= 600) {
        Row({ space: this.maximizedVideoChannelId >= 0 ? 0 : 4 }) {
          Column() { this.videoLane(primaryIndex) }.layoutWeight(1).height('100%')
          Column() { this.videoLane(this.otherVideoIndexes(primaryIndex)[0]) }
            .layoutWeight(this.maximizedVideoChannelId >= 0 ? 0 : 1)
            .visibility(this.maximizedVideoChannelId >= 0 ? Visibility.None : Visibility.Visible)
            .height('100%')
        }.width('100%').height('100%')
      } else {
        Column({ space: this.maximizedVideoChannelId >= 0 ? 0 : 4 }) {
          Column() { this.videoLane(primaryIndex) }.layoutWeight(1).width('100%')
          Row() { this.videoLane(this.otherVideoIndexes(primaryIndex)[0]) }
            .layoutWeight(this.maximizedVideoChannelId >= 0 ? 0 : 1)
            .visibility(this.maximizedVideoChannelId >= 0 ? Visibility.None : Visibility.Visible)
            .width('100%')
        }.width('100%').height('100%')
      }
    } else {
      if (this.stageWidth >= 600) {
        Row({ space: this.maximizedVideoChannelId >= 0 ? 0 : 4 }) {
          Column() { this.videoLane(primaryIndex) }
            .layoutWeight(this.maximizedVideoChannelId >= 0 ? 1 : 2).height('100%')
          Column({ space: this.maximizedVideoChannelId >= 0 ? 0 : 4 }) {
            this.videoLane(this.otherVideoIndexes(primaryIndex)[0])
            this.videoLane(this.otherVideoIndexes(primaryIndex)[1])
          }
            .layoutWeight(this.maximizedVideoChannelId >= 0 ? 0 : 1)
            .visibility(this.maximizedVideoChannelId >= 0 ? Visibility.None : Visibility.Visible)
            .height('100%')
        }.width('100%').height('100%')
      } else {
        Column({ space: this.maximizedVideoChannelId >= 0 ? 0 : 4 }) {
          Column() { this.videoLane(primaryIndex) }
            .layoutWeight(this.maximizedVideoChannelId >= 0 ? 1 : 2).width('100%')
          Row({ space: this.maximizedVideoChannelId >= 0 ? 0 : 4 }) {
            this.videoLane(this.otherVideoIndexes(primaryIndex)[0])
            this.videoLane(this.otherVideoIndexes(primaryIndex)[1])
          }
            .layoutWeight(this.maximizedVideoChannelId >= 0 ? 0 : 1)
            .visibility(this.maximizedVideoChannelId >= 0 ? Visibility.None : Visibility.Visible)
            .width('100%')
        }.width('100%').height('100%')
      }
    }
  }

  @Builder
  private videoLane(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      TiCloudStorageVideoOutputView({ output: this.flow!.videoOutputs[index] })
      if (this.videoStates[index] !== 'rendering') {
        Text(this.videoStates[index] === 'failed' ? '播放失败' :
          this.videoStates[index] === 'completed' ? '播放完成' : '等待视频')
          .fontSize(13)
          .fontColor('#FFFFFF')
      }
      Column() {
        Row() {
          Button(`视频 ${index + 1} · Channel ${this.videoChannelIds[index]}`)
            .id(`tirtc_example_ti_cloud_storage_video_lane_${this.videoChannelIds[index]}`)
            .accessibilityText(`视频 ${index + 1}，Channel ${this.videoChannelIds[index]}，点击选择或切换最大化`)
            .height(44)
            .fontSize(11).fontColor('#FFFFFF')
            .padding({ left: 12, right: 12 })
            .backgroundColor('#75000000').borderRadius(8)
            .onClick((): void => this.activateVideoLane(this.videoChannelIds[index]))
          if (this.selectedVideoChannelId === this.videoChannelIds[index]) {
            Button(this.maximizedVideoChannelId === this.videoChannelIds[index] ? '恢复宫格' : '最大化')
              .id(this.maximizedVideoChannelId === this.videoChannelIds[index] ?
                `tirtc_example_ti_cloud_storage_video_lane_restore_${this.videoChannelIds[index]}` :
                `tirtc_example_ti_cloud_storage_video_lane_maximize_${this.videoChannelIds[index]}`)
              .accessibilityText(this.maximizedVideoChannelId === this.videoChannelIds[index] ?
                `恢复 Channel ${this.videoChannelIds[index]} 宫格` :
                `最大化 Channel ${this.videoChannelIds[index]}`)
              .height(44).fontSize(11).fontColor('#FFFFFF')
              .padding({ left: 12, right: 12 })
              .backgroundColor('#75659287').borderRadius(8)
              .onClick((): void => {
                this.maximizedVideoChannelId =
                  this.maximizedVideoChannelId === this.videoChannelIds[index] ? -1 : this.videoChannelIds[index];
              })
          }
          Blank()
        }.width('100%')
        Blank()
      }
      .width('100%').height('100%').padding(8)
    }
    .id(`tirtc_example_ti_cloud_storage_video_lane_surface_${this.videoChannelIds[index]}`)
    .layoutWeight(1).width('100%').height('100%')
    .border({ width: this.selectedVideoChannelId === this.videoChannelIds[index] ? 2 : 0, color: '#659287' })
  }

  private otherVideoIndexes(primary: number): Array<number> {
    const indexes: Array<number> = [];
    for (let index = 0; index < Math.min(3, this.videoChannelIds.length); index += 1) {
      if (index !== primary) indexes.push(index);
    }
    return indexes;
  }

  private activateVideoLane(channelId: number): void {
    if (this.selectedVideoChannelId !== channelId) {
      this.maximizedVideoChannelId = -1;
      this.selectVideoChannel(channelId);
      return;
    }
    this.maximizedVideoChannelId = this.maximizedVideoChannelId === channelId ? -1 : channelId;
  }

  @Builder
  private topBar() {
    Row() {
      Button('<')
        .id('tirtc_example_ti_cloud_storage_back_button')
        .accessibilityText('返回')
        .width(48)
        .height(48)
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
        .height(48)
        .fontSize(12)
        .fontColor(this.flowReady ? '#659287' : '#777777')
        .backgroundColor('#00FFFFFF')
        .border({ width: 1, color: this.flowReady ? '#659287' : '#777777', radius: 12 })
        .enabled(this.flowReady)
        .onClick((): void => {
          this.calendarVisible = this.ranges.length === 0;
          this.sheetVisible = true;
        })
      Blank().width(8)
      Button('更多')
        .id('tirtc_example_ti_cloud_storage_more_button')
        .accessibilityText('更多操作')
        .width(48)
        .height(48)
        .fontSize(12)
        .fontColor('#659287')
        .backgroundColor('#00FFFFFF')
        .bindMenu(this.topBarMenu)
    }
    .width('100%')
    .padding({ left: 8, right: 16, top: PLAYER_TOP_PADDING })
    .backgroundColor('#FFF8E8')
  }

  @Builder
  private topBarMenu() {
    Menu() {
      MenuItem({ content: this.uploadingLogs ? '上传中' : '上传日志' })
        .id('tirtc_example_ti_cloud_storage_log_upload_button')
        .enabled(this.flowReady && !this.uploadingLogs)
        .onClick((): void => {
          void this.uploadLogs();
        })
    }
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
    .border({ width: 1, color: '#33FFFFFF', radius: 16 })
  }

  @Builder
  private controls() {
    Column({ space: 8 }) {
      if (this.selectedRange() !== undefined) {
        this.seekPanel()
      }
      Row({ space: 10 }) {
        Button(this.muted ? '恢复声音' : '静音')
          .id('tirtc_example_ti_cloud_storage_mute_button')
          .height(52)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.muted ? '#FFFFFF' : '#659287')
          .backgroundColor(this.muted ? '#F59E0B' : '#FFFFFF')
          .borderRadius(12)
          .enabled(this.canControl() && this.speedIndex === 3 && this.audioChannelId !== null)
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
          .height(52)
          .font({ size: 13, weight: FontWeight.Medium })
          .fontColor('#659287')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .enabled(this.canControl())
          .onSelect((index: number): void => {
            this.changeSpeed(index);
          })
        Button(this.paused ? '继续播放' : '暂停播放')
          .id('tirtc_example_ti_cloud_storage_pause_button')
          .height(56)
          .layoutWeight(1)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor('#659287')
          .borderRadius(16)
          .enabled(this.canControl())
          .onClick((): void => {
            this.togglePause();
          })
        Button('媒体')
          .id('tirtc_example_ti_cloud_storage_media_more_button')
          .accessibilityText('媒体操作')
          .width(52)
          .height(52)
          .fontSize(13)
          .fontColor('#659287')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .bindMenu(this.mediaMenu)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private mediaMenu() {
    Menu() {
      MenuItem({ content: this.recording ? '停止本地保存' : '开始本地保存' })
        .id('tirtc_example_ti_cloud_storage_recording_button')
        .accessibilityText(this.recording ? '停止本地保存' : '开始本地保存')
        .enabled(this.canControl() && !this.mediaBusy && this.selectedVideoChannelId >= 0)
        .onClick((): void => {
          void this.toggleRecording();
        })
      MenuItem({ content: '截图' })
        .id('tirtc_example_ti_cloud_storage_snapshot_button')
        .accessibilityText('截图')
        .enabled(this.replayState === 'rendering' && !this.mediaBusy && this.selectedVideoChannelId >= 0)
        .onClick((): void => {
          void this.takeSnapshot();
        })
      MenuItem({ content: '保存到系统相册' })
        .id('tirtc_example_ti_cloud_storage_gallery_button')
        .accessibilityText('保存到系统相册')
        .enabled(this.latestMediaKind.length > 0 && !this.mediaBusy)
        .onClick((): void => {
          void this.saveLatestToGallery();
        })
    }
  }

  @Builder
  private recordingCalendar() {
    Column() {
      Row() {
        Button('上个月')
          .id('tirtc_example_ti_cloud_storage_previous_month_button')
          .height(44)
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
          .height(44)
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
              .accessibilityText(this.calendarDayAccessibilityLabel(date))
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
        Text('正在加载月份…')
          .id('tirtc_example_ti_cloud_storage_month_loading')
          .fontSize(12)
          .fontColor('#848282')
      } else if (this.monthFailed) {
        Button('月份加载失败，重试')
          .id('tirtc_example_ti_cloud_storage_month_error_retry')
          .height(44)
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
                .height(44)
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
                  .id('tirtc_example_ti_cloud_storage_query_loading')
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
                  .id('tirtc_example_ti_cloud_storage_query_error')
                  .width('100%')
                  .padding(24)
                } else if (this.ranges.length === 0) {
                  Column() {
                    Text('当天没有可用录像')
                      .fontSize(13)
                      .fontColor('#848282')
                    Button('重新查询')
                      .id('tirtc_example_ti_cloud_storage_query_empty_retry_button')
                      .height(44)
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
                  .id('tirtc_example_ti_cloud_storage_query_empty')
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
                        Button(this.exportProgress >= 0 ? `${Math.round(this.exportProgress * 100)}%` : '下载')
                          .id(`tirtc_example_ti_cloud_storage_export_${range.startTimeMs}`)
                          .height(44)
                          .accessibilityText(this.exportProgress >= 0 ? '录像导出中' : '下载录像段')
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
                        void this.playRange(index);
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
      .constraintSize({ maxWidth: 720 })
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
    if (this.closing !== undefined || this.flow !== undefined) await this.closeFlowUntilReleased();
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
      onVideoState: (channelId: number, state: string): void => {
        if (!this.isCurrent(generation)) return;
        const index = this.videoChannelIds.indexOf(channelId);
        if (index < 0) return;
        const next = this.videoStates.slice();
        next[index] = state;
        this.videoStates = next;
      },
      onTimeChanged: (timeMs: number): void => {
        if (!this.isCurrent(generation)) return;
        this.currentTimeMs = timeMs;
      },
      onError: (code: number): void => {
        if (!this.isCurrent(generation)) return;
        this.setNotice(`操作失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
      },
      onExportProgress: (progress: number): void => {
        if (!this.isCurrent(generation)) return;
        this.exportProgress = progress;
      },
      onExportProgressDetail: (progress): void => {
        if (!this.isCurrent(generation)) return;
        this.exportProgress = progress.fraction;
      },
      onRecordingGap: (gap): void => {
        if (!this.isCurrent(generation)) return;
        this.setNotice(`录像缺口 · ${gap.range.startTimeMs}-${gap.range.endTimeMs}`);
      },
      onExportReport: (report): void => {
        if (!this.isCurrent(generation)) return;
        this.setNotice(`导出覆盖 ${report.coveredDurationMs}ms · 缺口 ${report.gaps.length}`);
      },
      onMediaChanged: (kind: string): void => {
        if (!this.isCurrent(generation)) return;
        this.latestMediaKind = kind;
      },
    };
    this.videoStates = this.videoChannelIds.map((): string => 'idle');
    this.selectedVideoChannelId = this.videoChannelIds.length > 0 ? this.videoChannelIds[0] : -1;
    this.flow = new TiCloudStorageExampleFlow(this.token, this.videoChannelIds, listener);
    if (!this.isCurrent(generation)) {
      await this.closeFlowUntilReleased();
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
    const statusDot = this.recordingDays.indexOf(date) >= 0 ? '●' : '○';
    return `${Number(date.slice(-2))}\n${statusDot}`;
  }

  private calendarDayAccessibilityLabel(date: string): string {
    if (date.length === 0) return '日历空白';
    const state = this.recordingDays.indexOf(date) >= 0 ? '有录像' : '无录像';
    return `${date}，${state}`;
  }

  private async playRange(index: number): Promise<void> {
    const flow = this.flow;
    const range = this.ranges[index];
    if (flow === undefined || range === undefined) return;
    if (this.audioChannelId === null && this.videoChannelIds.length === 0) {
      this.setNotice('请至少选择一路音频或视频后再播放。');
      return;
    }
    this.sheetVisible = false;
    await observeCloudStorageVideoOutputMount();
    if (this.flow !== flow || this.ranges[index] !== range) return;
    const code = flow.play(range, this.audioChannelId);
    if (code === TI_CLOUD_STORAGE_ERROR_OK) {
      this.selectedIndex = index;
      this.currentTimeMs = range.startTimeMs;
      this.replayState = 'buffering';
      this.paused = false;
      this.muted = false;
      this.speedIndex = 3;
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
      if (this.selectedVideoChannelId < 0) return;
      const code = flow.startRecording(this.selectedVideoChannelId, this.audioChannelId);
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
    if (this.selectedVideoChannelId < 0) return;
    const code = await flow.exportRecording(range, this.selectedVideoChannelId, this.audioChannelId);
    this.exportProgress = -1;
    this.setNotice(code === TI_CLOUD_STORAGE_ERROR_OK ? '范围录像已下载' :
      `导出失败 · ${TiCloudStorage.errorToString(code)} (${code})`);
  }

  private async saveLatestToGallery(): Promise<void> {
    const flow = this.flow;
    if (flow === undefined || this.mediaBusy || flow.latestMediaPath().length === 0) return;
    this.mediaBusy = true;
    const context = getContext(this) as common.UIAbilityContext;
    const saved = await saveMediaFileToGallery(
      context, flow.latestMediaPath(), flow.latestMediaKind(), flow.latestMediaTarget());
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

  private selectVideoChannel(channelId: number): void {
    if (this.videoChannelIds.indexOf(channelId) < 0) return;
    this.selectedVideoChannelId = channelId;
    this.flow?.selectVideoChannel(channelId);
  }

  private async uploadLogs(): Promise<boolean> {
    if (this.uploadingLogs) return false;
    this.uploadingLogs = true;
    this.setNotice('日志上传中');
    try {
      const result = await TiRtcLogging.upload();
      this.setNotice(result.code === TI_CLOUD_STORAGE_ERROR_OK ? `日志上传成功 · ${result.logId ?? ''}` :
        `日志上传失败 · ${result.code}`);
      if (result.code === TI_CLOUD_STORAGE_ERROR_OK) this.rawDumpUploadPending = false;
      return result.code === TI_CLOUD_STORAGE_ERROR_OK;
    } catch (_) {
      this.setNotice('日志上传失败');
      return false;
    } finally {
      this.uploadingLogs = false;
    }
  }

  private async toggleRawDump(): Promise<void> {
    const flow = this.flow;
    if (flow === undefined || this.rawDumpBusy) return;
    this.rawDumpBusy = true;
    if (this.rawDumpUploadPending) {
      const uploaded = await this.uploadLogs();
      this.rawDumpBusy = false;
      if (!uploaded) this.setNotice('诊断数据上传失败 · 点击重试上传');
      return;
    }
    const result = await flow.toggleRawDump(this.audioChannelId);
    this.rawDumpBusy = false;
    if (result.code !== TI_CLOUD_STORAGE_ERROR_OK) {
      this.rawDumpCapturing = result.capturing;
      this.setNotice(`诊断抓取失败 · ${result.code}`);
      return;
    }
    this.rawDumpCapturing = result.capturing;
    if (result.capturing) {
      this.setNotice('正在抓取诊断数据 · 再次点击结束并上传日志');
    } else {
      this.setNotice(`诊断抓取完成 · ${result.captureId}`);
      this.rawDumpUploadPending = true;
      const uploaded = await this.uploadLogs();
      if (!uploaded) this.setNotice(`诊断数据上传失败 · ${result.captureId} · 点击重试上传`);
    }
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
    if (!await this.closeFlow()) {
      this.active = true;
      this.generation += 1;
      this.setNotice('诊断数据仍在结束，请稍后重试。');
      return;
    }
    this.onBack();
  }

  private closeFlow(): Promise<boolean> {
    if (this.closing !== undefined) return this.closing;
    const flow = this.flow;
    this.dayQueryGeneration += 1;
    this.monthQueryGeneration += 1;
    const started = (async (): Promise<boolean> => {
      if (flow !== undefined) {
        const code = await flow.dispose();
        if (code === TI_CLOUD_STORAGE_ERROR_IN_USE) return false;
        if (this.flow === flow) this.flow = undefined;
        TiCloudStorage.shutdown();
      }
      this.rawDumpCapturing = false;
      this.rawDumpUploadPending = false;
      this.flowReady = false;
      this.sheetVisible = false;
      this.querying = false;
      this.monthLoading = false;
      this.recording = false;
      this.mediaBusy = false;
      this.exportProgress = -1;
      this.latestMediaKind = '';
      return true;
    })();
    this.closing = started;
    void started.then((): void => {
      if (this.closing === started) this.closing = undefined;
    });
    return started;
  }

  private async closeFlowUntilReleased(): Promise<void> {
    while (!await this.closeFlow()) {
      await new Promise<void>((resolve): void => {
        setTimeout(resolve, FLOW_CLEANUP_RETRY_DELAY_MS);
      });
    }
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
