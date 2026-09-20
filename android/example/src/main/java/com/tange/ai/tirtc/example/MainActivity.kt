package com.tange.ai.tirtc.example

import android.Manifest
import android.app.AlertDialog
import android.app.Dialog
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.zxing.ResultPoint
import com.journeyapps.barcodescanner.BarcodeCallback
import com.journeyapps.barcodescanner.BarcodeResult
import com.journeyapps.barcodescanner.DecoratedBarcodeView
import com.tange.ai.tirtc.TiCloudStorageErrorCode
import com.tange.ai.tirtc.TiCloudStorageRecordingRange
import com.tange.ai.tirtc.TiCloudStorageReplaySpeed
import com.tange.ai.tirtc.TiCloudStorageVideoOutputState
import com.tange.ai.tirtc.TiRtc
import com.tange.ai.tirtc.TiRtcAudioInput
import com.tange.ai.tirtc.TiRtcAudioOutput
import com.tange.ai.tirtc.TiRtcAudioOutputErrorListener
import com.tange.ai.tirtc.TiRtcAudioOutputOptions
import com.tange.ai.tirtc.TiRtcAudioOutputState
import com.tange.ai.tirtc.TiRtcAudioOutputStateListener
import com.tange.ai.tirtc.TiRtcConn
import com.tange.ai.tirtc.TiRtcConnCommandListener
import com.tange.ai.tirtc.TiRtcConnState
import com.tange.ai.tirtc.TiRtcConnStateListener
import com.tange.ai.tirtc.TiRtcConnStreamMessageListener
import com.tange.ai.tirtc.TiRtcInitOptions
import com.tange.ai.tirtc.TiRtcInputErrorListener
import com.tange.ai.tirtc.TiRtcInputStateListener
import com.tange.ai.tirtc.TiRtcLogUploadCallback
import com.tange.ai.tirtc.TiRtcLogging
import com.tange.ai.tirtc.TiRawDump
import com.tange.ai.tirtc.TiRawDumpArchive
import com.tange.ai.tirtc.TiRawDumpStartCallback
import com.tange.ai.tirtc.TiRtcRawDumpOptions
import com.tange.ai.tirtc.TiRtcRecordingFile
import com.tange.ai.tirtc.TiRtcRecordingTask
import com.tange.ai.tirtc.TiRtcSnapshotFile
import com.tange.ai.tirtc.TiRtcVideoOutput
import com.tange.ai.tirtc.TiRtcVideoOutputErrorListener
import com.tange.ai.tirtc.TiRtcVideoOutputOptions
import com.tange.ai.tirtc.TiRtcVideoOutputRenderSizeListener
import com.tange.ai.tirtc.TiRtcVideoOutputState
import com.tange.ai.tirtc.TiRtcVideoOutputStateListener
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import org.json.JSONObject
import java.util.TimeZone
import java.util.Timer
import java.util.TimerTask

class MainActivity : AppCompatActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var settings = ExampleSettings()
    private var configureProduct = ConfigureProduct.RTC
    private var clientConfig =
        ClientConfiguration(
            appId = "",
            endpoint = "",
            remoteId = "",
            audioStreamId = DEFAULT_AUDIO_STREAM_ID,
            videoStreamIds = listOf(DEFAULT_VIDEO_STREAM_ID),
            token = "",
        )
    private var cloudStorageConfig = CloudStorageConfiguration()
    private var conn: TiRtcConn? = null
    private var audioOutput: TiRtcAudioOutput? = null
    private val videoOutputs = linkedMapOf<Int, TiRtcVideoOutput>()
    private val playerVideoLanes = linkedMapOf<Int, FrameLayout>()
    private val playerVideoStateLabels = linkedMapOf<Int, TextView>()
    private val playerUnavailableVideoStreamIds = mutableSetOf<Int>()
    private var selectedVideoStreamId: Int? = DEFAULT_VIDEO_STREAM_ID
    private var maximizedVideoStreamId: Int? = null
    private var recordingVideoStreamId: Int? = null
    private var playerLatestMediaTargetId: Int? = null
    private var playerAudioInput: TiRtcAudioInput? = null
    private var playerTalkbackRunning = false
    private var playerRunning = false
    private var playerConfig: ClientConfiguration? = null
    private var playerStage: FrameLayout? = null
    private var playerLocalAudioButton: TextView? = null
    private var playerOutputVolumeButton: TextView? = null
    private var playerDownlinkButton: TextView? = null
    private var playerRecordingButton: View? = null
    private var playerSnapshotButton: View? = null
    private var playerOutputMuted = false
    private var playerRecordingTask: TiRtcRecordingTask? = null
    private var playerLatestMediaFile: Any? = null
    private var playerGalleryButton: View? = null
    private var playerMoreButton: TextView? = null
    private val playerOwnedMediaFiles = mutableSetOf<Any>()
    private var playerMediaBusy = false
    private var metricsTimer: Timer? = null
    private var playerSessionGeneration = 0
    private var statusView: TextView? = null
    private var downlinkMetricsPanel: DownlinkMetricsPanel? = null
    private var streamBubble: TextView? = null
    private var commandHistoryView: TextView? = null
    private var commandHistory = "暂无命令记录"
    private var commandDialog: Dialog? = null
    private var activeScanner: DecoratedBarcodeView? = null
    private var scannerProcessing = false
    private var cloudStorageFlow: TiCloudStorageExampleFlow? = null
    private var cloudStorageSelectedRange: TiCloudStorageRecordingRange? = null
    private val cloudStorageSelectedDate: Calendar = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
    private val cloudStorageVisibleMonth: Calendar = Calendar.getInstance(TimeZone.getTimeZone("Asia/Shanghai"))
    private var cloudStorageRecordingsDialog: Dialog? = null
    private var cloudStorageRecordingsButton: View? = null
    private var cloudStorageRecordingsContent: LinearLayout? = null
    private var cloudStorageDayQueryGeneration = 0
    private var cloudStorageMonthQueryGeneration = 0
    private var cloudStorageExportProgress = -1
    private var cloudStorageRecordings: List<TiCloudStorageRecordingRange> = emptyList()
    private var cloudStorageStatusView: TextView? = null
    private var cloudStoragePlaybackStatus = "请选择录像"
    private var cloudStorageActionStatusGeneration = 0L
    private var cloudStorageActionStatusUntilMs = 0L
    private var cloudStorageTimeView: TextView? = null
    private var cloudStorageSeekBar: SeekBar? = null
    private var cloudStorageStage: FrameLayout? = null
    private var cloudStorageRecordingButton: TextView? = null
    private var cloudStorageSnapshotButton: TextView? = null
    private var cloudStorageGalleryButton: TextView? = null
    private var cloudStorageMuteButton: TextView? = null
    private var cloudStorageSpeedButton: TextView? = null
    private var cloudStoragePauseButton: TextView? = null
    private var cloudStorageMoreButton: TextView? = null
    private var cloudStorageMediaBusyOwner: TiCloudStorageExampleFlow? = null
    private var rawDump: TiRawDump? = null
    private var rawDumpButton: TextView? = null
    private var rawDumpArchiveReady = false
    private var rawDumpArchiveEvidence: TiRawDumpArchive? = null
    private var rawDumpBusy = false
    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        restoreMediaSelections()
        requestRuntimePermissions()
        showConfigure()
    }

    override fun onResume() {
        super.onResume()
        activeScanner?.resume()
    }

    override fun onPause() {
        activeScanner?.pause()
        super.onPause()
    }

    override fun onDestroy() {
        clearActiveScanner()
        closeCloudStorageFlow()
        stopPlayer()
        super.onDestroy()
    }

    private fun showConfigure() {
        clearActiveScanner()
        closeCloudStorageFlow()
        stopPlayer()
        statusView = null
        if (configureProduct == ConfigureProduct.CLOUD_STORAGE) {
            showCloudStorageConfigure()
        } else {
            showRtcConfigure()
        }
    }

    private fun showRtcConfigure() {
        val appIdField = editText("TiRTC 应用标识，进入播放页前必须提供。", clientConfig.appId, viewId = R.id.field_app_id)
        val endpointField = editText("接入的云端环境，留空则使用默认环境。", clientConfig.endpoint, viewId = R.id.field_endpoint)
        val remoteIdField = editText("待连接的远端目标 ID", clientConfig.remoteId, viewId = R.id.field_remote_id)
        val audioStreamField =
            editText(
                "留空不接收音频",
                clientConfig.audioStreamId?.toString().orEmpty(),
                viewId = R.id.field_audio_stream_id,
            )
        val videoStreamFields =
            clientConfig.videoStreamIds
                .mapIndexed { index, id ->
                    editText(
                        "留空不接收该路视频",
                        id.toString(),
                        viewId = if (index == 0) R.id.field_video_stream_id else View.generateViewId(),
                    )
                }.toMutableList()
        val videoFieldsContainer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        fun rebuildVideoFields() {
            videoFieldsContainer.removeAllViews()
            videoStreamFields.forEachIndexed { index, field ->
                (field.parent as? ViewGroup)?.removeView(field)
                field.id =
                    when (index) {
                        0 -> R.id.field_video_stream_id
                        1 -> R.id.field_video_stream_id_2
                        else -> R.id.field_video_stream_id_3
                    }
                videoFieldsContainer.addView(
                    LinearLayout(this).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER_VERTICAL
                        addView(body("${index + 1}"), LinearLayout.LayoutParams(dp(28), LinearLayout.LayoutParams.WRAP_CONTENT))
                        addView(field, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                        addView(
                            outlinedButton("−") {
                                videoStreamFields.removeAt(index)
                                rebuildVideoFields()
                            },
                            LinearLayout.LayoutParams(dp(52), dp(48)),
                        )
                    },
                )
            }
        }
        rebuildVideoFields()
        val tokenIssuerField = editText("例如 http://192.168.1.10:8966", clientConfig.tokenIssuerBaseUrl)
        val tokenField =
            editText(
                "进行一次连接所需的一次性 token",
                clientConfig.oneTimeToken.ifBlank { clientConfig.token },
                multiLine = true,
                viewId = R.id.field_token,
            )
        setContentView(
            page {
                header(
                    title = "Ti RTC",
                    primaryAction = "偏好设置" to { showSettings() },
                )
                addViewWithMargin(
                    productTabs(configureProduct) { product ->
                        configureProduct = product
                        showConfigure()
                    },
                    bottom = 20,
                )
                addViewWithMargin(
                    responsiveFormSections(
                        listOf(
                            formSection("连接") {
                                addViewWithMargin(fieldBlock("endpoint", endpointField), bottom = 12)
                                addViewWithMargin(fieldBlock("app_id", appIdField), bottom = 12)
                                addView(fieldBlock("remote_id", remoteIdField))
                            },
                            formSection("媒体") {
                                addViewWithMargin(fieldBlock("音频 Stream ID", audioStreamField), bottom = 12)
                                addViewWithMargin(
                                    LinearLayout(context).apply {
                                        orientation = LinearLayout.HORIZONTAL
                                        gravity = Gravity.CENTER_VERTICAL
                                        addView(
                                            body("视频 Stream ID（最多 3 路）"),
                                            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                                        )
                                        addView(
                                            outlinedButton("+") {
                                                if (videoStreamFields.size < 3) {
                                                    videoStreamFields.add(editText("留空不接收该路视频", "", viewId = View.generateViewId()))
                                                    rebuildVideoFields()
                                                }
                                            },
                                            LinearLayout.LayoutParams(dp(48), dp(48)),
                                        )
                                    },
                                    bottom = 4,
                                )
                                addView(videoFieldsContainer)
                            },
                            formSection("鉴权") {
                                addViewWithMargin(fieldBlock("一次性连接 Token", tokenField), bottom = 8)
                                addViewWithMargin(
                                    outlinedButton("扫描二维码") {
                                        showClientQr(appIdField, endpointField, remoteIdField, tokenField)
                                    }.apply { contentDescription = "扫描 RTC Token 二维码" },
                                    bottom = 12,
                                )
                                addView(fieldBlock("TiRTC DevTools 服务地址", tokenIssuerField))
                            },
                        ),
                    ),
                    bottom = 20,
                )
                addView(
                    primaryButton("开始连接、拉流播放") {
                        val next =
                            readClientConfig(
                                appIdField = appIdField,
                                endpointField = endpointField,
                                remoteIdField = remoteIdField,
                                audioStreamField = audioStreamField,
                                videoStreamFields = videoStreamFields,
                                tokenSource = if (tokenField.text.toString().trim().isNotEmpty()) 1 else 0,
                                tokenIssuerField = tokenIssuerField,
                                tokenField = tokenField,
                            ) ?: return@primaryButton
                        clientConfig = next
                        saveMediaSelections()
                        resolveTokenAndShowPlayer(next)
                    },
                )
                addView(linkButton("上传日志") { uploadLogs() })
            },
        )
    }

    private fun showCloudStorageConfigure() {
        val appIdField = editText("Ti Cloud Storage 应用标识", cloudStorageConfig.appId, viewId = R.id.field_cloud_storage_app_id)
        val endpointField =
            editText("留空则使用默认环境", cloudStorageConfig.endpoint, viewId = R.id.field_cloud_storage_endpoint)
        val tokenField =
            editText(
                "粘贴 Ti Cloud Storage APP Token",
                cloudStorageConfig.token,
                multiLine = true,
                isSecret = true,
                viewId = R.id.field_cloud_storage_token,
            )
        val audioChannelField =
            editText(
                "留空不接收音频",
                cloudStorageConfig.audioChannelId?.toString().orEmpty(),
                viewId = R.id.field_cloud_storage_audio_channel_id,
            )
        val videoChannelFields =
            cloudStorageConfig.videoChannelIds
                .mapIndexed { index, id ->
                    editText(
                        "留空不接收该路视频",
                        id.toString(),
                        viewId = if (index == 0) R.id.field_cloud_storage_video_channel_id else View.generateViewId(),
                    )
                }.toMutableList()
        val videoChannelsContainer = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        fun rebuildVideoChannels() {
            videoChannelsContainer.removeAllViews()
            videoChannelFields.forEachIndexed { index, field ->
                (field.parent as? ViewGroup)?.removeView(field)
                field.id =
                    when (index) {
                        0 -> R.id.field_cloud_storage_video_channel_id
                        1 -> R.id.field_cloud_storage_video_channel_id_2
                        else -> R.id.field_cloud_storage_video_channel_id_3
                    }
                videoChannelsContainer.addView(
                    LinearLayout(this).apply {
                        orientation = LinearLayout.HORIZONTAL
                        gravity = Gravity.CENTER_VERTICAL
                        addView(body("${index + 1}"), LinearLayout.LayoutParams(dp(28), LinearLayout.LayoutParams.WRAP_CONTENT))
                        addView(field, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                        addView(
                            outlinedButton("−") {
                                videoChannelFields.removeAt(index)
                                rebuildVideoChannels()
                            },
                            LinearLayout.LayoutParams(dp(52), dp(48)),
                        )
                    },
                )
            }
        }
        rebuildVideoChannels()
        setContentView(
            page {
                header(
                    title = "Ti RTC",
                    primaryAction = "偏好设置" to { showSettings() },
                )
                addViewWithMargin(
                    productTabs(configureProduct) { product ->
                        configureProduct = product
                        showConfigure()
                    },
                    bottom = 20,
                )
                addViewWithMargin(
                    responsiveFormSections(
                        listOf(
                            formSection("连接") {
                                addViewWithMargin(fieldBlock("app_id", appIdField), bottom = 12)
                                addView(fieldBlock("endpoint", endpointField))
                            },
                            formSection("鉴权") {
                                addViewWithMargin(fieldBlock("token", tokenField), bottom = 8)
                                addView(
                                    outlinedButton("扫描二维码") { showCloudStorageQr(appIdField, endpointField, tokenField) }.apply {
                                        contentDescription = "扫描云录像 Token 二维码"
                                    },
                                )
                            },
                            formSection("媒体") {
                                addViewWithMargin(fieldBlock("音频 Channel ID", audioChannelField), bottom = 12)
                                addViewWithMargin(
                                    LinearLayout(context).apply {
                                        orientation = LinearLayout.HORIZONTAL
                                        gravity = Gravity.CENTER_VERTICAL
                                        addView(
                                            body("视频 Channel ID（最多 3 路）"),
                                            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                                        )
                                        addView(
                                            outlinedButton("+") {
                                                if (videoChannelFields.size < 3) {
                                                    videoChannelFields.add(editText("留空不接收该路视频", "", viewId = View.generateViewId()))
                                                    rebuildVideoChannels()
                                                }
                                            },
                                            LinearLayout.LayoutParams(dp(48), dp(48)),
                                        )
                                    },
                                    bottom = 4,
                                )
                                addView(videoChannelsContainer)
                            },
                        ),
                    ),
                    bottom = 20,
                )
                addView(
                    primaryButton("播放云录像") {
                        val appId = appIdField.text.toString().trim()
                        val token = tokenField.text.toString().trim()
                        val audioChannelText = audioChannelField.text.toString().trim()
                        val videoChannelTexts = videoChannelFields.map { it.text.toString().trim() }.filter(String::isNotEmpty)
                        val audioChannel = audioChannelText.takeIf(String::isNotEmpty)?.toIntOrNull()
                        val videoChannels = videoChannelTexts.mapNotNull { it.toIntOrNull() }
                        if (appId.isEmpty() || token.isEmpty() ||
                            audioChannelText.isNotEmpty() && audioChannel == null ||
                            videoChannels.size != videoChannelTexts.size ||
                            audioChannel != null && audioChannel !in 0..255 ||
                            videoChannels.any { it !in 0..255 } || videoChannels.distinct().size != videoChannels.size
                        ) {
                            toast("请填写 app_id、token 和有效 channel_id。")
                            return@primaryButton
                        }
                        val next =
                            CloudStorageConfiguration(
                                appId = appId,
                                endpoint = endpointField.text.toString().trim(),
                                token = token,
                                audioChannelId = audioChannel,
                                videoChannelIds = videoChannels,
                            )
                        cloudStorageConfig = next
                        saveMediaSelections()
                        showCloudStoragePlayer(next)
                    },
                )
                addView(linkButton("上传日志") { uploadLogs() })
            },
        )
    }

    private fun showCloudStoragePlayer(config: CloudStorageConfiguration) {
        clearActiveScanner()
        stopPlayer()
        closeCloudStorageFlow()
        val flow = TiCloudStorageExampleFlow()
        cloudStorageFlow = flow
        cloudStorageSelectedRange = null
        val status = body("正在初始化云录像…").apply { id = R.id.cloud_storage_status }
        val time = body("--:--:-- / --:--:--").apply { id = R.id.cloud_storage_seek_time }
        val seek = cloudStorageSeekBar(flow)
        val recording =
            playbackControlButton("●", "开始录屏") { toggleCloudStorageRecording(flow, config) }.apply {
                id = R.id.cloud_storage_recording_button
            }
        val snapshot =
            playbackControlButton("▣", "截图") { takeCloudStorageSnapshot(flow) }.apply {
                id = R.id.cloud_storage_snapshot_button
            }
        val gallery =
            playbackControlButton("□", "保存到系统相册") { saveCloudStorageMediaToGallery(flow) }.apply {
                id = R.id.cloud_storage_gallery_button
            }
        val mute =
            playbackControlButton("🔊", "静音", wideText = "静音") {
                val code = flow.toggleMute()
                val message =
                    if (code == 0) {
                        if (flow.muted) "已静音" else "已恢复声音"
                    } else {
                        "音量设置失败：$code"
                    }
                updateCloudStorageStatus(message)
                updateCloudStorageControls()
            }.apply { id = R.id.cloud_storage_mute_button }
        val speed =
            playbackControlButton("1×", "播放倍速", wideText = "倍速 x1") {
                val values = TiCloudStorageReplaySpeed.entries
                val next = values[(values.indexOf(flow.speed) + 1) % values.size]
                val code = flow.setSpeed(next)
                updateCloudStorageStatus(if (code == 0) "播放倍速：${cloudStorageSpeedLabel(next)}" else "倍速设置失败：$code")
                updateCloudStorageControls()
            }.apply { id = R.id.cloud_storage_speed_button }
        val pause =
            playbackControlButton("Ⅱ", "暂停播放", wideText = "暂停", emphasized = true) {
                val code = if (flow.paused) flow.resume() else flow.pause()
                if (code != 0) updateCloudStorageStatus("暂停操作失败：$code")
                updateCloudStorageControls()
            }.apply { id = R.id.cloud_storage_pause_button }
        lateinit var more: TextView
        more =
            playbackMoreButton {
                showPlaybackActionMenu(
                    more,
                    listOf(
                        PlaybackMenuAction(
                            R.id.cloud_storage_recording_button,
                            if (flow.isRecording) "结束录屏" else "开始录屏",
                            "cloud_storage_action_recording",
                            enabled = { cloudActionEnabled(PlaybackMediaAction.RECORDING, cloudPlaybackActionState(flow)) },
                            unavailableMessage = { if (cloudStorageMediaBusyOwner === flow) "媒体操作进行中" else "请先选择并播放录像" },
                            dispatch = { toggleCloudStorageRecording(flow, config) },
                        ),
                        PlaybackMenuAction(
                            R.id.cloud_storage_snapshot_button,
                            "截图",
                            "cloud_storage_action_snapshot",
                            enabled = { cloudActionEnabled(PlaybackMediaAction.SNAPSHOT, cloudPlaybackActionState(flow)) },
                            unavailableMessage = { if (cloudStorageMediaBusyOwner === flow) "媒体操作进行中" else "请先选择并播放录像" },
                            dispatch = { takeCloudStorageSnapshot(flow) },
                        ),
                        PlaybackMenuAction(
                            R.id.cloud_storage_gallery_button,
                            "保存到系统相册",
                            "cloud_storage_action_gallery",
                            enabled = { cloudActionEnabled(PlaybackMediaAction.GALLERY, cloudPlaybackActionState(flow)) },
                            unavailableMessage = { if (cloudStorageMediaBusyOwner === flow) "媒体操作进行中" else "还没有可保存的媒体文件" },
                            dispatch = { saveCloudStorageMediaToGallery(flow) },
                        ),
                    ),
                    ::updateCloudStorageStatus,
                )
            }.apply { id = R.id.cloud_storage_more_button }
        cloudStorageMoreButton = more
        cloudStorageStatusView = status
        cloudStorageTimeView = time
        cloudStorageSeekBar = seek
        cloudStorageRecordingButton = recording
        cloudStorageSnapshotButton = snapshot
        cloudStorageGalleryButton = gallery
        cloudStorageMuteButton = mute
        cloudStorageSpeedButton = speed
        cloudStoragePauseButton = pause
        val stage = videoPanel("请选择录像").apply { id = R.id.cloud_storage_video_stage }
        cloudStorageStage = stage
        val controls = cloudStoragePlayerControls(time, seek, recording, snapshot, gallery, mute, speed, pause, more)
        val rawDumpControl =
            createRawDumpButton { callback ->
                flow.startRawDump(config.audioChannelId, config.videoChannelIds, callback)
            }
        rawDumpButton = rawDumpControl
        setContentView(
            frameScreen(
                top =
                    cloudStoragePlayerTopBar(
                        onBack = {
                            closeCloudStorageFlow {
                                configureProduct = ConfigureProduct.CLOUD_STORAGE
                                showConfigure()
                            }
                        },
                        onSelectRecording = { showCloudStorageRecordingsDialog(flow, config, query = false) },
                        onUploadLogs = { uploadCloudStorageLogs() },
                    ),
                stage = stage,
                overlay = playbackStatusSurface(status),
                bottom = controls,
            ).apply { addRawDumpOverlay(rawDumpControl) },
        )
        cloudStorageRecordingsButton = findViewById(R.id.cloud_storage_recordings_button)
        bindCloudStorageFlowCallbacks(flow)
        val initCode = flow.initialize(this, config.appId, config.endpoint, config.token)
        if (initCode != 0) {
            updateCloudStorageStatus("初始化失败：$initCode")
            updateCloudStorageControls()
            return
        }
        updateCloudStorageStatus("请选择录像")
        updateCloudStorageControls()
        mainHandler.post { if (cloudStorageFlow === flow) showCloudStorageRecordingsDialog(flow, config, query = true) }
    }

    private fun cloudStorageSeekBar(flow: TiCloudStorageExampleFlow): SeekBar =
        SeekBar(this).apply {
            id = R.id.cloud_storage_seek_bar
            max = CLOUD_STORAGE_SEEK_MAX
            isEnabled = false
            setOnSeekBarChangeListener(
                object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(
                        seekBar: SeekBar?,
                        progress: Int,
                        fromUser: Boolean,
                    ) {
                        if (fromUser) updateCloudStorageSeekLabel(progress)
                    }

                    override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit

                    override fun onStopTrackingTouch(seekBar: SeekBar?) {
                        val range = cloudStorageSelectedRange ?: return
                        val progress = seekBar?.progress ?: return
                        val target = range.startTimeMs + (range.endTimeMs - range.startTimeMs) * progress / CLOUD_STORAGE_SEEK_MAX
                        val code = flow.seek(target)
                        updateCloudStorageStatus(if (code == 0) "已跳转到 ${formatCloudStorageTime(target)}" else "跳转失败：$code")
                    }
                },
            )
        }

    private fun bindCloudStorageFlowCallbacks(flow: TiCloudStorageExampleFlow) {
        flow.onTimeChanged = { timeMs ->
            if (cloudStorageFlow === flow) updateCloudStorageProgress(timeMs)
        }
        flow.onReplayCompleted = {
            if (cloudStorageFlow === flow) updateCloudStoragePlaybackStatus("录像播放完成")
        }
        flow.onVideoStateChanged = { channelId, state ->
            if (cloudStorageFlow === flow) {
                updateCloudStoragePlaybackStatus("视频 Channel $channelId · ${cloudStorageVideoStateLabel(state)}")
                updateCloudStorageControls()
            }
        }
        flow.onAudioStateChanged = { state ->
            if (cloudStorageFlow === flow && state.name == "FAILED") updateCloudStorageStatus("音频输出失败")
        }
        flow.onError = { code ->
            if (cloudStorageFlow === flow) updateCloudStorageStatus("播放失败：$code")
        }
    }

    private fun showCloudStorageRecordingsDialog(
        flow: TiCloudStorageExampleFlow,
        config: CloudStorageConfiguration,
        query: Boolean,
    ) {
        if (cloudStorageFlow !== flow || isFinishing) return
        cloudStorageRecordingsDialog?.dismiss()
        val dateRow =
            LinearLayout(this).apply {
                id = R.id.cloud_storage_recordings_date_row
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(
                    LinearLayout(context).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(
                            TextView(context).apply {
                                text = cloudStorageDateLabel()
                                setTextColor(ExampleTheme.textPrimary)
                                textSize = 15f
                            },
                        )
                        addView(
                            TextView(context).apply {
                                text = "自然日按 Asia/Shanghai 查询"
                                setTextColor(ExampleTheme.textSecondary)
                                textSize = 12f
                            },
                        )
                    },
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
                addView(
                    appBarActionButton("重新查询") {
                        queryCloudStorageRecordings(flow, config)
                    }.apply { id = R.id.cloud_storage_query_button },
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(ExampleTheme.minimumTouchTargetDp)),
                )
            }
        val content =
            LinearLayout(this).apply {
                id = R.id.cloud_storage_recordings_list
                orientation = LinearLayout.VERTICAL
                setPadding(dp(18), dp(8), dp(18), dp(12))
            }
        cloudStorageRecordingsContent = content
        val root =
            LinearLayout(this).apply {
                id = R.id.cloud_storage_recordings_sheet
                orientation = LinearLayout.VERTICAL
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                setPadding(0, dp(6), 0, dp(12))
                setBackgroundColor(ExampleTheme.background)
                addView(
                    View(context).apply {
                        id = R.id.cloud_storage_sheet_drag_handle
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                        setBackgroundColor(ExampleTheme.inputBorder)
                    },
                    LinearLayout.LayoutParams(dp(40), dp(4)).apply {
                        gravity = Gravity.CENTER_HORIZONTAL
                    },
                )
                addView(
                    ScrollView(this@MainActivity).apply {
                        isFillViewport = true
                        addView(
                            LinearLayout(context).apply {
                                orientation = LinearLayout.VERTICAL
                                addViewWithMargin(
                                    dateRow.apply { setPadding(dp(18), dp(10), dp(18), dp(10)) },
                                    top = dp(2),
                                    bottom = 0,
                                )
                                addView(cloudStorageMonthCalendar(flow, config))
                                addView(
                                    View(context).apply { setBackgroundColor(ExampleTheme.inputBorder) },
                                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1),
                                )
                                addView(content)
                            },
                        )
                    },
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f),
                )
            }
        root.layoutParams =
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                (resources.displayMetrics.heightPixels * 0.88).toInt(),
            )
        val dialog = BottomSheetDialog(this)
        dialog.setContentView(root)
        dialog.setOnDismissListener {
            if (cloudStorageRecordingsDialog === dialog) {
                cloudStorageRecordingsDialog = null
                cloudStorageRecordingsContent = null
            }
            cloudStorageRecordingsButton?.requestFocus()
        }
        dialog.behavior.apply {
            peekHeight = root.layoutParams.height
            isFitToContents = true
        }
        cloudStorageRecordingsDialog = dialog
        dialog.show()
        if (resources.configuration.screenWidthDp >= ExampleTheme.compactBreakpointDp) {
            dialog.window?.setLayout(
                dp(minOf(ExampleTheme.dialogMaxWidthDp, resources.configuration.screenWidthDp - 32)),
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }
        dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED
        if (query) queryCloudStorageRecordings(flow, config) else renderCloudStorageRecordings(cloudStorageRecordings, null, flow, config)
    }

    private fun queryCloudStorageRecordings(
        flow: TiCloudStorageExampleFlow,
        config: CloudStorageConfiguration,
    ) {
        if (cloudStorageFlow !== flow) return
        val generation = ++cloudStorageDayQueryGeneration
        renderCloudStorageRecordings(emptyList(), "正在查询…")
        val bounds = cloudStorageQueryBounds()
        val accepted =
            flow.query(bounds.first, bounds.second) { result ->
                if (cloudStorageFlow !== flow || generation != cloudStorageDayQueryGeneration) return@query
                if (result.code != 0) {
                    cloudStorageRecordings = emptyList()
                    renderCloudStorageRecordings(emptyList(), "查询失败：${result.code}")
                    updateCloudStorageStatus("查询失败：${result.code}")
                } else {
                    val recordings =
                        result.recordings.sortedWith(
                            compareByDescending<TiCloudStorageRecordingRange> { it.startTimeMs }
                                .thenByDescending { it.endTimeMs },
                        )
                    cloudStorageRecordings = recordings
                    renderCloudStorageRecordings(recordings, null, flow, config)
                    updateCloudStorageStatus("查询完成：${result.recordings.size} 段录像")
                }
            }
        if (accepted != 0) {
            renderCloudStorageRecordings(emptyList(), "查询启动失败：$accepted")
            updateCloudStorageStatus("查询启动失败：$accepted")
        }
    }

    private fun cloudStorageMonthCalendar(
        flow: TiCloudStorageExampleFlow,
        config: CloudStorageConfiguration,
    ): View {
        val title = body("").apply { gravity = Gravity.CENTER }
        val grid = GridLayout(this).apply {
            id = R.id.cloud_storage_calendar_grid
            columnCount = 7
        }
        var availableDays: Set<String> = emptySet()
        lateinit var render: () -> Unit
        lateinit var load: () -> Unit
        render = {
            title.text =
                SimpleDateFormat("yyyy-MM", Locale.ROOT).apply {
                    timeZone = TimeZone.getTimeZone("Asia/Shanghai")
                }.format(cloudStorageVisibleMonth.time)
            grid.removeAllViews()
            val first = cloudStorageVisibleMonth.clone() as Calendar
            first.set(Calendar.DAY_OF_MONTH, 1)
            val leading = first.get(Calendar.DAY_OF_WEEK) - Calendar.SUNDAY
            repeat(leading) {
                grid.addView(
                    space(dp(1)),
                    GridLayout.LayoutParams().apply {
                        width = dp(ExampleTheme.minimumTouchTargetDp)
                        height = dp(ExampleTheme.minimumTouchTargetDp)
                        columnSpec = GridLayout.spec(GridLayout.UNDEFINED)
                    },
                )
            }
            val lastDay = first.getActualMaximum(Calendar.DAY_OF_MONTH)
            for (day in 1..lastDay) {
                val date = first.clone() as Calendar
                date.set(Calendar.DAY_OF_MONTH, day)
                val key = cloudStorageDateKey(date)
                val selected = key == cloudStorageDateLabel()
                val available = key in availableDays
                val button =
                    if (selected) {
                        compactFilledButton(calendarDayText(day, available)) {}
                    } else {
                        outlinedButton(calendarDayText(day, available)) {}
                    }
                button.apply {
                    minHeight = dp(ExampleTheme.minimumTouchTargetDp)
                    minWidth = dp(ExampleTheme.minimumTouchTargetDp)
                    textSize = 12f
                    setPadding(0, dp(4), 0, dp(4))
                    contentDescription = calendarDayDescription(key, available, selected)
                    isEnabled = available
                    alpha = if (isEnabled) 1f else 0.34f
                    setOnClickListener {
                        cloudStorageSelectedDate.timeInMillis = date.timeInMillis
                        render()
                        queryCloudStorageRecordings(flow, config)
                    }
                }
                grid.addView(
                    button,
                    GridLayout.LayoutParams().apply {
                        width = dp(ExampleTheme.minimumTouchTargetDp)
                        height = ViewGroup.LayoutParams.WRAP_CONTENT
                        setMargins(dp(1), dp(1), dp(1), dp(1))
                        columnSpec = GridLayout.spec(GridLayout.UNDEFINED)
                    },
                )
            }
        }
        load = {
            val generation = ++cloudStorageMonthQueryGeneration
            availableDays = emptySet()
            render()
            val first = cloudStorageVisibleMonth.clone() as Calendar
            first.set(Calendar.DAY_OF_MONTH, 1)
            val last = first.clone() as Calendar
            last.set(Calendar.DAY_OF_MONTH, last.getActualMaximum(Calendar.DAY_OF_MONTH))
            val accepted =
                flow.queryDays(cloudStorageDateKey(first), cloudStorageDateKey(last), "Asia/Shanghai") { result ->
                    if (cloudStorageFlow !== flow || generation != cloudStorageMonthQueryGeneration) return@queryDays
                    availableDays = result.days.filter { it.hasRecording }.map { it.date }.toSet()
                    render()
                    if (result.code != 0) updateCloudStorageStatus("月份加载失败：${result.code}，切换月份可重试")
                }
            if (accepted != 0) updateCloudStorageStatus("月份加载启动失败：$accepted")
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(4), dp(18), dp(8))
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(
                        appBarActionButton("上个月") {
                            cloudStorageVisibleMonth.add(Calendar.MONTH, -1)
                            load()
                        },
                    )
                    addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                    addView(
                        appBarActionButton("下个月") {
                            cloudStorageVisibleMonth.add(Calendar.MONTH, 1)
                            load()
                        },
                    )
                },
            )
            addView(
                HorizontalScrollView(context).apply {
                    isFillViewport = false
                    addView(
                        LinearLayout(context).apply {
                            orientation = LinearLayout.VERTICAL
                            addView(
                                LinearLayout(context).apply {
                                    orientation = LinearLayout.HORIZONTAL
                                    listOf("日", "一", "二", "三", "四", "五", "六").forEach { weekday ->
                                        addView(
                                            body(weekday).apply { gravity = Gravity.CENTER },
                                            LinearLayout.LayoutParams(
                                                dp(ExampleTheme.minimumTouchTargetDp),
                                                dp(ExampleTheme.minimumTouchTargetDp),
                                            ),
                                        )
                                    }
                                },
                            )
                            addView(grid)
                        },
                    )
                },
            )
            post {
                render()
                load()
            }
        }
    }

    private fun renderCloudStorageRecordings(
        recordings: List<TiCloudStorageRecordingRange>,
        message: String?,
        flow: TiCloudStorageExampleFlow? = null,
        config: CloudStorageConfiguration? = null,
    ) {
        val content = cloudStorageRecordingsContent ?: return
        content.removeAllViews()
        if (message != null) {
            val state =
                LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.CENTER_HORIZONTAL
                    addView(
                        TextView(context).apply {
                            text = message
                            setTextColor(ExampleTheme.textSecondary)
                            gravity = Gravity.CENTER
                        },
                    )
                    if (message.contains("正在查询")) {
                        addViewWithMargin(ProgressBar(this@MainActivity), top = dp(12), bottom = 0)
                    } else if (message.contains("查询失败")) {
                        addViewWithMargin(
                            appBarActionButton("重试") {
                                if (flow != null && config != null) queryCloudStorageRecordings(flow, config)
                            }.apply { id = R.id.cloud_storage_query_retry_button },
                            top = dp(12),
                            bottom = 0,
                        )
                    }
                }
            content.addViewWithMargin(state, top = dp(12), bottom = dp(12))
            return
        }
        if (recordings.isEmpty()) {
            content.addView(body("当天没有可用录像"))
            return
        }
        val exportBusy = cloudStorageExportProgress >= 0
        recordings.forEachIndexed { index, range ->
            val row =
                LinearLayout(this).apply {
                    id = R.id.cloud_storage_recording_play
                    contentDescription = "播放录像"
                    gravity = Gravity.CENTER_VERTICAL
                    orientation = LinearLayout.HORIZONTAL
                    isClickable = true
                    isFocusable = true
                    setOnClickListener {
                        cloudStorageRecordingsDialog?.dismiss()
                        if (flow != null && config != null) playCloudStorageRecording(flow, config, range)
                    }
                    val label =
                        TextView(context).apply {
                            id = R.id.cloud_storage_recording_row_label
                            text =
                                "${formatCloudStorageTime(range.startTimeMs)} — ${formatCloudStorageTime(range.endTimeMs)}\n" +
                                formatCloudStorageDuration(range.endTimeMs - range.startTimeMs)
                            setTextColor(ExampleTheme.textPrimary)
                            textSize = 14f
                            setPadding(dp(8), dp(12), dp(8), dp(12))
                        }
                    addView(label, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                    addView(
                        appBarActionButton(if (exportBusy) "$cloudStorageExportProgress%" else "下载") {
                            if (flow != null && config != null) exportCloudStorageRecording(flow, config, range)
                        }.apply {
                            id = R.id.cloud_storage_range_export
                            isEnabled = !exportBusy
                            alpha = if (exportBusy) 0.6f else 1f
                        },
                        LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(40)),
                    )
                }
            content.addViewWithMargin(row, top = if (index == 0) 0 else dp(6), bottom = 6)
            if (index < recordings.lastIndex) {
                content.addView(
                    View(content.context).apply { setBackgroundColor(ExampleTheme.inputBorder) },
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1),
                )
            }
        }
    }

    private fun playCloudStorageRecording(
        flow: TiCloudStorageExampleFlow,
        config: CloudStorageConfiguration,
        range: TiCloudStorageRecordingRange,
    ) {
        val stage = cloudStorageStage
        if (stage == null) {
            updateCloudStorageStatus("播放区域不可用")
            return
        }
        if (config.videoChannelIds.isEmpty() && config.audioChannelId == null) {
            updateCloudStorageStatus("请至少选择一路音频或视频")
            return
        }
        val code = flow.play(range, stage, config.videoChannelIds, config.audioChannelId)
        if (code == 0) {
            cloudStorageSelectedRange = range
            updateCloudStorageProgress(range.startTimeMs)
        } else {
            updateCloudStorageStatus("播放启动失败：$code")
        }
        updateCloudStorageControls()
    }

    private fun toggleCloudStorageRecording(
        flow: TiCloudStorageExampleFlow,
        config: CloudStorageConfiguration,
    ) {
        if (cloudStorageMediaBusyOwner != null) return
        if (flow.selectedVideoChannelId == null) {
            updateCloudStorageStatus("当前没有可用视频")
            return
        }
        cloudStorageMediaBusyOwner = flow
        updateCloudStorageControls()
        val code =
            flow.toggleRecording(flow.selectedVideoChannelId ?: return, config.audioChannelId) { started, resultCode, path ->
                if (cloudStorageFlow !== flow) return@toggleRecording
                if (cloudStorageMediaBusyOwner === flow) cloudStorageMediaBusyOwner = null
                updateCloudStorageStatus(
                    when {
                        resultCode != 0 -> "边播边录失败：$resultCode"
                        started -> "边播边录已开始"
                        else -> "边播边录完成${path?.let { "：$it" }.orEmpty()}"
                    },
                )
                updateCloudStorageControls()
            }
        if (code != 0) {
            if (cloudStorageMediaBusyOwner === flow) cloudStorageMediaBusyOwner = null
            updateCloudStorageStatus("边播边录操作失败：$code")
        }
        updateCloudStorageControls()
    }

    private fun takeCloudStorageSnapshot(flow: TiCloudStorageExampleFlow) {
        if (cloudStorageMediaBusyOwner != null) return
        if (flow.selectedVideoChannelId == null) {
            updateCloudStorageStatus("当前没有可用视频")
            return
        }
        cloudStorageMediaBusyOwner = flow
        updateCloudStorageControls()
        val code =
            flow.takeSnapshot(flow.selectedVideoChannelId ?: return) { resultCode, path ->
                if (cloudStorageFlow !== flow) return@takeSnapshot
                if (cloudStorageMediaBusyOwner === flow) cloudStorageMediaBusyOwner = null
                updateCloudStorageStatus(if (resultCode == 0) "截图完成${path?.let { "：$it" }.orEmpty()}" else "截图失败：$resultCode")
                updateCloudStorageControls()
            }
        if (code != 0) {
            if (cloudStorageMediaBusyOwner === flow) cloudStorageMediaBusyOwner = null
            updateCloudStorageStatus("截图启动失败：$code")
        }
        updateCloudStorageControls()
    }

    private fun exportCloudStorageRecording(
        flow: TiCloudStorageExampleFlow,
        config: CloudStorageConfiguration,
        range: TiCloudStorageRecordingRange,
    ) {
        if (cloudStorageExportProgress >= 0) return
        cloudStorageExportProgress = 0
        renderCloudStorageRecordings(cloudStorageRecordings, null, flow, config)
        val code =
            flow.export(
                range,
                flow.selectedVideoChannelId ?: return,
                config.audioChannelId,
                onProgress = { progress ->
                    if (cloudStorageFlow !== flow) return@export
                    cloudStorageExportProgress = ((progress * 100).toInt()).coerceIn(0, 99)
                    renderCloudStorageRecordings(cloudStorageRecordings, null, flow, config)
                    updateCloudStorageStatus("范围下载 $cloudStorageExportProgress%")
                },
                onProgressDetail = { progress ->
                    if (cloudStorageFlow !== flow) return@export
                    updateCloudStorageStatus("范围下载已覆盖 ${progress.coveredDurationMs} ms")
                },
                onRecordingGap = { gap ->
                    if (cloudStorageFlow !== flow) return@export
                    updateCloudStorageStatus(
                        "录像缺口 ${gap.range.startTimeMs}..${gap.range.endTimeMs}，原因 ${gap.reasons.joinToString()}",
                    )
                },
            ) { resultCode, path, report ->
                if (cloudStorageFlow !== flow) return@export
                cloudStorageExportProgress = -1
                renderCloudStorageRecordings(cloudStorageRecordings, null, flow, config)
                updateCloudStorageStatus(
                    if (resultCode == 0) {
                        "范围下载完成${path?.let { "：$it" }.orEmpty()}，覆盖 ${report?.coveredDurationMs ?: 0} ms，完整 ${report?.complete == true}"
                    } else {
                        "范围下载失败：$resultCode，终止 ${report?.termination}"
                    },
                )
                updateCloudStorageControls()
            }
        if (code == 0) {
            updateCloudStorageStatus("范围下载已开始")
        } else {
            cloudStorageExportProgress = -1
            renderCloudStorageRecordings(cloudStorageRecordings, null, flow, config)
            updateCloudStorageStatus("范围下载启动失败：$code")
        }
        updateCloudStorageControls()
    }

    private fun saveCloudStorageMediaToGallery(flow: TiCloudStorageExampleFlow) {
        if (cloudStorageMediaBusyOwner != null) return
        cloudStorageMediaBusyOwner = flow
        updateCloudStorageControls()
        val code =
            flow.saveLatestToGallery { resultCode ->
                if (cloudStorageFlow !== flow) return@saveLatestToGallery
                if (cloudStorageMediaBusyOwner === flow) cloudStorageMediaBusyOwner = null
                updateCloudStorageStatus(if (resultCode == 0) "已保存到系统相册" else "保存到相册失败：$resultCode")
                updateCloudStorageControls()
            }
        if (code != 0) {
            if (cloudStorageMediaBusyOwner === flow) cloudStorageMediaBusyOwner = null
            updateCloudStorageStatus("保存到相册启动失败：$code")
            updateCloudStorageControls()
        }
    }

    private fun uploadCloudStorageLogs() {
        finishRawDump(upload = false, completion = { uploadCloudStorageLogsNow() })
    }

    private fun uploadCloudStorageLogsNow() {
        updateCloudStorageStatus("正在上传日志…")
        val code =
            TiRtcLogging.upload(
                TiRtcLogUploadCallback { resultCode, logId ->
                    updateCloudStorageStatus(
                        if (resultCode == 0) "日志上传完成：${logId.orEmpty()}" else "日志上传失败：$resultCode",
                    )
                },
            )
        if (code != 0) updateCloudStorageStatus("日志上传启动失败：$code")
    }

    private fun createRawDumpButton(start: (TiRawDumpStartCallback) -> Boolean): TextView =
        TextView(this).apply {
            id = R.id.raw_dump_button
            text = "抓数据"
            contentDescription = "抓数据"
            gravity = Gravity.CENTER
            textSize = 11f
            setTextColor(0xFFFFFFFF.toInt())
            background =
                android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(ExampleTheme.primary)
                }
            setOnClickListener {
                if (rawDumpBusy) return@setOnClickListener
                if (rawDump != null) {
                    finishRawDump(upload = true)
                } else if (rawDumpArchiveReady) {
                    uploadRawDumpArchive()
                } else {
                    rawDumpBusy = true
                    renderRawDumpButton("准备中", enabled = false)
                    val accepted =
                        start(
                            TiRawDumpStartCallback { result ->
                                rawDumpBusy = false
                                if (result.code == 0 && result.dump != null) {
                                    rawDump = result.dump
                                    rawDumpArchiveReady = false
                                    rawDumpArchiveEvidence = null
                                    renderRawDumpButton("结束上传", enabled = true)
                                } else {
                                    renderRawDumpButton("重新抓取", enabled = true)
                                }
                            },
                        )
                    if (!accepted) {
                        rawDumpBusy = false
                        renderRawDumpButton("重新抓取", enabled = true)
                    }
                }
            }
        }

    private fun FrameLayout.addRawDumpOverlay(button: View) {
        addView(
            button,
            FrameLayout.LayoutParams(
                dp(RAW_DUMP_BUTTON_SIZE_DP),
                dp(RAW_DUMP_BUTTON_SIZE_DP),
                Gravity.START or Gravity.CENTER_VERTICAL,
            ).apply {
                leftMargin = dp(RAW_DUMP_BUTTON_LEFT_INSET_DP)
            },
        )
    }

    private fun renderRawDumpButton(label: String, enabled: Boolean) {
        mainHandler.post {
            rawDumpButton?.apply {
                text = label
                contentDescription = label
                isEnabled = enabled
                alpha = if (enabled) 1f else 0.6f
            }
        }
    }

    private fun finishRawDump(
        upload: Boolean,
        completion: () -> Unit = {},
        retryCount: Int = 0,
    ) {
        val active = rawDump
        if (active == null) {
            if (upload && rawDumpArchiveReady) uploadRawDumpArchive(completion) else completion()
            return
        }
        if (rawDumpBusy) return
        rawDumpBusy = true
        renderRawDumpButton("打包中", enabled = false)
        active.stop { result ->
            val archive = result.archive
            if (result.code == 0 && archive != null) {
                rawDumpBusy = false
                rawDump = null
                rawDumpArchiveReady = true
                rawDumpArchiveEvidence = archive
                emitRawDumpEvidence(
                    "stop",
                    JSONObject()
                        .put("capture_id", archive.captureId)
                        .put("archive_sha256", archive.sha256)
                        .put("archive_path", archive.path),
                )
                renderRawDumpButton("上传数据", enabled = true)
                if (upload) uploadRawDumpArchive(completion) else completion()
            } else if (result.code == TiCloudStorageErrorCode.IN_USE) {
                if (retryCount < RAW_DUMP_STOP_RETRY_LIMIT) {
                    renderRawDumpButton("打包中", enabled = false)
                    mainHandler.postDelayed(
                        {
                            rawDumpBusy = false
                            if (rawDump === active) {
                                finishRawDump(upload, completion, retryCount + 1)
                            } else {
                                completion()
                            }
                        },
                        RAW_DUMP_STOP_RETRY_DELAY_MS,
                    )
                } else {
                    rawDumpBusy = false
                    renderRawDumpButton("重试结束", enabled = true)
                }
            } else {
                rawDumpBusy = false
                rawDump = null
                renderRawDumpButton("重新抓取", enabled = true)
                completion()
            }
        }
    }

    private fun uploadRawDumpArchive(completion: () -> Unit = {}) {
        if (!rawDumpArchiveReady || rawDumpBusy) {
            completion()
            return
        }
        rawDumpBusy = true
        renderRawDumpButton("上传中", enabled = false)
        val code =
            TiRtcLogging.upload(
                TiRtcLogUploadCallback { resultCode, logId ->
                    rawDumpBusy = false
                    emitRawDumpEvidence(
                        "upload",
                        JSONObject()
                            .put("code", resultCode)
                            .put("log_id", logId.orEmpty())
                            .put("capture_id", rawDumpArchiveEvidence?.captureId.orEmpty())
                            .put("archive_sha256", rawDumpArchiveEvidence?.sha256.orEmpty())
                            .put("archive_path", rawDumpArchiveEvidence?.path.orEmpty()),
                    )
                    if (resultCode == 0) {
                        rawDumpArchiveReady = false
                        renderRawDumpButton("抓数据", enabled = true)
                    } else {
                        renderRawDumpButton("重试上传", enabled = true)
                    }
                    completion()
                },
            )
        if (code != 0) {
            rawDumpBusy = false
            renderRawDumpButton("重试上传", enabled = true)
            completion()
        }
    }

    private fun emitRawDumpEvidence(event: String, payload: JSONObject) {
        val encoded =
            Base64.encodeToString(
                payload.toString().toByteArray(Charsets.UTF_8),
                Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
            )
        Log.i(RAW_DUMP_EVIDENCE_TAG, "raw_dump_evidence_${event}_b64=$encoded")
    }

    private fun updateCloudStorageStatus(message: String) {
        mainHandler.post {
            val target = cloudStorageStatusView ?: return@post
            cloudStorageActionStatusGeneration += 1
            val generation = cloudStorageActionStatusGeneration
            cloudStorageActionStatusUntilMs = SystemClock.uptimeMillis() + CLOUD_STORAGE_ACTION_STATUS_DURATION_MS
            target.text = message
            mainHandler.postDelayed(
                {
                    if (cloudStorageStatusView === target && cloudStorageActionStatusGeneration == generation) {
                        cloudStorageActionStatusUntilMs = 0L
                        target.text = cloudStoragePlaybackStatus
                    }
                },
                CLOUD_STORAGE_ACTION_STATUS_DURATION_MS,
            )
        }
    }

    private fun updateCloudStoragePlaybackStatus(message: String) {
        mainHandler.post {
            cloudStoragePlaybackStatus = message
            if (SystemClock.uptimeMillis() >= cloudStorageActionStatusUntilMs) {
                cloudStorageStatusView?.text = message
            }
        }
    }

    private fun updateCloudStorageProgress(timeMs: Long) {
        val range = cloudStorageSelectedRange ?: return
        val duration = (range.endTimeMs - range.startTimeMs).coerceAtLeast(1L)
        val progress = (((timeMs - range.startTimeMs).coerceIn(0L, duration) * CLOUD_STORAGE_SEEK_MAX) / duration).toInt()
        cloudStorageSeekBar?.progress = progress
        cloudStorageTimeView?.text = "${formatCloudStorageTime(timeMs)} / ${formatCloudStorageTime(range.endTimeMs)}"
    }

    private fun updateCloudStorageSeekLabel(progress: Int) {
        val range = cloudStorageSelectedRange ?: return
        val target = range.startTimeMs + (range.endTimeMs - range.startTimeMs) * progress / CLOUD_STORAGE_SEEK_MAX
        cloudStorageTimeView?.text = "${formatCloudStorageTime(target)} / ${formatCloudStorageTime(range.endTimeMs)}"
    }

    private fun updateCloudStorageControls() {
        val flow = cloudStorageFlow
        val playing = flow != null && cloudStorageSelectedRange != null

        fun TextView?.enabled(value: Boolean) {
            this?.isEnabled = value
            this?.alpha = if (value) 1f else 0.5f
        }
        cloudStorageSeekBar?.isEnabled = playing
        val actionState = flow?.let(::cloudPlaybackActionState) ?: PlaybackActionState()
        cloudStorageRecordingButton.enabled(cloudActionEnabled(PlaybackMediaAction.RECORDING, actionState))
        cloudStorageSnapshotButton.enabled(cloudActionEnabled(PlaybackMediaAction.SNAPSHOT, actionState))
        cloudStorageRecordingButton?.updatePlaybackControl(
            compactText = if (flow?.isRecording == true) "■" else "●",
            wideText = if (flow?.isRecording == true) "结束录屏" else "开始录屏",
            description = if (flow?.isRecording == true) "结束录屏" else "开始录屏",
        )
        cloudStorageGalleryButton.enabled(cloudActionEnabled(PlaybackMediaAction.GALLERY, actionState))
        cloudStorageMuteButton.enabled(playing && flow?.speed == TiCloudStorageReplaySpeed.X1)
        cloudStorageMuteButton?.updatePlaybackControl(
            compactText = if (flow?.muted == true) "🔇" else "🔊",
            wideText = if (flow?.muted == true) "恢复声音" else "静音",
            description = if (flow?.muted == true) "恢复声音" else "静音",
        )
        cloudStorageSpeedButton.enabled(playing)
        val speedLabel = cloudStorageSpeedLabel(flow?.speed ?: TiCloudStorageReplaySpeed.X1)
        cloudStorageSpeedButton?.updatePlaybackControl(speedLabel, "倍速 $speedLabel", "播放倍速 $speedLabel")
        cloudStoragePauseButton.enabled(playing)
        cloudStoragePauseButton?.updatePlaybackControl(
            compactText = if (flow?.paused == true) "▶" else "Ⅱ",
            wideText = if (flow?.paused == true) "继续" else "暂停",
            description = if (flow?.paused == true) "继续播放" else "暂停播放",
        )
        updateCloudStorageMoreSummary(flow, actionState)
    }

    private fun updateCloudStorageMoreSummary(
        flow: TiCloudStorageExampleFlow?,
        state: PlaybackActionState,
    ) {
        fun summary(action: PlaybackMediaAction, label: String): String {
            if (cloudActionEnabled(action, state)) return label
            val reason =
                when {
                    state.busy -> "媒体操作进行中"
                    action == PlaybackMediaAction.GALLERY && !state.latestMediaAvailable -> "还没有可保存的媒体文件"
                    !state.playing -> "请先选择并播放录像"
                    else -> "当前视频尚未可用"
                }
            return "${label}不可用：$reason"
        }
        val recordingLabel = if (flow?.isRecording == true) "结束录屏" else "开始录屏"
        cloudStorageMoreButton?.contentDescription =
            "更多；" +
            listOf(
                summary(PlaybackMediaAction.RECORDING, recordingLabel),
                summary(PlaybackMediaAction.SNAPSHOT, "截图"),
                summary(PlaybackMediaAction.GALLERY, "相册"),
            ).joinToString("；")
    }

    private fun cloudStorageQueryBounds(): Pair<Long, Long> {
        val exactStart = intent.getLongExtra("cloud_storage_query_start_ms", -1L)
        val exactEnd = intent.getLongExtra("cloud_storage_query_end_ms", -1L)
        if (exactStart >= 0 && exactEnd > exactStart) return exactStart to exactEnd
        val start = cloudStorageSelectedDate.clone() as Calendar
        start.set(Calendar.HOUR_OF_DAY, 0)
        start.set(Calendar.MINUTE, 0)
        start.set(Calendar.SECOND, 0)
        start.set(Calendar.MILLISECOND, 0)
        val end = start.clone() as Calendar
        end.add(Calendar.DAY_OF_MONTH, 1)
        return start.timeInMillis to end.timeInMillis
    }

    private fun cloudStorageDateKey(calendar: Calendar): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }.format(calendar.time)

    private fun cloudStorageDateLabel(): String = cloudStorageDateKey(cloudStorageSelectedDate)

    private fun formatCloudStorageTime(timeMs: Long): String =
        SimpleDateFormat("HH:mm:ss", Locale.ROOT).apply {
            timeZone = TimeZone.getTimeZone("Asia/Shanghai")
        }.format(timeMs)

    private fun formatCloudStorageDuration(durationMs: Long): String {
        val seconds = (durationMs / 1000L).coerceAtLeast(0L)
        return "%02d:%02d".format(seconds / 60L, seconds % 60L)
    }

    private fun cloudStorageSpeedLabel(speed: TiCloudStorageReplaySpeed): String =
        when (speed) {
            TiCloudStorageReplaySpeed.X0_125 -> "1/8×"
            TiCloudStorageReplaySpeed.X0_25 -> "1/4×"
            TiCloudStorageReplaySpeed.X0_5 -> "1/2×"
            TiCloudStorageReplaySpeed.X1 -> "1×"
            TiCloudStorageReplaySpeed.X2 -> "2×"
            TiCloudStorageReplaySpeed.X4 -> "4×"
            TiCloudStorageReplaySpeed.X8 -> "8×"
        }

    private fun cloudStorageVideoStateLabel(state: TiCloudStorageVideoOutputState): String =
        when (state) {
            TiCloudStorageVideoOutputState.IDLE -> "等待播放"
            TiCloudStorageVideoOutputState.BUFFERING -> "缓冲中"
            TiCloudStorageVideoOutputState.RENDERING -> "正在播放"
            TiCloudStorageVideoOutputState.FAILED -> "视频输出失败"
            TiCloudStorageVideoOutputState.PAUSED -> "已暂停"
            TiCloudStorageVideoOutputState.COMPLETED -> "录像播放完成"
        }

    private fun closeCloudStorageFlow(completion: () -> Unit = {}) {
        if (rawDump != null) {
            finishRawDump(upload = false, completion = { closeCloudStorageFlow(completion) })
            return
        }
        val flow = cloudStorageFlow
        cloudStorageFlow = null
        if (cloudStorageMediaBusyOwner === flow) cloudStorageMediaBusyOwner = null
        cloudStorageDayQueryGeneration += 1
        cloudStorageMonthQueryGeneration += 1
        cloudStorageRecordingsDialog?.dismiss()
        cloudStorageRecordingsDialog = null
        cloudStorageRecordingsButton = null
        cloudStorageRecordingsContent = null
        cloudStorageSelectedRange = null
        cloudStorageExportProgress = -1
        cloudStorageActionStatusGeneration += 1
        cloudStorageActionStatusUntilMs = 0L
        cloudStoragePlaybackStatus = "请选择录像"
        cloudStorageStatusView = null
        cloudStorageTimeView = null
        cloudStorageSeekBar = null
        cloudStorageStage = null
        cloudStorageRecordingButton = null
        cloudStorageSnapshotButton = null
        cloudStorageGalleryButton = null
        cloudStorageMuteButton = null
        cloudStorageSpeedButton = null
        cloudStoragePauseButton = null
        cloudStorageMoreButton?.contentDescription = "更多"
        cloudStorageMoreButton = null
        rawDumpButton = null
        if (flow == null) {
            completion()
        } else {
            flow.close { code ->
                if (code != 0) Log.w("TiCloudStorageExample", "cloudStorage cleanup failed code=$code")
                completion()
            }
        }
    }

    private fun showSettings() {
        clearActiveScanner()
        showExampleSettingsPage(
            settings = settings,
            onBack = { showConfigure() },
            onSave = { next ->
                settings = next
                showConfigure()
            },
        )
    }

    private fun showClientQr(
        appIdField: EditText,
        endpointField: EditText,
        remoteIdField: EditText,
        tokenField: EditText,
    ) {
        val payloadField =
            editText(
                placeholder = CLIENT_QR_SAMPLE,
                value = CLIENT_QR_SAMPLE,
                multiLine = true,
            )
        val scannerView =
            qrScannerView { raw ->
                val payload = parseClientQrPayload(raw, clientConfig, ::toast) ?: return@qrScannerView false
                appIdField.setText(payload.appId)
                remoteIdField.setText(payload.remoteId)
                tokenField.setText(payload.oneTimeToken)
                if (payload.endpoint.isNotBlank()) {
                    endpointField.setText(payload.endpoint)
                }
                clientConfig = payload
                showConfigure()
                true
            }
        setContentView(
            page {
                navigationHeader("扫描二维码") { showConfigure() }
                addView(scannerPanel(scannerView))
                addView(qrGuide("将二维码完整放入方框内，系统会自动识别并填充 app_id、remote_id、token。"))
                addViewWithMargin(
                    fieldBlock("JSON payload", payloadField),
                    bottom = 20,
                )
                addView(
                    primaryButton("解析并填充") {
                        val payload = parseClientQrPayload(payloadField.text.toString(), clientConfig, ::toast) ?: return@primaryButton
                        appIdField.setText(payload.appId)
                        remoteIdField.setText(payload.remoteId)
                        tokenField.setText(payload.oneTimeToken)
                        if (payload.endpoint.isNotBlank()) {
                            endpointField.setText(payload.endpoint)
                        }
                        clientConfig = payload
                        showConfigure()
                    },
                )
            },
        )
        activateScanner(scannerView)
    }

    private fun showCloudStorageQr(
        appIdField: EditText,
        endpointField: EditText,
        tokenField: EditText,
    ) {
        val payloadField = editText("粘贴云录像 Token", "", multiLine = true)

        fun applyToken(raw: String): Boolean {
            val payload = parseCloudStorageQrPayload(raw, cloudStorageConfig, ::toast) ?: return false
            appIdField.setText(payload.appId)
            endpointField.setText(payload.endpoint)
            tokenField.setText(payload.token)
            cloudStorageConfig = payload
            showConfigure()
            return true
        }
        val scannerView = qrScannerView(::applyToken)
        setContentView(
            page {
                navigationHeader("扫描二维码") { showConfigure() }
                addView(scannerPanel(scannerView))
                addView(qrGuide("对准云录像 Token 二维码，或使用包含 app_id、token 和可选 endpoint 的 JSON。"))
                addViewWithMargin(fieldBlock("二维码内容", payloadField), bottom = 20)
                addView(primaryButton("应用二维码内容") { applyToken(payloadField.text.toString()) })
            },
        )
        activateScanner(scannerView)
    }

    private fun showPlayer(config: ClientConfiguration) {
        clearActiveScanner()
        val videoStage = videoPanel("远端视频")
        val status = body("正在初始化").apply { id = R.id.player_status }
        val metrics =
            DownlinkMetricsPanel(
                context = this,
                requestedDecoderPreference = settings.decoderPreference.nativeValue,
                onShowExplanation = { showMetricsExplanation() },
            )
        val bubble = streamBubbleView("等待 stream message")
        val localAudioButton =
            playbackControlButton("🎙", "启动麦克风") {
                togglePlayerTalkback()
            }
        val downlinkButton =
            playbackControlButton("…", "连接中", emphasized = true) {
                togglePlayerDownlink()
            }
        val outputVolumeButton =
            playbackControlButton("🔊", "静音播放") {
                togglePlayerOutputVolume()
            }
        val recordingButton =
            mediaIconButton(android.R.drawable.presence_video_online, "开始本地保存") {
                togglePlayerRecording()
            }.apply { id = R.id.player_recording_button }
        val snapshotButton =
            mediaIconButton(android.R.drawable.ic_menu_camera, "截图") {
                takePlayerSnapshot()
            }.apply { id = R.id.player_snapshot_button }
        val galleryButton =
            mediaIconButton(android.R.drawable.ic_menu_gallery, "保存到系统相册") {
                savePlayerLatestToGallery()
            }.apply {
                id = R.id.player_gallery_button
                isEnabled = false
                alpha = 0.46f
            }
        lateinit var moreButton: TextView
        moreButton =
            playbackMoreButton {
                showPlaybackActionMenu(
                    moreButton,
                    listOf(
                        PlaybackMenuAction(
                            R.id.player_recording_button,
                            if (playerRecordingTask == null) "开始本地保存" else "结束本地保存",
                            "player_action_recording",
                            enabled = { rtcActionEnabled(PlaybackMediaAction.RECORDING, rtcPlaybackActionState()) },
                            unavailableMessage = { if (playerMediaBusy) "媒体操作进行中" else "当前视频尚未可用" },
                            dispatch = ::togglePlayerRecording,
                        ),
                        PlaybackMenuAction(
                            R.id.player_snapshot_button,
                            "截图",
                            "player_action_snapshot",
                            enabled = { rtcActionEnabled(PlaybackMediaAction.SNAPSHOT, rtcPlaybackActionState()) },
                            unavailableMessage = { if (playerMediaBusy) "媒体操作进行中" else "当前视频尚未可用" },
                            dispatch = ::takePlayerSnapshot,
                        ),
                        PlaybackMenuAction(
                            R.id.player_gallery_button,
                            "保存到系统相册",
                            "player_action_gallery",
                            enabled = { rtcActionEnabled(PlaybackMediaAction.GALLERY, rtcPlaybackActionState()) },
                            unavailableMessage = { if (playerMediaBusy) "媒体操作进行中" else "还没有可保存的媒体文件" },
                            dispatch = ::savePlayerLatestToGallery,
                        ),
                    ),
                    ::appendStatus,
                )
            }.apply { id = R.id.player_more_button }
        if (config.videoStreamIds.isEmpty()) {
            recordingButton.visibility = View.GONE
            snapshotButton.visibility = View.GONE
            galleryButton.visibility = View.GONE
        }
        playerGalleryButton = galleryButton
        playerMoreButton = moreButton
        playerRecordingButton = recordingButton
        playerSnapshotButton = snapshotButton
        playerConfig = config
        playerStage = videoStage
        playerLocalAudioButton = localAudioButton
        playerOutputVolumeButton = outputVolumeButton
        playerDownlinkButton = downlinkButton
        playerOutputMuted = false
        statusView = status
        downlinkMetricsPanel = metrics
        streamBubble = bubble
        setPlayerControlState(connecting = true, running = false, localAudioEnabled = false)
        val rawDumpControl =
            createRawDumpButton { callback ->
                val active = conn ?: return@createRawDumpButton false
                active.startRawDump(
                    TiRtcRawDumpOptions(
                        audioStreamIds = config.audioStreamId?.let { intArrayOf(it) } ?: intArrayOf(),
                        videoStreamIds = config.videoStreamIds.toIntArray(),
                        uplinkAudioStreamIds = intArrayOf(settings.localAudioStreamId),
                    ),
                    callback,
                )
                true
            }
        rawDumpButton = rawDumpControl
        setContentView(
            frameScreen(
                top =
                    playerTopBar(
                        remoteId = config.remoteId,
                        onBack = {
                            stopPlayer()
                            showConfigure()
                        },
                        onCommand = { trigger -> showCommandPanel(trigger) },
                        onUploadLogs = { uploadLogs() },
                    ),
                stage = videoStage,
                overlay =
                    LinearLayout(this).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(playbackStatusSurface(status))
                        addView(metrics)
                    },
                bottom =
                    playerBottomControls(
                        bubble = bubble,
                        recordingButton = recordingButton,
                        snapshotButton = snapshotButton,
                        galleryButton = galleryButton,
                        localAudioButton = localAudioButton,
                        outputVolumeButton = outputVolumeButton,
                        downlinkButton = downlinkButton,
                        moreButton = moreButton,
                    ),
            ).apply { addRawDumpOverlay(rawDumpControl) },
        )
        startPlayer(config, videoStage)
    }

    private fun startPlayer(
        config: ClientConfiguration,
        stage: FrameLayout,
    ) {
        val generation = ++playerSessionGeneration
        val initCode =
            TiRtc.init(
                this,
                TiRtcInitOptions(
                    appId = config.appId,
                    endpoint = config.endpoint,
                    consoleLogEnabled = settings.consoleLogEnabled,
                ),
            )
        appendStatus("initialize code=$initCode")
        if (initCode != 0) {
            setPlayerControlState(connecting = false, running = false, localAudioEnabled = false)
            return
        }
        val nextConn = TiRtcConn()
        val nextAudio = config.audioStreamId?.let { TiRtcAudioOutput() }
        val nextVideos = config.videoStreamIds.associateWithTo(linkedMapOf()) { TiRtcVideoOutput() }
        val nextTalkback = TiRtcAudioInput()
        conn = nextConn
        audioOutput = nextAudio
        videoOutputs.clear()
        videoOutputs.putAll(nextVideos)
        selectedVideoStreamId = config.videoStreamIds.firstOrNull()
        maximizedVideoStreamId = null
        playerVideoLanes.clear()
        playerVideoStateLabels.clear()
        playerUnavailableVideoStreamIds.clear()
        stage.removeAllViews()
        val grid = GridLayout(this).apply {
            columnCount = 1
            rowCount = 1
        }
        stage.addView(
            grid,
            FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT),
        )
        if (config.videoStreamIds.isEmpty()) {
            addPlayerEmptyVideoState(stage, config.audioStreamId)
        }
        config.videoStreamIds.forEachIndexed { index, streamId ->
            val lane = FrameLayout(this).apply {
                contentDescription = "rtc_video_lane_$streamId"
                setBackgroundColor(ExampleTheme.videoBackground)
                setPadding(dp(2), dp(2), dp(2), dp(2))
                setOnClickListener {
                    maximizedVideoStreamId =
                        if (selectedVideoStreamId == streamId && maximizedVideoStreamId == null) streamId else null
                    selectedVideoStreamId = streamId
                    updatePlayerVideoSelection()
                }
            }
            val params = GridLayout.LayoutParams().apply { width = 0; height = 0 }
            grid.addView(lane, params)
            playerVideoLanes[streamId] = lane
        }
        playerAudioInput = nextTalkback
        playerTalkbackRunning = false
        nextVideos.forEach { (streamId, video) ->
            val lane = playerVideoLanes.getValue(streamId)
            val laneNumber = config.videoStreamIds.indexOf(streamId) + 1
            val laneLabel =
                body("视频 $laneNumber · ID $streamId\nwaiting").apply {
                    setTextColor(0xFFFFFFFF.toInt())
                    setBackgroundColor(0x99000000.toInt())
                    setPadding(dp(8), dp(4), dp(8), dp(4))
                }
            lane.addView(
                laneLabel,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.TOP or Gravity.START,
                ).apply { setMargins(dp(8), dp(8), 0, 0) },
            )
            playerVideoStateLabels[streamId] = laneLabel
            video.onStateChanged =
                TiRtcVideoOutputStateListener { state ->
                    if (generation != playerSessionGeneration || videoOutputs[streamId] !== video) {
                        return@TiRtcVideoOutputStateListener
                    }
                    appendStatus("video[$streamId]=${state.name}")
                    mainHandler.post {
                        if (generation != playerSessionGeneration || videoOutputs[streamId] !== video) {
                            return@post
                        }
                        if (state == TiRtcVideoOutputState.FAILED) {
                            playerUnavailableVideoStreamIds.add(streamId)
                        }
                        laneLabel.text = "视频 $laneNumber · ID $streamId\n${state.name.lowercase(Locale.ROOT)}"
                        lane.contentDescription = "rtc_video_lane_$streamId state=${state.name.lowercase(Locale.ROOT)}"
                        updatePlayerVideoSelection()
                    }
                }
            video.onError =
                TiRtcVideoOutputErrorListener { code ->
                    if (generation != playerSessionGeneration || videoOutputs[streamId] !== video) {
                        return@TiRtcVideoOutputErrorListener
                    }
                    markPlayerVideoUnavailable(streamId, "runtime", code)
                    appendStatus("video[$streamId] error=$code")
                }
            video.onRenderSizeChanged =
                TiRtcVideoOutputRenderSizeListener { size ->
                    if (generation != playerSessionGeneration || videoOutputs[streamId] !== video) {
                        return@TiRtcVideoOutputRenderSizeListener
                    }
                    appendStatus("video[$streamId] size=${size.width}x${size.height}")
                    mainHandler.post {
                        if (generation != playerSessionGeneration || videoOutputs[streamId] !== video) {
                            return@post
                        }
                        laneLabel.text = "视频 $laneNumber · ID $streamId\nrendering · ${size.width}×${size.height}"
                        lane.contentDescription = "rtc_video_lane_$streamId size=${size.width}x${size.height}"
                        updatePlayerVideoSelection()
                    }
                }
            val viewCode = video.attachView(lane)
            appendStatus("view[$streamId]=$viewCode")
            if (viewCode != 0) markPlayerVideoUnavailable(streamId, "attach-view", viewCode)
        }
        updatePlayerVideoSelection()
        nextTalkback.onStateChanged =
            TiRtcInputStateListener { state ->
                if (generation == playerSessionGeneration && playerAudioInput === nextTalkback) {
                    appendStatus("talkback=${state.name}")
                }
            }
        nextTalkback.onError =
            TiRtcInputErrorListener { code, message ->
                if (generation != playerSessionGeneration || playerAudioInput !== nextTalkback) {
                    return@TiRtcInputErrorListener
                }
                appendStatus("talkback error=$code ${message ?: ""}")
            }
        nextConn.onCommand =
            TiRtcConnCommandListener { command, data ->
                if (generation != playerSessionGeneration || conn !== nextConn) {
                    return@TiRtcConnCommandListener
                }
                handleIncomingCommand(nextConn, command, data)
            }
        nextConn.onStreamMessage =
            TiRtcConnStreamMessageListener { streamId, _, data ->
                if (generation != playerSessionGeneration || conn !== nextConn) {
                    return@TiRtcConnStreamMessageListener
                }
                updateStreamBubble("stream $streamId: ${payloadText(data)}")
            }
        nextConn.onStateChanged =
            TiRtcConnStateListener { state, code ->
                if (generation != playerSessionGeneration || conn !== nextConn) {
                    return@TiRtcConnStateListener
                }
                appendStatus("conn=${state.name} code=$code")
                if (state == TiRtcConnState.CONNECTED) {
                    setPlayerControlState(connecting = false, running = true, localAudioEnabled = true)
                    val activeAudio = audioOutput
                    val audioCode = config.audioStreamId?.let { activeAudio?.attach(nextConn, it) } ?: 0
                    var audioSubscribeCode = 0
                    if (audioCode == 0 && activeAudio != null && config.audioStreamId != null) {
                        audioSubscribeCode = nextConn.subscribeAudio(config.audioStreamId)
                    }
                    if (audioCode != 0 || audioSubscribeCode != 0) {
                        retirePlayerAudioOutput(
                            activeAudio,
                            config.audioStreamId,
                            if (audioCode != 0) "attach" else "subscribe",
                            if (audioCode != 0) audioCode else audioSubscribeCode,
                        )
                    }
                    val videoCodes = linkedMapOf<Int, Int>()
                    val videoSubscribeCodes = linkedMapOf<Int, Int>()
                    nextVideos.forEach { (streamId, video) ->
                        if (streamId in playerUnavailableVideoStreamIds) return@forEach
                        val attachCode = video.attach(nextConn, streamId)
                        videoCodes[streamId] = attachCode
                        if (attachCode != 0) {
                            markPlayerVideoUnavailable(streamId, "attach", attachCode)
                            return@forEach
                        }
                        val subscribeCode = nextConn.subscribeVideo(streamId)
                        videoSubscribeCodes[streamId] = subscribeCode
                        if (subscribeCode != 0) {
                            markPlayerVideoUnavailable(streamId, "subscribe", subscribeCode)
                        }
                    }
                    appendStatus("attach audio=$audioCode videos=$videoCodes")
                    appendStatus(
                        "subscribe audio=$audioSubscribeCode videos=$videoSubscribeCodes " +
                            "audioStream=${config.audioStreamId} videoStreams=${config.videoStreamIds}",
                    )
                    appendStatus("talkback ready stream=${settings.localAudioStreamId}")
                }
            }
        nextTalkback.setOptions(settings.localAudioOptions())
        nextAudio?.onStateChanged =
            TiRtcAudioOutputStateListener { state ->
                if (generation != playerSessionGeneration || audioOutput !== nextAudio) {
                    return@TiRtcAudioOutputStateListener
                }
                appendStatus("audio=${state.name}")
                if (state == TiRtcAudioOutputState.FAILED) {
                    retirePlayerAudioOutput(nextAudio, config.audioStreamId, "runtime-state", -1)
                }
            }
        nextAudio?.onError =
            TiRtcAudioOutputErrorListener { code ->
                if (generation != playerSessionGeneration || audioOutput !== nextAudio) {
                    return@TiRtcAudioOutputErrorListener
                }
                retirePlayerAudioOutput(nextAudio, config.audioStreamId, "runtime", code)
                appendStatus("audio error=$code")
            }
        val audioOptionsCode =
            nextAudio?.configure(TiRtcAudioOutputOptions(bufferStrategy = settings.outputBufferStrategy)) ?: 0
        if (audioOptionsCode != 0) {
            retirePlayerAudioOutput(nextAudio, config.audioStreamId, "configure", audioOptionsCode)
        }
        nextVideos.forEach { (streamId, video) ->
            val optionsCode = video.setOptions(
                TiRtcVideoOutputOptions(
                    decoderPreference = settings.decoderPreference.toSdkDecoderPreference(),
                    bufferStrategy = settings.outputBufferStrategy,
                ),
            )
            if (optionsCode != 0) markPlayerVideoUnavailable(streamId, "configure", optionsCode)
        }
        appendStatus("connect=${nextConn.connect(config.remoteId, config.token)}")
        startMetricsPolling()
    }

    private fun updatePlayerVideoSelection() {
        (playerVideoLanes.values.firstOrNull()?.parent as? GridLayout)?.let { grid ->
            layoutVideoMosaic(
                grid,
                playerConfig?.videoStreamIds.orEmpty(),
                playerVideoLanes,
                selectedVideoStreamId,
                maximizedVideoStreamId,
                resources.configuration.screenWidthDp >= ExampleTheme.compactBreakpointDp,
            )
        }
        val actionState = rtcPlaybackActionState()
        playerRecordingButton?.apply {
            isEnabled = rtcActionEnabled(PlaybackMediaAction.RECORDING, actionState)
            alpha = if (isEnabled) 1f else 0.46f
            contentDescription = if (playerRecordingTask == null) "开始本地保存" else "结束本地保存"
        }
        playerSnapshotButton?.apply {
            isEnabled = rtcActionEnabled(PlaybackMediaAction.SNAPSHOT, actionState)
            alpha = if (isEnabled) 1f else 0.46f
        }
        playerGalleryButton?.apply {
            isEnabled = rtcActionEnabled(PlaybackMediaAction.GALLERY, actionState)
            alpha = if (isEnabled) 1f else 0.46f
        }
        updatePlayerMoreSummary()
        downlinkMetricsPanel?.render(conn, audioOutput, selectedVideoStreamId?.let(videoOutputs::get))
    }

    private fun updatePlayerMoreSummary() {
        val state = rtcPlaybackActionState()
        fun unavailableReason(action: PlaybackMediaAction): String =
            when {
                state.busy -> "媒体操作进行中"
                action == PlaybackMediaAction.GALLERY && !state.latestMediaAvailable -> "还没有可保存的媒体文件"
                else -> "当前视频尚未可用"
            }
        playerMoreButton?.contentDescription =
            "更多；" +
            listOf(
                PlaybackMediaAction.RECORDING to "录制",
                PlaybackMediaAction.SNAPSHOT to "截图",
                PlaybackMediaAction.GALLERY to "相册",
            ).joinToString("；") { (action, label) ->
                if (rtcActionEnabled(action, state)) label else "${label}不可用：${unavailableReason(action)}"
            }
    }

    private fun playerSelectedVideoReady(): Boolean {
        val streamId = selectedVideoStreamId ?: return false
        return streamId !in playerUnavailableVideoStreamIds && videoOutputs[streamId]?.state == TiRtcVideoOutputState.RENDERING
    }

    private fun rtcPlaybackActionState(): PlaybackActionState =
        PlaybackActionState(
            selectedVideoReady = playerSelectedVideoReady(),
            recording = playerRecordingTask != null,
            latestMediaAvailable = playerLatestMediaFile != null,
            busy = playerMediaBusy,
        )

    private fun cloudPlaybackActionState(flow: TiCloudStorageExampleFlow): PlaybackActionState =
        PlaybackActionState(
            selectedVideoReady = flow.videoState == TiCloudStorageVideoOutputState.RENDERING,
            recording = flow.isRecording,
            latestMediaAvailable = flow.hasLatestMedia,
            busy = cloudStorageMediaBusyOwner === flow,
            playing = cloudStorageSelectedRange != null,
        )

    private fun markPlayerVideoUnavailable(streamId: Int, phase: String, code: Int) {
        playerUnavailableVideoStreamIds.add(streamId)
        mainHandler.post {
            playerVideoStateLabels[streamId]?.let { label ->
                label.text = "${label.text.toString().substringBefore('\n')}\nfailed"
            }
            playerVideoLanes[streamId]?.contentDescription = "rtc_video_lane_$streamId state=failed"
            updatePlayerVideoSelection()
        }
        appendStatus("video[$streamId] $phase failed code=$code")
    }

    private fun retirePlayerAudioOutput(
        output: TiRtcAudioOutput?,
        streamId: Int?,
        phase: String,
        code: Int,
    ) {
        if (output == null || audioOutput !== output) return
        streamId?.let { conn?.unsubscribeAudio(it) }
        output.detach()
        output.dispose()
        audioOutput = null
        playerOutputVolumeButton?.apply {
            isEnabled = false
            alpha = 0.55f
        }
        appendStatus("audio $phase failed code=$code")
    }

    private fun stopPlayer(clearPageRefs: Boolean = true) {
        if (rawDump != null) {
            finishRawDump(upload = false, completion = { stopPlayer(clearPageRefs) })
            return
        }
        playerSessionGeneration += 1
        metricsTimer?.cancel()
        metricsTimer = null
        emitDownlinkMetricsEvidence()
        stopPlayerTalkback()
        val task = playerRecordingTask
        playerRecordingTask = null
        playerLatestMediaFile = null
        playerLatestMediaTargetId = null
        playerMediaBusy = true
        refreshPlayerMediaControls()
        val finish = {
            deletePlayerMediaFiles(playerOwnedMediaFiles.toList()) {
                finishStopPlayer(clearPageRefs)
            }
        }
        if (task == null) {
            finish()
        } else {
            task.stop { result ->
                appendStatus("media recording teardown code=${result.code}")
                result.file?.let(playerOwnedMediaFiles::add)
                finish()
            }
        }
    }

    private fun finishStopPlayer(clearPageRefs: Boolean) {
        playerAudioInput?.dispose()
        playerAudioInput = null
        playerTalkbackRunning = false
        val activeConfig = playerConfig
        val activeConnection = conn
        if (activeConfig != null && activeConnection != null) {
            val videoUnsubscribeCodes = activeConfig.videoStreamIds.associateWith(activeConnection::unsubscribeVideo)
            val audioUnsubscribeCode = activeConfig.audioStreamId?.let(activeConnection::unsubscribeAudio) ?: 0
            appendStatus(
                "unsubscribe audio=$audioUnsubscribeCode videos=$videoUnsubscribeCodes " +
                    "audioStream=${activeConfig.audioStreamId} videoStreams=${activeConfig.videoStreamIds}",
            )
        }
        videoOutputs.values.forEach(TiRtcVideoOutput::dispose)
        videoOutputs.clear()
        playerVideoLanes.clear()
        playerVideoStateLabels.clear()
        playerUnavailableVideoStreamIds.clear()
        audioOutput?.dispose()
        audioOutput = null
        conn?.dispose()
        conn = null
        playerRunning = false
        setPlayerControlState(connecting = false, running = false, localAudioEnabled = false)
        if (clearPageRefs) {
            rawDumpButton = null
            downlinkMetricsPanel = null
            playerConfig = null
            playerStage = null
            playerLocalAudioButton = null
            playerOutputVolumeButton = null
            playerDownlinkButton = null
            playerRecordingButton = null
            playerSnapshotButton = null
            playerGalleryButton = null
            playerMoreButton = null
        }
        playerMediaBusy = false
        refreshPlayerMediaControls()
        TiRtc.shutdown()
    }

    private fun togglePlayerRecording() {
        if (playerMediaBusy) return
        val activeTask = playerRecordingTask
        if (activeTask != null) {
            playerMediaBusy = true
            refreshPlayerMediaControls()
            activeTask.stop { result ->
                playerRecordingTask = null
                refreshPlayerMediaControls()
                val completedFile = result.file
                deletePlayerMediaFile(playerLatestMediaFile) {
                    playerMediaBusy = false
                    refreshPlayerMediaControls()
                    if (result.code == 0 && completedFile != null) {
                        playerLatestMediaFile = completedFile
                        playerLatestMediaTargetId = recordingVideoStreamId
                        recordingVideoStreamId = null
                        playerOwnedMediaFiles.add(completedFile)
                    }
                    appendStatus(
                        if (result.code == 0) {
                            "本地保存完成 ${completedFile?.path.orEmpty()}"
                        } else {
                            "本地保存失败 code=${result.code}"
                        },
                    )
                }
            }
            return
        }
        val connection = conn ?: return
        val config = playerConfig ?: return
        val targetStreamId = selectedVideoStreamId ?: return
        val result = connection.startRecording(targetStreamId, config.audioStreamId)
        if (result.code == 0 && result.task != null) {
            playerRecordingTask = result.task
            recordingVideoStreamId = targetStreamId
            refreshPlayerMediaControls()
            appendStatus("正在本地保存 · 视频 Stream ID $targetStreamId")
        } else {
            appendStatus("开始本地保存失败 code=${result.code}")
        }
    }

    private fun takePlayerSnapshot() {
        if (playerMediaBusy) return
        val targetStreamId = selectedVideoStreamId ?: return
        val output = videoOutputs[targetStreamId] ?: return
        playerMediaBusy = true
        refreshPlayerMediaControls()
        output.takeSnapshot { result ->
            val file = result.file
            if (result.code != 0 || file == null) {
                playerMediaBusy = false
                refreshPlayerMediaControls()
                appendStatus("截图失败 code=${result.code}")
                return@takeSnapshot
            }
            deletePlayerMediaFile(playerLatestMediaFile) {
                playerLatestMediaFile = file
                playerLatestMediaTargetId = targetStreamId
                playerOwnedMediaFiles.add(file)
                playerMediaBusy = false
                refreshPlayerMediaControls()
                appendStatus("截图完成 · 视频 Stream ID $targetStreamId · ${file.path}")
            }
        }
    }

    private fun deletePlayerMediaFile(
        file: Any?,
        completion: () -> Unit,
    ) {
        val callback =
            com.tange.ai.tirtc.TiRtcDeleteCallback { code ->
                if (code == 0 && file != null) playerOwnedMediaFiles.remove(file)
                completion()
            }
        when (file) {
            is TiRtcRecordingFile -> file.delete(callback)
            is TiRtcSnapshotFile -> file.delete(callback)
            else -> completion()
        }
    }

    private fun savePlayerLatestToGallery() {
        if (playerMediaBusy) return
        val file = playerLatestMediaFile ?: return
        val path =
            when (file) {
                is TiRtcRecordingFile -> file.path
                is TiRtcSnapshotFile -> file.path
                else -> return
            }
        playerMediaBusy = true
        refreshPlayerMediaControls()
        Thread {
            val code = copyPathToGallery(this, path, file is TiRtcRecordingFile, playerLatestMediaTargetId ?: -1)
            mainHandler.post {
                playerMediaBusy = false
                refreshPlayerMediaControls()
                appendStatus(if (code == 0) "已保存到系统相册" else "保存到系统相册失败 code=$code")
            }
        }.start()
    }

    private fun deletePlayerMediaFiles(
        files: List<Any>,
        completion: () -> Unit,
    ) {
        val file = files.firstOrNull()
        if (file == null) {
            completion()
            return
        }
        deletePlayerMediaFile(file) {
            deletePlayerMediaFiles(files.drop(1), completion)
        }
    }

    private fun refreshPlayerMediaControls() {
        mainHandler.post {
            if (playerConfig != null) updatePlayerVideoSelection()
        }
    }

    private fun emitDownlinkMetricsEvidence() {
        if (conn == null && audioOutput == null && videoOutputs.isEmpty()) {
            return
        }
        val connectionMetrics = conn?.getMetricsSnapshot()
        val audioMetrics = audioOutput?.getMetricsSnapshot()
        val videoMetrics = selectedVideoStreamId?.let(videoOutputs::get)?.getMetricsSnapshot()
        val audioSnapshot = audioMetrics?.snapshot
        val videoSnapshot = videoMetrics?.snapshot
        Log.i(
            DOWNLINK_METRICS_EVIDENCE_TAG,
            "event=downlink_metrics_snapshot " +
                "connection_code=${connectionMetrics?.code ?: -1} " +
                "audio_code=${audioMetrics?.code ?: -1} " +
                "video_code=${videoMetrics?.code ?: -1} " +
                "video_first_output=${if (videoSnapshot?.startup?.hasFirstOutput == true) 1 else 0} " +
                "video_decoder_backend=${videoSnapshot?.decoderBackend ?: -1} " +
                "video_input_fps=${videoSnapshot?.videoInputFps ?: -1.0} " +
                "video_decoded_fps=${videoSnapshot?.videoDecodedFps ?: -1.0} " +
                "video_render_fps=${videoSnapshot?.videoRenderFps ?: -1.0} " +
                "video_stats_updated_at_ms=${videoSnapshot?.statsUpdatedAtMs ?: -1} " +
                "audio_input_packet_rate=${audioSnapshot?.audioInputPacketRate ?: -1.0} " +
                "audio_render_callback_rate=${audioSnapshot?.audioRenderCallbackRate ?: -1.0} " +
                "audio_stats_updated_at_ms=${audioSnapshot?.statsUpdatedAtMs ?: -1}",
        )
    }

    private fun togglePlayerDownlink() {
        if (playerRunning) {
            stopPlayer(clearPageRefs = false)
            appendStatus("Downlink stopped.")
            return
        }
        val config = playerConfig ?: return
        val stage = playerStage ?: return
        setPlayerControlState(connecting = true, running = false, localAudioEnabled = false)
        startPlayer(config, stage)
    }

    private fun togglePlayerTalkback() {
        if (playerTalkbackRunning) {
            stopPlayerTalkback()
        } else {
            startPlayerTalkback()
        }
    }

    private fun togglePlayerOutputVolume() {
        val output = audioOutput
        if (output == null) {
            appendStatus("audio volume output unavailable")
            return
        }
        val targetVolume = if (playerOutputMuted) 100 else 0
        val before = output.getMetricsSnapshot().snapshot
        val systemVolume =
            (getSystemService(AUDIO_SERVICE) as AudioManager).getStreamVolume(AudioManager.STREAM_MUSIC)
        val code = output.setVolume(targetVolume)
        if (code == 0) {
            playerOutputMuted = targetVolume == 0
        }
        val after = output.getMetricsSnapshot().snapshot
        playerOutputVolumeButton?.updatePlaybackControl(
            compactText = if (playerOutputMuted) "🔇" else "🔊",
            wideText = if (playerOutputMuted) "恢复声音" else "静音播放",
            description = if (playerOutputMuted) "恢复声音" else "静音播放",
        )
        val evidence =
            "event=audio_output_volume_toggle target=$targetVolume code=$code " +
                "state=${output.state.name} system_media_volume=$systemVolume " +
                "output_duration_ms_before=${before?.stutter?.outputDurationMs ?: -1} " +
                "output_duration_ms_after=${after?.stutter?.outputDurationMs ?: -1} " +
                "stats_updated_at_ms_before=${before?.statsUpdatedAtMs ?: -1} " +
                "stats_updated_at_ms_after=${after?.statsUpdatedAtMs ?: -1} " +
                "render_callback_rate=${after?.audioRenderCallbackRate ?: -1.0}"
        Log.i(AUDIO_VOLUME_EVIDENCE_TAG, evidence)
        appendStatus("audio volume=$targetVolume code=$code")
    }

    private fun startPlayerTalkback() {
        val connection = conn
        val input = playerAudioInput
        if (connection == null || input == null || connection.state != TiRtcConnState.CONNECTED) {
            appendStatus("talkback waiting for connected client")
            return
        }
        val optionsCode = input.setOptions(settings.localAudioOptions())
        if (optionsCode != 0) {
            appendStatus("talkback options=$optionsCode")
            return
        }
        val attachCode = input.attach(connection, settings.localAudioStreamId)
        if (attachCode != 0) {
            appendStatus("talkback attach=$attachCode")
            return
        }
        val startCode = input.start()
        playerTalkbackRunning = startCode == 0
        updatePlayerLocalAudioButton(enabled = true)
        appendStatus("talkback start=$startCode stream=${settings.localAudioStreamId}")
    }

    private fun stopPlayerTalkback() {
        val input = playerAudioInput ?: return
        val connection = conn
        val detachCode = if (connection != null) input.detach(connection) else 0
        val stopCode = input.stop()
        playerTalkbackRunning = false
        updatePlayerLocalAudioButton(enabled = connection?.state == TiRtcConnState.CONNECTED)
        appendStatus("talkback stop=$stopCode detach=$detachCode")
    }

    private fun setPlayerControlState(
        connecting: Boolean,
        running: Boolean,
        localAudioEnabled: Boolean,
    ) {
        playerRunning = running
        playerDownlinkButton?.apply {
            val label = when {
                connecting -> "连接中"
                running -> "停止播放"
                else -> "开始播放"
            }
            updatePlaybackControl(if (connecting) "…" else if (running) "■" else "▶", label, label)
            isEnabled = !connecting
            alpha = if (isEnabled) 1.0f else 0.55f
        }
        updatePlayerLocalAudioButton(enabled = localAudioEnabled)
        playerOutputVolumeButton?.apply {
            isEnabled = running && audioOutput != null
            alpha = if (isEnabled) 1.0f else 0.55f
        }
        updatePlayerMoreSummary()
    }

    private fun updatePlayerLocalAudioButton(enabled: Boolean) {
        playerLocalAudioButton?.apply {
            val label = if (playerTalkbackRunning) "停止麦克风" else "启动麦克风"
            updatePlaybackControl(if (playerTalkbackRunning) "🎙" else "🎙", label, label)
            isEnabled = enabled
            alpha = if (enabled) 1.0f else 0.55f
        }
    }

    private fun startMetricsPolling() {
        metricsTimer?.cancel()
        metricsTimer =
            Timer("tirtc-android-example-metrics", true).also { timer ->
                timer.scheduleAtFixedRate(
                    object : TimerTask() {
                        override fun run() {
                            mainHandler.post { refreshMetrics() }
                        }
                    },
                    0L,
                    METRICS_PERIOD_MS,
                )
            }
    }

    private fun refreshMetrics() {
        val connection = conn
        val audio = audioOutput
        val video = selectedVideoStreamId?.let(videoOutputs::get)
        downlinkMetricsPanel?.render(connection, audio, video)
    }

    private fun showMetricsExplanation() {
        AlertDialog.Builder(this)
            .setTitle("指标说明")
            .setMessage(DOWNLINK_METRICS_EXPLANATION)
            .setPositiveButton("知道了", null)
            .show()
    }

    private fun showCommandPanel(trigger: View) {
        commandDialog?.dismiss()
        val commandField = editText("0x00000000", formatCommandId(DEMO_CALL_COMMAND_ID))
        val preset = spinner(listOf("echo", CALL_START, CALL_READY, CALL_REJECT), 0)
        val mode = spinner(listOf("text", "hex"), 0)
        val payloadField = editText("输入文本内容", CALL_START, multiLine = true)
        val history = body(commandHistory)
        commandHistoryView = history
        val formContent =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(16), dp(10), dp(16), dp(16))
                addView(sectionTitle("发送命令"))
                addViewWithMargin(fieldBlock("命令 ID", commandField), bottom = 16)
                addViewWithMargin(fieldBlock("call command schema", preset), bottom = 12)
                addViewWithMargin(fieldBlock("payload mode", mode), bottom = 12)
                addViewWithMargin(fieldBlock("命令内容", payloadField), bottom = 16)
                addView(sectionTitle("history"))
                addView(history)
            }
        val wide = resources.configuration.screenWidthDp >= ExampleTheme.compactBreakpointDp
        val dialog: Dialog = if (wide) Dialog(this) else BottomSheetDialog(this)
        val actions =
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                addView(outlinedButton("关闭") { dialog.dismiss() }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                addView(space(dp(12)))
                addView(
                    primaryButton("发送") send@{
                        val command = parseCommandIdOrNull(commandField.text.toString(), ::toast) ?: return@send
                        val payload =
                            if (preset.selectedItemPosition > 0) {
                                utf8Payload(demoCommandPresetPayload(preset.selectedItemPosition))
                            } else if (mode.selectedItemPosition == 1) {
                                parseHexPayloadOrNull(payloadField.text.toString(), ::toast) ?: return@send
                            } else {
                                utf8Payload(payloadField.text.toString())
                            }
                        val code = conn?.sendCommand(command, payload) ?: -1
                        appendCommand("sent code=$code", command, payload)
                    },
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
            }
        val root =
            LinearLayout(this).apply {
                id = R.id.player_command_sheet
                orientation = LinearLayout.VERTICAL
                setBackgroundColor(ExampleTheme.background)
                addView(
                    ScrollView(context).apply {
                        isFillViewport = true
                        addView(formContent)
                    },
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f),
                )
                addView(actions, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                    setMargins(dp(16), dp(8), dp(16), dp(16))
                })
            }
        val panelHeight = (resources.displayMetrics.heightPixels * 0.72).toInt()
        root.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, panelHeight)
        dialog.setContentView(root)
        dialog.setOnDismissListener {
            if (commandDialog === dialog) commandDialog = null
            trigger.requestFocus()
        }
        dialog.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        commandDialog = dialog
        dialog.show()
        if (dialog is BottomSheetDialog) {
            dialog.behavior.apply {
                peekHeight = panelHeight
                state = BottomSheetBehavior.STATE_EXPANDED
            }
        } else {
            dialog.window?.setLayout(
                dp(minOf(ExampleTheme.dialogMaxWidthDp, resources.configuration.screenWidthDp - 32)),
                panelHeight,
            )
        }
    }

    private fun uploadLogs() {
        finishRawDump(upload = false, completion = ::uploadLogsNow)
    }

    private fun uploadLogsNow() {
        appendStatus("log upload=start")
        TiRtcLogging.upload(
            TiRtcLogUploadCallback { code, logId ->
                appendStatus("log upload code=$code id=${logId ?: ""}")
            },
        )
    }

    private fun restoreMediaSelections() {
        val preferences = getSharedPreferences("tirtc_example_media", MODE_PRIVATE)
        fun videos(listKey: String, fallback: List<Int>): List<Int> {
            if (preferences.contains(listKey)) {
                return preferences.getString(listKey, "").orEmpty().split(',')
                    .mapNotNull { it.trim().takeIf(String::isNotEmpty)?.toIntOrNull() }
                    .take(3)
            }
            return fallback
        }
        clientConfig =
            clientConfig.copy(
                audioStreamId = if (preferences.contains("rtc_audio_stream_id")) {
                    preferences.getString("rtc_audio_stream_id", "").orEmpty().toIntOrNull()
                } else {
                    clientConfig.audioStreamId
                },
                videoStreamIds = videos("rtc_video_stream_ids", clientConfig.videoStreamIds),
            )
        cloudStorageConfig =
            cloudStorageConfig.copy(
                audioChannelId = if (preferences.contains("cloud_audio_channel_id")) {
                    preferences.getString("cloud_audio_channel_id", "").orEmpty().toIntOrNull()
                } else {
                    cloudStorageConfig.audioChannelId
                },
                videoChannelIds = videos("cloud_video_channel_ids", cloudStorageConfig.videoChannelIds),
            )
    }

    private fun saveMediaSelections() {
        getSharedPreferences("tirtc_example_media", MODE_PRIVATE).edit()
            .putString("rtc_audio_stream_id", clientConfig.audioStreamId?.toString().orEmpty())
            .putString("rtc_video_stream_ids", clientConfig.videoStreamIds.joinToString(","))
            .putString("cloud_audio_channel_id", cloudStorageConfig.audioChannelId?.toString().orEmpty())
            .putString("cloud_video_channel_ids", cloudStorageConfig.videoChannelIds.joinToString(","))
            .apply()
    }

    private fun readClientConfig(
        appIdField: EditText,
        endpointField: EditText,
        remoteIdField: EditText,
        audioStreamField: EditText,
        videoStreamFields: List<EditText>,
        tokenSource: Int,
        tokenIssuerField: EditText,
        tokenField: EditText,
    ): ClientConfiguration? {
        val appId = appIdField.text.toString().trim()
        val remoteId = remoteIdField.text.toString().trim()
        val source = if (tokenSource == 0) DemoTokenSource.ISSUER else DemoTokenSource.ONE_TIME
        val tokenIssuerBaseUrl = tokenIssuerField.text.toString().trim()
        val oneTimeToken = tokenField.text.toString().trim()
        if (appId.isBlank() || remoteId.isBlank()) {
            toast("请先填写 app_id 和 remote_id")
            return null
        }
        if (source == DemoTokenSource.ISSUER && tokenIssuerBaseUrl.isBlank()) {
            toast("请填写 tokenIssuerBaseUrl")
            return null
        }
        if (source == DemoTokenSource.ONE_TIME && oneTimeToken.isBlank()) {
            toast("请填写 oneTimeToken")
            return null
        }
        val audioStreamText = audioStreamField.text.toString().trim()
        val videoStreamTexts = videoStreamFields.map { it.text.toString().trim() }.filter(String::isNotEmpty)
        val audioStreamId = audioStreamText.takeIf(String::isNotEmpty)?.toIntOrNull()
        val videoStreamIds = videoStreamTexts.mapNotNull { it.toIntOrNull() }
        if (audioStreamText.isNotEmpty() && audioStreamId == null ||
            videoStreamIds.size != videoStreamTexts.size ||
            audioStreamId != null && audioStreamId !in 0..15 ||
            videoStreamIds.any { it !in 0..15 } || videoStreamIds.distinct().size != videoStreamIds.size ||
            audioStreamId != null && audioStreamId in videoStreamIds
        ) {
            toast("RTC Stream ID 必须在 0..15，且音频与视频 ID 不能重复")
            return null
        }
        return ClientConfiguration(
            appId = appId,
            endpoint = endpointField.text.toString().trim(),
            remoteId = remoteId,
            audioStreamId = audioStreamId,
            videoStreamIds = videoStreamIds,
            token = oneTimeToken,
            tokenSource = source,
            tokenIssuerBaseUrl = tokenIssuerBaseUrl,
            oneTimeToken = oneTimeToken,
        )
    }

    private fun resolveTokenAndShowPlayer(config: ClientConfiguration) {
        if (config.tokenSource == DemoTokenSource.ONE_TIME) {
            try {
                val resolved = resolveDemoToken(config)
                clientConfig = resolved
                showPlayer(resolved)
            } catch (error: Exception) {
                toast("token 无效：${error.message}")
            }
            return
        }
        toast("token acquisition=start")
        Thread {
            val result =
                runCatching {
                    resolveDemoToken(config)
                }
            mainHandler.post {
                result
                    .onSuccess { resolved ->
                        clientConfig = resolved
                        showPlayer(resolved)
                    }
                    .onFailure { error -> toast("token issuer 失败：${error.message}") }
            }
        }.start()
    }

    private fun appendStatus(message: String) {
        mainHandler.post {
            statusView?.apply {
                text = message
                contentDescription = "播放状态：$message"
                setTextColor(if (message.contains("失败") || message.contains("error", ignoreCase = true)) ExampleTheme.failure else ExampleTheme.textPrimary)
            }
        }
    }

    private fun appendCommand(
        direction: String,
        command: Long,
        payload: ByteArray,
    ) {
        val line = "$direction ${formatCommandId(command)} ${payloadText(payload)}"
        commandHistory = if (commandHistory == "暂无命令记录") line else "$line\n$commandHistory"
        commandHistoryView?.text = commandHistory
        appendStatus(line)
    }

    private fun handleIncomingCommand(
        connection: TiRtcConn,
        command: Long,
        payload: ByteArray,
    ) {
        appendCommand("received", command, payload)
        val responsePayload = demoCommandResponsePayload(command, payload) ?: return
        val code = connection.sendCommand(command, responsePayload)
        appendCommand("sent code=$code", command, responsePayload)
    }

    private fun updateStreamBubble(text: String) {
        streamBubble?.text = text
    }

    private fun qrScannerView(onPayload: (String) -> Boolean): DecoratedBarcodeView {
        return DecoratedBarcodeView(this).apply {
            setStatusText("")
            decodeContinuous(
                object : BarcodeCallback {
                    override fun barcodeResult(result: BarcodeResult) {
                        val raw = result.text?.trim().orEmpty()
                        if (raw.isBlank() || scannerProcessing) {
                            return
                        }
                        scannerProcessing = true
                        mainHandler.post {
                            if (onPayload(raw)) {
                                clearActiveScanner()
                                return@post
                            }
                            mainHandler.postDelayed({ scannerProcessing = false }, SCANNER_RETRY_DELAY_MS)
                        }
                    }

                    override fun possibleResultPoints(resultPoints: List<ResultPoint>) = Unit
                },
            )
        }
    }

    private fun activateScanner(scannerView: DecoratedBarcodeView) {
        clearActiveScanner()
        activeScanner = scannerView
        scannerView.resume()
    }

    private fun clearActiveScanner() {
        activeScanner?.pause()
        activeScanner = null
        scannerProcessing = false
    }

    private fun requestRuntimePermissions() {
        val permissions = mutableListOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P) {
            permissions += Manifest.permission.WRITE_EXTERNAL_STORAGE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.POST_NOTIFICATIONS
        }
        val missing =
            permissions.filter { permission ->
                ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
            }
        if (missing.isNotEmpty()) {
            permissionLauncher.launch(missing.toTypedArray())
        }
    }

    private fun toast(text: String) {
        Toast.makeText(this, text, Toast.LENGTH_SHORT).show()
    }

    companion object {
        private const val DEFAULT_AUDIO_STREAM_ID = 10
        private const val DEFAULT_VIDEO_STREAM_ID = 11
        private const val CLOUD_STORAGE_SEEK_MAX = 1000
        private const val CLOUD_STORAGE_ACTION_STATUS_DURATION_MS = 4000L
        private const val RAW_DUMP_STOP_RETRY_DELAY_MS = 50L
        private const val RAW_DUMP_STOP_RETRY_LIMIT = 20
        private const val METRICS_PERIOD_MS = 1000L
        private const val SCANNER_RETRY_DELAY_MS = 900L
        private const val AUDIO_VOLUME_EVIDENCE_TAG = "TiRtcVolumeEvidence"
        private const val DOWNLINK_METRICS_EVIDENCE_TAG = "TiRtcDomainEvidence"
        private const val RAW_DUMP_EVIDENCE_TAG = "TiRtcRawDumpEvidence"
        private const val CLIENT_QR_SAMPLE =
            "{\n" +
                "  \"app_id\": \"demo-app\",\n" +
                "  \"remote_id\": \"TESTTIRTC01\",\n" +
                "  \"token\": \"token\",\n" +
                "  \"endpoint\": \"https://example.com\"\n" +
                "}"
        private const val DOWNLINK_METRICS_EXPLANATION =
            "【连接耗时】：从点击开始连接，到 runtime 确认连接成功的时间。只表示连接建立用了多久，不表示画面已经出来。\n\n" +
                "【首帧耗时】：从点击开始连接，到第一个视频帧真正显示成功的时间。\n\n" +
                "【卡顿统计】：第一个视频帧真正显示成功后，才开始统计本次播放的卡顿；连接中、等首帧、页面看不见、停止播放后的空窗不算卡顿。\n\n" +
                "【码率 / 速率】：码率、接收 FPS、渲染 FPS 和音频包率来自 runtime 最近一个已闭合窗口。\n\n" +
                "【音频卡顿】：统计本机音频输出已经开始后，系统输出回调取不到可播放数据而产生的停滞。\n\n" +
                "【视频 / 音频本机延迟】：表示从本机接收到远端编码包，到 runtime 交给本机输出并返回所花的时间。"
    }
}
