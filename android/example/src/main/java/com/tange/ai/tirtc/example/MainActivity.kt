package com.tange.ai.tirtc.example

import android.Manifest
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.Dialog
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.FrameLayout
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
import com.tange.ai.tirtc.TiRtc
import com.tange.ai.tirtc.TiRtcAudioInput
import com.tange.ai.tirtc.TiRtcAudioOutput
import com.tange.ai.tirtc.TiRtcAudioOutputOptions
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
import com.tange.ai.tirtc.TiRtcRecordingFile
import com.tange.ai.tirtc.TiRtcRecordingTask
import com.tange.ai.tirtc.TiRtcSnapshotFile
import com.tange.ai.tirtc.TiRtcVideoOutput
import com.tange.ai.tirtc.TiRtcVideoOutputOptions
import com.tange.ai.tirtc.TiRtcVideoOutputRenderSizeListener
import com.tange.ai.tirtc.TiRtcVideoOutputStateListener
import com.tange.ai.tirtc.TiStoreRecordingRange
import com.tange.ai.tirtc.TiStoreReplaySpeed
import com.tange.ai.tirtc.TiStoreVideoOutputState
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
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
            videoStreamId = DEFAULT_VIDEO_STREAM_ID,
            token = "",
        )
    private var storeConfig = StoreConfiguration()
    private var conn: TiRtcConn? = null
    private var audioOutput: TiRtcAudioOutput? = null
    private var videoOutput: TiRtcVideoOutput? = null
    private var playerAudioInput: TiRtcAudioInput? = null
    private var playerTalkbackRunning = false
    private var playerRunning = false
    private var playerConfig: ClientConfiguration? = null
    private var playerStage: FrameLayout? = null
    private var playerLocalAudioButton: TextView? = null
    private var playerOutputVolumeButton: TextView? = null
    private var playerDownlinkButton: TextView? = null
    private var playerOutputMuted = false
    private var playerRecordingTask: TiRtcRecordingTask? = null
    private var playerLatestMediaFile: Any? = null
    private val playerOwnedMediaFiles = mutableSetOf<Any>()
    private var playerMediaBusy = false
    private var metricsTimer: Timer? = null
    private var statusView: TextView? = null
    private var downlinkMetricsPanel: DownlinkMetricsPanel? = null
    private var streamBubble: TextView? = null
    private var commandHistoryView: TextView? = null
    private var commandHistory = "暂无命令记录"
    private var activeScanner: DecoratedBarcodeView? = null
    private var scannerProcessing = false
    private var storeFlow: TiStoreExampleFlow? = null
    private var storeSelectedRange: TiStoreRecordingRange? = null
    private val storeSelectedDate: Calendar = Calendar.getInstance()
    private var storeRecordingsDialog: Dialog? = null
    private var storeRecordingsContent: LinearLayout? = null
    private var storeExportProgress = -1
    private var storeRecordings: List<TiStoreRecordingRange> = emptyList()
    private var storeStatusView: TextView? = null
    private var storePlaybackStatus = "请选择录像"
    private var storeActionStatusGeneration = 0L
    private var storeActionStatusUntilMs = 0L
    private var storeTimeView: TextView? = null
    private var storeSeekBar: SeekBar? = null
    private var storeStage: FrameLayout? = null
    private var storeRecordingButton: TextView? = null
    private var storeSnapshotButton: TextView? = null
    private var storeGalleryButton: TextView? = null
    private var storeMuteButton: TextView? = null
    private var storeSpeedButton: TextView? = null
    private var storePauseButton: TextView? = null

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
        closeStoreFlow()
        stopPlayer()
        super.onDestroy()
    }

    private fun showConfigure() {
        clearActiveScanner()
        closeStoreFlow()
        stopPlayer()
        statusView = null
        if (configureProduct == ConfigureProduct.STORE) {
            showStoreConfigure()
        } else {
            showRtcConfigure()
        }
    }

    private fun showRtcConfigure() {
        val appIdField = editText("TiRTC 应用标识，进入播放页前必须提供。", clientConfig.appId, viewId = R.id.field_app_id)
        val endpointField = editText("接入的云端环境，留空则使用默认环境。", clientConfig.endpoint, viewId = R.id.field_endpoint)
        val remoteIdField = editText("待连接的远端目标 ID", clientConfig.remoteId, viewId = R.id.field_remote_id)
        val audioStreamField = editText("音频流 ID，默认 10", clientConfig.audioStreamId.toString(), viewId = R.id.field_audio_stream_id)
        val videoStreamField = editText("视频流 ID，默认 11", clientConfig.videoStreamId.toString(), viewId = R.id.field_video_stream_id)
        val tokenSource =
            spinner(
                listOf("tokenIssuer", "oneTimeToken"),
                if (clientConfig.tokenSource == DemoTokenSource.ISSUER) 0 else 1,
            )
        val tokenIssuerField = editText("Token issuer base URL", clientConfig.tokenIssuerBaseUrl)
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
                addViewWithMargin(fieldBlock("app_id", appIdField), bottom = 16)
                addViewWithMargin(fieldBlock("endpoint", endpointField), bottom = 16)
                addViewWithMargin(fieldBlock("remote_id", remoteIdField), bottom = 16)
                addViewWithMargin(
                    twoColumnFields(
                        "audio_stream_id",
                        audioStreamField,
                        "video_stream_id",
                        videoStreamField,
                    ),
                    bottom = 16,
                )
                addViewWithMargin(
                    surface {
                        addView(sectionTitle("连接 Token"))
                        addView(inputLabel("token acquisition"))
                        addViewWithMargin(tokenSource, bottom = 16)
                        addViewWithMargin(fieldBlock("Token 签发服务地址", tokenIssuerField), bottom = 16)
                        addViewWithMargin(fieldBlock("一次性连接 Token", tokenField), bottom = 12)
                        addView(
                            outlinedButton("扫一扫") {
                                showClientQr(appIdField, endpointField, remoteIdField, tokenField)
                            },
                        )
                    },
                    bottom = 20,
                )
                addView(
                    primaryButton("进入播放页面") {
                        val next =
                            readClientConfig(
                                appIdField = appIdField,
                                endpointField = endpointField,
                                remoteIdField = remoteIdField,
                                audioStreamField = audioStreamField,
                                videoStreamField = videoStreamField,
                                tokenSource = tokenSource.selectedItemPosition,
                                tokenIssuerField = tokenIssuerField,
                                tokenField = tokenField,
                            ) ?: return@primaryButton
                        clientConfig = next
                        resolveTokenAndShowPlayer(next)
                    },
                )
            },
        )
    }

    private fun showStoreConfigure() {
        val appIdField = editText("TiStore App ID", storeConfig.appId, viewId = R.id.field_store_app_id)
        val endpointField =
            editText("Store Endpoint（可选）", storeConfig.endpoint, viewId = R.id.field_store_endpoint)
        val tokenField =
            editText(
                "APP Access Token",
                storeConfig.token,
                multiLine = true,
                isSecret = true,
                viewId = R.id.field_store_token,
            )
        val audioChannelField =
            editText(
                "音频 Channel ID",
                storeConfig.audioChannelId.toString(),
                viewId = R.id.field_store_audio_channel_id,
            )
        val videoChannelField =
            editText(
                "视频 Channel ID",
                storeConfig.videoChannelId.toString(),
                viewId = R.id.field_store_video_channel_id,
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
                addViewWithMargin(fieldBlock("TiStore App ID", appIdField), bottom = 16)
                addViewWithMargin(fieldBlock("Store Endpoint（可选）", endpointField), bottom = 16)
                addViewWithMargin(fieldBlock("APP Access Token", tokenField), bottom = 16)
                addViewWithMargin(
                    twoColumnFields(
                        "音频 Channel ID",
                        audioChannelField,
                        "视频 Channel ID",
                        videoChannelField,
                    ),
                    bottom = 20,
                )
                addView(
                    primaryButton("进入云录像") {
                        val appId = appIdField.text.toString().trim()
                        val token = tokenField.text.toString().trim()
                        val audioChannel = audioChannelField.text.toString().toIntOrNull()
                        val videoChannel = videoChannelField.text.toString().toIntOrNull()
                        if (appId.isEmpty() || token.isEmpty() || audioChannel !in 0..255 || videoChannel !in 0..255) {
                            toast("请填写 TiStore App ID、APP Access Token 和有效 Channel ID。")
                            return@primaryButton
                        }
                        val next =
                            StoreConfiguration(
                                appId = appId,
                                endpoint = endpointField.text.toString().trim(),
                                token = token,
                                audioChannelId = audioChannel!!,
                                videoChannelId = videoChannel!!,
                            )
                        storeConfig = next
                        showStorePlayer(next)
                    },
                )
            },
        )
    }

    private fun showStorePlayer(config: StoreConfiguration) {
        clearActiveScanner()
        stopPlayer()
        closeStoreFlow()
        val flow = TiStoreExampleFlow()
        storeFlow = flow
        storeSelectedRange = null
        val status = body("正在初始化云录像…").apply { id = R.id.store_status }
        val time = body("--:--:-- / --:--:--").apply { id = R.id.store_seek_time }
        val seek = storeSeekBar(flow)
        val recording =
            outlinedButton("开始本地保存") { toggleStoreRecording(flow, config) }.apply {
                id = R.id.store_recording_button
            }
        val snapshot =
            outlinedButton("截图") { takeStoreSnapshot(flow) }.apply {
                id = R.id.store_snapshot_button
            }
        val gallery =
            outlinedButton("保存到系统相册") { saveStoreMediaToGallery(flow) }.apply {
                id = R.id.store_gallery_button
            }
        val mute =
            outlinedButton("静音") {
                val code = flow.toggleMute()
                val message =
                    if (code == 0) {
                        if (flow.muted) "已静音" else "已恢复声音"
                    } else {
                        "音量设置失败：$code"
                    }
                updateStoreStatus(message)
                updateStoreControls()
            }.apply { id = R.id.store_mute_button }
        val speed =
            outlinedButton("倍速 x1") {
                val values = TiStoreReplaySpeed.entries
                val next = values[(values.indexOf(flow.speed) + 1) % values.size]
                val code = flow.setSpeed(next)
                updateStoreStatus(if (code == 0) "播放倍速：${storeSpeedLabel(next)}" else "倍速设置失败：$code")
                updateStoreControls()
            }.apply { id = R.id.store_speed_button }
        val pause =
            outlinedButton("暂停播放") {
                val code = if (flow.paused) flow.resume() else flow.pause()
                if (code != 0) updateStoreStatus("暂停操作失败：$code")
                updateStoreControls()
            }.apply { id = R.id.store_pause_button }
        storeStatusView = status
        storeTimeView = time
        storeSeekBar = seek
        storeRecordingButton = recording
        storeSnapshotButton = snapshot
        storeGalleryButton = gallery
        storeMuteButton = mute
        storeSpeedButton = speed
        storePauseButton = pause
        val stage = videoPanel("请选择录像").apply { id = R.id.store_video_stage }
        storeStage = stage
        val controls = storePlayerControls(time, seek, recording, snapshot, gallery, mute, speed, pause)
        setContentView(
            frameScreen(
                top =
                    storePlayerTopBar(
                        onBack = {
                            closeStoreFlow {
                                configureProduct = ConfigureProduct.STORE
                                showConfigure()
                            }
                        },
                        onSelectRecording = { showStoreRecordingsDialog(flow, config, query = false) },
                        onUploadLogs = { uploadStoreLogs() },
                    ),
                stage = stage,
                overlay = surface { addView(status) },
                bottom = controls,
            ),
        )
        bindStoreFlowCallbacks(flow)
        val initCode = flow.initialize(this, config.appId, config.endpoint, config.token)
        if (initCode != 0) {
            updateStoreStatus("初始化失败：$initCode")
            updateStoreControls()
            return
        }
        updateStoreStatus("请选择录像")
        updateStoreControls()
        mainHandler.post { if (storeFlow === flow) showStoreRecordingsDialog(flow, config, query = true) }
    }

    private fun storeSeekBar(flow: TiStoreExampleFlow): SeekBar =
        SeekBar(this).apply {
            id = R.id.store_seek_bar
            max = STORE_SEEK_MAX
            isEnabled = false
            setOnSeekBarChangeListener(
                object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(
                        seekBar: SeekBar?,
                        progress: Int,
                        fromUser: Boolean,
                    ) {
                        if (fromUser) updateStoreSeekLabel(progress)
                    }

                    override fun onStartTrackingTouch(seekBar: SeekBar?) = Unit

                    override fun onStopTrackingTouch(seekBar: SeekBar?) {
                        val range = storeSelectedRange ?: return
                        val progress = seekBar?.progress ?: return
                        val target = range.startTimeMs + (range.endTimeMs - range.startTimeMs) * progress / STORE_SEEK_MAX
                        val code = flow.seek(target)
                        updateStoreStatus(if (code == 0) "已跳转到 ${formatStoreTime(target)}" else "跳转失败：$code")
                    }
                },
            )
        }

    private fun storePlayerControls(
        time: TextView,
        seek: SeekBar,
        recording: TextView,
        snapshot: TextView,
        gallery: TextView,
        mute: TextView,
        speed: TextView,
        pause: TextView,
    ): View =
        surface {
            addView(time)
            addView(seek)
            addView(storeControlRow(recording, snapshot, gallery))
            addViewWithMargin(storeControlRow(mute, speed, pause), top = 8, bottom = 0)
        }

    private fun storeControlRow(
        first: View,
        second: View,
        third: View,
    ): View =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(first, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(space(dp(8)))
            addView(second, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(space(dp(8)))
            addView(third, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }

    private fun bindStoreFlowCallbacks(flow: TiStoreExampleFlow) {
        flow.onTimeChanged = { timeMs ->
            if (storeFlow === flow) updateStoreProgress(timeMs)
        }
        flow.onReplayCompleted = {
            if (storeFlow === flow) updateStorePlaybackStatus("录像播放完成")
        }
        flow.onVideoStateChanged = { state ->
            if (storeFlow === flow) {
                updateStorePlaybackStatus(storeVideoStateLabel(state))
                updateStoreControls()
            }
        }
        flow.onAudioStateChanged = { state ->
            if (storeFlow === flow && state.name == "FAILED") updateStoreStatus("音频输出失败")
        }
        flow.onError = { code ->
            if (storeFlow === flow) updateStoreStatus("播放失败：$code")
        }
    }

    private fun showStoreRecordingsDialog(
        flow: TiStoreExampleFlow,
        config: StoreConfiguration,
        query: Boolean,
    ) {
        if (storeFlow !== flow || isFinishing) return
        storeRecordingsDialog?.dismiss()
        val dateRow =
            LinearLayout(this).apply {
                id = R.id.store_recordings_date_row
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    DatePickerDialog(
                        this@MainActivity,
                        { _, year, month, day ->
                            storeSelectedDate.set(year, month, day)
                            showStoreRecordingsDialog(flow, config, query = true)
                        },
                        storeSelectedDate.get(Calendar.YEAR),
                        storeSelectedDate.get(Calendar.MONTH),
                        storeSelectedDate.get(Calendar.DAY_OF_MONTH),
                    ).show()
                }
                addView(
                    LinearLayout(context).apply {
                        orientation = LinearLayout.VERTICAL
                        addView(
                            TextView(context).apply {
                                text = storeDateLabel()
                                setTextColor(ExampleTheme.textPrimary)
                                textSize = 15f
                            },
                        )
                        addView(
                            TextView(context).apply {
                                text = "按设备所在本地日期查询"
                                setTextColor(ExampleTheme.textSecondary)
                                textSize = 12f
                            },
                        )
                    },
                    LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
                )
                addView(
                    appBarActionButton("重新查询") {
                        queryStoreRecordings(flow, config)
                    }.apply { id = R.id.store_query_button },
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(40)),
                )
            }
        val content =
            LinearLayout(this).apply {
                id = R.id.store_recordings_list
                orientation = LinearLayout.VERTICAL
                setPadding(dp(18), dp(8), dp(18), dp(12))
            }
        storeRecordingsContent = content
        val root =
            LinearLayout(this).apply {
                id = R.id.store_recordings_sheet
                orientation = LinearLayout.VERTICAL
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                setPadding(0, dp(6), 0, dp(12))
                setBackgroundColor(ExampleTheme.background)
                addView(
                    View(context).apply {
                        id = R.id.store_sheet_drag_handle
                        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                        setBackgroundColor(ExampleTheme.inputBorder)
                    },
                    LinearLayout.LayoutParams(dp(40), dp(4)).apply {
                        gravity = Gravity.CENTER_HORIZONTAL
                    },
                )
                addViewWithMargin(
                    dateRow.apply {
                        setPadding(dp(18), dp(10), dp(18), dp(10))
                    },
                    top = dp(2),
                    bottom = 0,
                )
                addView(
                    View(context).apply { setBackgroundColor(ExampleTheme.inputBorder) },
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 1),
                )
                addView(
                    ScrollView(this@MainActivity).apply {
                        isFillViewport = true
                        addView(content)
                    },
                    LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f),
                )
            }
        root.layoutParams =
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                (resources.displayMetrics.heightPixels * 0.72).toInt(),
            )
        val dialog = BottomSheetDialog(this)
        dialog.setContentView(root)
        dialog.setOnDismissListener {
            if (storeRecordingsDialog === dialog) {
                storeRecordingsDialog = null
                storeRecordingsContent = null
            }
        }
        dialog.behavior.apply {
            peekHeight = root.layoutParams.height
            isFitToContents = true
        }
        storeRecordingsDialog = dialog
        dialog.show()
        dialog.behavior.state = BottomSheetBehavior.STATE_EXPANDED
        if (query) queryStoreRecordings(flow, config) else renderStoreRecordings(storeRecordings, null, flow, config)
    }

    private fun queryStoreRecordings(
        flow: TiStoreExampleFlow,
        config: StoreConfiguration,
    ) {
        if (storeFlow !== flow) return
        renderStoreRecordings(emptyList(), "正在查询…")
        val bounds = storeQueryBounds()
        val accepted =
            flow.query(bounds.first, bounds.second) { result ->
                if (storeFlow !== flow) return@query
                if (result.code != 0) {
                    storeRecordings = emptyList()
                    renderStoreRecordings(emptyList(), "查询失败：${result.code}")
                    updateStoreStatus("查询失败：${result.code}")
                } else {
                    val recordings =
                        result.recordings.sortedWith(
                            compareByDescending<TiStoreRecordingRange> { it.startTimeMs }
                                .thenByDescending { it.endTimeMs },
                        )
                    storeRecordings = recordings
                    renderStoreRecordings(recordings, null, flow, config)
                    updateStoreStatus("查询完成：${result.recordings.size} 段录像")
                }
            }
        if (accepted != 0) {
            renderStoreRecordings(emptyList(), "查询启动失败：$accepted")
            updateStoreStatus("查询启动失败：$accepted")
        }
    }

    private fun renderStoreRecordings(
        recordings: List<TiStoreRecordingRange>,
        message: String?,
        flow: TiStoreExampleFlow? = null,
        config: StoreConfiguration? = null,
    ) {
        val content = storeRecordingsContent ?: return
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
                                if (flow != null && config != null) queryStoreRecordings(flow, config)
                            }.apply { id = R.id.store_query_retry_button },
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
        val exportBusy = storeExportProgress >= 0
        recordings.forEachIndexed { index, range ->
            val row =
                LinearLayout(this).apply {
                    id = R.id.store_recording_play
                    contentDescription = "播放录像"
                    gravity = Gravity.CENTER_VERTICAL
                    orientation = LinearLayout.HORIZONTAL
                    isClickable = true
                    isFocusable = true
                    setOnClickListener {
                        storeRecordingsDialog?.dismiss()
                        if (flow != null && config != null) playStoreRecording(flow, config, range)
                    }
                    val label =
                        TextView(context).apply {
                            id = R.id.store_recording_row_label
                            text =
                                "${formatStoreTime(range.startTimeMs)} — ${formatStoreTime(range.endTimeMs)}\n" +
                                formatStoreDuration(range.endTimeMs - range.startTimeMs)
                            setTextColor(ExampleTheme.textPrimary)
                            textSize = 14f
                            setPadding(dp(8), dp(12), dp(8), dp(12))
                        }
                    addView(label, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
                    addView(
                        appBarActionButton(if (exportBusy) "${storeExportProgress}%" else "直接导出") {
                            if (flow != null && config != null) exportStoreRecording(flow, config, range)
                        }.apply {
                            id = R.id.store_range_export
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

    private fun playStoreRecording(
        flow: TiStoreExampleFlow,
        config: StoreConfiguration,
        range: TiStoreRecordingRange,
    ) {
        val stage = storeStage
        if (stage == null) {
            updateStoreStatus("播放区域不可用")
            return
        }
        val code = flow.play(range, stage, config.videoChannelId, config.audioChannelId)
        if (code == 0) {
            storeSelectedRange = range
            updateStoreProgress(range.startTimeMs)
        } else {
            updateStoreStatus("播放启动失败：$code")
        }
        updateStoreControls()
    }

    private fun toggleStoreRecording(
        flow: TiStoreExampleFlow,
        config: StoreConfiguration,
    ) {
        val code =
            flow.toggleRecording(config.videoChannelId, config.audioChannelId) { started, resultCode, path ->
                if (storeFlow !== flow) return@toggleRecording
                updateStoreStatus(
                    when {
                        resultCode != 0 -> "边播边录失败：$resultCode"
                        started -> "边播边录已开始"
                        else -> "边播边录完成${path?.let { "：$it" }.orEmpty()}"
                    },
                )
                updateStoreControls()
            }
        if (code != 0) updateStoreStatus("边播边录操作失败：$code")
        updateStoreControls()
    }

    private fun takeStoreSnapshot(flow: TiStoreExampleFlow) {
        val code =
            flow.takeSnapshot { resultCode, path ->
                if (storeFlow !== flow) return@takeSnapshot
                updateStoreStatus(if (resultCode == 0) "截图完成${path?.let { "：$it" }.orEmpty()}" else "截图失败：$resultCode")
                updateStoreControls()
            }
        if (code != 0) updateStoreStatus("截图启动失败：$code")
    }

    private fun exportStoreRecording(
        flow: TiStoreExampleFlow,
        config: StoreConfiguration,
        range: TiStoreRecordingRange,
    ) {
        if (storeExportProgress >= 0) return
        storeExportProgress = 0
        renderStoreRecordings(storeRecordings, null, flow, config)
        val code =
            flow.export(
                range,
                config.videoChannelId,
                config.audioChannelId,
                onProgress = { progress ->
                    if (storeFlow !== flow) return@export
                    storeExportProgress = ((progress * 100).toInt()).coerceIn(0, 99)
                    renderStoreRecordings(storeRecordings, null, flow, config)
                    updateStoreStatus("范围下载 ${storeExportProgress}%")
                },
            ) { resultCode, path ->
                if (storeFlow !== flow) return@export
                storeExportProgress = -1
                renderStoreRecordings(storeRecordings, null, flow, config)
                updateStoreStatus(if (resultCode == 0) "范围下载完成${path?.let { "：$it" }.orEmpty()}" else "范围下载失败：$resultCode")
                updateStoreControls()
            }
        if (code == 0) {
            updateStoreStatus("范围下载已开始")
        } else {
            storeExportProgress = -1
            renderStoreRecordings(storeRecordings, null, flow, config)
            updateStoreStatus("范围下载启动失败：$code")
        }
        updateStoreControls()
    }

    private fun saveStoreMediaToGallery(flow: TiStoreExampleFlow) {
        val code =
            flow.saveLatestToGallery { resultCode ->
                if (storeFlow !== flow) return@saveLatestToGallery
                updateStoreStatus(if (resultCode == 0) "已保存到系统相册" else "保存到相册失败：$resultCode")
                updateStoreControls()
            }
        if (code != 0) updateStoreStatus("保存到相册启动失败：$code")
    }

    private fun uploadStoreLogs() {
        updateStoreStatus("正在上传日志…")
        val code =
            TiRtcLogging.upload(
                TiRtcLogUploadCallback { resultCode, logId ->
                    updateStoreStatus(
                        if (resultCode == 0) "日志上传完成：${logId.orEmpty()}" else "日志上传失败：$resultCode",
                    )
                },
            )
        if (code != 0) updateStoreStatus("日志上传启动失败：$code")
    }

    private fun updateStoreStatus(message: String) {
        mainHandler.post {
            val target = storeStatusView ?: return@post
            storeActionStatusGeneration += 1
            val generation = storeActionStatusGeneration
            storeActionStatusUntilMs = SystemClock.uptimeMillis() + STORE_ACTION_STATUS_DURATION_MS
            target.text = message
            mainHandler.postDelayed(
                {
                    if (storeStatusView === target && storeActionStatusGeneration == generation) {
                        storeActionStatusUntilMs = 0L
                        target.text = storePlaybackStatus
                    }
                },
                STORE_ACTION_STATUS_DURATION_MS,
            )
        }
    }

    private fun updateStorePlaybackStatus(message: String) {
        mainHandler.post {
            storePlaybackStatus = message
            if (SystemClock.uptimeMillis() >= storeActionStatusUntilMs) {
                storeStatusView?.text = message
            }
        }
    }

    private fun updateStoreProgress(timeMs: Long) {
        val range = storeSelectedRange ?: return
        val duration = (range.endTimeMs - range.startTimeMs).coerceAtLeast(1L)
        val progress = (((timeMs - range.startTimeMs).coerceIn(0L, duration) * STORE_SEEK_MAX) / duration).toInt()
        storeSeekBar?.progress = progress
        storeTimeView?.text = "${formatStoreTime(timeMs)} / ${formatStoreTime(range.endTimeMs)}"
    }

    private fun updateStoreSeekLabel(progress: Int) {
        val range = storeSelectedRange ?: return
        val target = range.startTimeMs + (range.endTimeMs - range.startTimeMs) * progress / STORE_SEEK_MAX
        storeTimeView?.text = "${formatStoreTime(target)} / ${formatStoreTime(range.endTimeMs)}"
    }

    private fun updateStoreControls() {
        val flow = storeFlow
        val playing = flow != null && storeSelectedRange != null

        fun TextView?.enabled(value: Boolean) {
            this?.isEnabled = value
            this?.alpha = if (value) 1f else 0.5f
        }
        storeSeekBar?.isEnabled = playing
        storeRecordingButton.enabled(playing)
        storeSnapshotButton.enabled(playing)
        storeRecordingButton?.text = if (flow?.isRecording == true) "停止本地保存" else "开始本地保存"
        storeGalleryButton.enabled(flow?.hasLatestMedia == true)
        storeMuteButton.enabled(playing && flow?.speed == TiStoreReplaySpeed.X1)
        storeMuteButton?.text = if (flow?.muted == true) "恢复声音" else "静音"
        storeSpeedButton.enabled(playing)
        storeSpeedButton?.text = "倍速 ${storeSpeedLabel(flow?.speed ?: TiStoreReplaySpeed.X1)}"
        storePauseButton.enabled(playing)
        storePauseButton?.text = if (flow?.paused == true) "继续播放" else "暂停播放"
    }

    private fun storeQueryBounds(): Pair<Long, Long> {
        val exactStart = intent.getLongExtra("store_query_start_ms", -1L)
        val exactEnd = intent.getLongExtra("store_query_end_ms", -1L)
        if (exactStart >= 0 && exactEnd > exactStart) return exactStart to exactEnd
        val start = storeSelectedDate.clone() as Calendar
        start.set(Calendar.HOUR_OF_DAY, 0)
        start.set(Calendar.MINUTE, 0)
        start.set(Calendar.SECOND, 0)
        start.set(Calendar.MILLISECOND, 0)
        val end = start.clone() as Calendar
        end.add(Calendar.DAY_OF_MONTH, 1)
        return start.timeInMillis to end.timeInMillis
    }

    private fun storeDateLabel(): String = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(storeSelectedDate.time)

    private fun formatStoreTime(timeMs: Long): String = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(timeMs)

    private fun formatStoreDuration(durationMs: Long): String {
        val seconds = (durationMs / 1000L).coerceAtLeast(0L)
        return "%02d:%02d".format(seconds / 60L, seconds % 60L)
    }

    private fun storeSpeedLabel(speed: TiStoreReplaySpeed): String =
        when (speed) {
            TiStoreReplaySpeed.X1 -> "x1"
            TiStoreReplaySpeed.X2 -> "x2"
            TiStoreReplaySpeed.X4 -> "x4"
            TiStoreReplaySpeed.X8 -> "x8"
        }

    private fun storeVideoStateLabel(state: TiStoreVideoOutputState): String =
        when (state) {
            TiStoreVideoOutputState.IDLE -> "等待播放"
            TiStoreVideoOutputState.BUFFERING -> "缓冲中"
            TiStoreVideoOutputState.RENDERING -> "正在播放"
            TiStoreVideoOutputState.FAILED -> "视频输出失败"
            TiStoreVideoOutputState.PAUSED -> "已暂停"
            TiStoreVideoOutputState.COMPLETED -> "录像播放完成"
        }

    private fun closeStoreFlow(completion: () -> Unit = {}) {
        val flow = storeFlow
        storeFlow = null
        storeRecordingsDialog?.dismiss()
        storeRecordingsDialog = null
        storeRecordingsContent = null
        storeSelectedRange = null
        storeExportProgress = -1
        storeActionStatusGeneration += 1
        storeActionStatusUntilMs = 0L
        storePlaybackStatus = "请选择录像"
        storeStatusView = null
        storeTimeView = null
        storeSeekBar = null
        storeStage = null
        storeRecordingButton = null
        storeSnapshotButton = null
        storeGalleryButton = null
        storeMuteButton = null
        storeSpeedButton = null
        storePauseButton = null
        if (flow == null) {
            completion()
        } else {
            flow.close { code ->
                if (code != 0) Log.w("TiStoreExample", "store cleanup failed code=$code")
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
                navigationHeader("扫一扫") { showConfigure() }
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

    private fun showPlayer(config: ClientConfiguration) {
        clearActiveScanner()
        val videoStage = videoPanel("远端视频")
        val status = body("正在初始化")
        val metrics =
            DownlinkMetricsPanel(
                context = this,
                requestedDecoderPreference = settings.decoderPreference.nativeValue,
                onShowExplanation = { showMetricsExplanation() },
            )
        val bubble = streamBubbleView("等待 stream message")
        val localAudioButton =
            compactFilledButton(
                text = "启动麦克风",
                backgroundColor = ExampleTheme.surface,
                foregroundColor = ExampleTheme.primary,
            ) {
                togglePlayerTalkback()
            }
        val downlinkButton =
            compactFilledButton("连接中") {
                togglePlayerDownlink()
            }
        val outputVolumeButton =
            compactFilledButton(
                text = "静音播放",
                backgroundColor = ExampleTheme.surface,
                foregroundColor = ExampleTheme.primary,
            ) {
                togglePlayerOutputVolume()
            }
        val recordingButton =
            mediaIconButton(android.R.drawable.presence_video_online, "开始本地保存") {
                togglePlayerRecording()
            }
        val snapshotButton =
            mediaIconButton(android.R.drawable.ic_menu_camera, "截图") {
                takePlayerSnapshot()
            }
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
        setContentView(
            frameScreen(
                top =
                    playerTopBar(
                        remoteId = config.remoteId,
                        onBack = {
                            stopPlayer()
                            showConfigure()
                        },
                        onCommand = { showCommandPanel() },
                        onUploadLogs = { uploadLogs() },
                    ),
                stage = videoStage,
                overlay = metrics,
                bottom =
                    playerBottomControls(
                        bubble = bubble,
                        recordingButton = recordingButton,
                        snapshotButton = snapshotButton,
                        localAudioButton = localAudioButton,
                        outputVolumeButton = outputVolumeButton,
                        downlinkButton = downlinkButton,
                    ),
            ),
        )
        startPlayer(config, videoStage)
    }

    private fun startPlayer(
        config: ClientConfiguration,
        stage: FrameLayout,
    ) {
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
        val nextAudio = TiRtcAudioOutput()
        val nextVideo = TiRtcVideoOutput()
        val nextTalkback = TiRtcAudioInput()
        conn = nextConn
        audioOutput = nextAudio
        videoOutput = nextVideo
        playerAudioInput = nextTalkback
        playerTalkbackRunning = false
        nextAudio.onStateChanged = TiRtcAudioOutputStateListener { state -> appendStatus("audio=${state.name}") }
        nextVideo.onStateChanged = TiRtcVideoOutputStateListener { state -> appendStatus("video=${state.name}") }
        nextTalkback.onStateChanged = TiRtcInputStateListener { state -> appendStatus("talkback=${state.name}") }
        nextTalkback.onError =
            TiRtcInputErrorListener { code, message ->
                appendStatus("talkback error=$code ${message ?: ""}")
            }
        nextVideo.onRenderSizeChanged =
            TiRtcVideoOutputRenderSizeListener { size -> appendStatus("video size=${size.width}x${size.height}") }
        nextConn.onCommand =
            TiRtcConnCommandListener { command, data ->
                handleIncomingCommand(nextConn, command, data)
            }
        nextConn.onStreamMessage =
            TiRtcConnStreamMessageListener { streamId, _, data ->
                updateStreamBubble("stream $streamId: ${payloadText(data)}")
            }
        nextConn.onStateChanged =
            TiRtcConnStateListener { state, code ->
                appendStatus("conn=${state.name} code=$code")
                if (state == TiRtcConnState.CONNECTED) {
                    setPlayerControlState(connecting = false, running = true, localAudioEnabled = true)
                    val audioCode = nextAudio.attach(nextConn, config.audioStreamId)
                    val videoCode = nextVideo.attach(nextConn, config.videoStreamId)
                    val audioSubscribeCode = nextConn.subscribeAudio(config.audioStreamId)
                    val videoSubscribeCode = nextConn.subscribeVideo(config.videoStreamId)
                    appendStatus("attach audio=$audioCode video=$videoCode")
                    appendStatus(
                        "subscribe audio=$audioSubscribeCode video=$videoSubscribeCode " +
                            "audioStream=${config.audioStreamId} videoStream=${config.videoStreamId}",
                    )
                    if (audioSubscribeCode != 0 || videoSubscribeCode != 0) {
                        AlertDialog.Builder(this@MainActivity)
                            .setTitle("订阅失败")
                            .setMessage(
                                "音频订阅返回 $audioSubscribeCode，视频订阅返回 $videoSubscribeCode。",
                            )
                            .setPositiveButton("知道了", null)
                            .show()
                    }
                    appendStatus("talkback ready stream=${settings.localAudioStreamId}")
                }
            }
        nextTalkback.setOptions(settings.localAudioOptions())
        nextAudio.configure(TiRtcAudioOutputOptions(bufferStrategy = settings.outputBufferStrategy))
        nextVideo.setOptions(
            TiRtcVideoOutputOptions(
                decoderPreference = settings.decoderPreference.toSdkDecoderPreference(),
                bufferStrategy = settings.outputBufferStrategy,
            ),
        )
        appendStatus("view=${nextVideo.attachView(stage)}")
        appendStatus("connect=${nextConn.connect(config.remoteId, config.token)}")
        startMetricsPolling()
    }

    private fun stopPlayer(clearPageRefs: Boolean = true) {
        metricsTimer?.cancel()
        metricsTimer = null
        emitDownlinkMetricsEvidence()
        stopPlayerTalkback()
        val task = playerRecordingTask
        playerRecordingTask = null
        playerLatestMediaFile = null
        playerMediaBusy = true
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
            val videoUnsubscribeCode = activeConnection.unsubscribeVideo(activeConfig.videoStreamId)
            val audioUnsubscribeCode = activeConnection.unsubscribeAudio(activeConfig.audioStreamId)
            appendStatus(
                "unsubscribe audio=$audioUnsubscribeCode video=$videoUnsubscribeCode " +
                    "audioStream=${activeConfig.audioStreamId} videoStream=${activeConfig.videoStreamId}",
            )
        }
        videoOutput?.dispose()
        videoOutput = null
        audioOutput?.dispose()
        audioOutput = null
        conn?.dispose()
        conn = null
        playerRunning = false
        setPlayerControlState(connecting = false, running = false, localAudioEnabled = false)
        if (clearPageRefs) {
            downlinkMetricsPanel = null
            playerConfig = null
            playerStage = null
            playerLocalAudioButton = null
            playerOutputVolumeButton = null
            playerDownlinkButton = null
        }
        playerMediaBusy = false
        TiRtc.shutdown()
    }

    private fun togglePlayerRecording() {
        if (playerMediaBusy) return
        val activeTask = playerRecordingTask
        if (activeTask != null) {
            playerMediaBusy = true
            activeTask.stop { result ->
                playerRecordingTask = null
                val completedFile = result.file
                deletePlayerMediaFile(playerLatestMediaFile) {
                    playerMediaBusy = false
                    if (result.code == 0 && completedFile != null) {
                        playerLatestMediaFile = completedFile
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
        val result = connection.startRecording(config.videoStreamId, config.audioStreamId)
        if (result.code == 0 && result.task != null) {
            playerRecordingTask = result.task
            appendStatus("正在本地保存")
        } else {
            appendStatus("开始本地保存失败 code=${result.code}")
        }
    }

    private fun takePlayerSnapshot() {
        if (playerMediaBusy) return
        val output = videoOutput ?: return
        playerMediaBusy = true
        output.takeSnapshot { result ->
            val file = result.file
            if (result.code != 0 || file == null) {
                playerMediaBusy = false
                appendStatus("截图失败 code=${result.code}")
                return@takeSnapshot
            }
            deletePlayerMediaFile(playerLatestMediaFile) {
                playerLatestMediaFile = file
                playerOwnedMediaFiles.add(file)
                playerMediaBusy = false
                appendStatus("截图完成 ${file.path}")
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

    private fun emitDownlinkMetricsEvidence() {
        if (conn == null && audioOutput == null && videoOutput == null) {
            return
        }
        val connectionMetrics = conn?.getMetricsSnapshot()
        val audioMetrics = audioOutput?.getMetricsSnapshot()
        val videoMetrics = videoOutput?.getMetricsSnapshot()
        val audioSnapshot = audioMetrics?.snapshot
        val videoSnapshot = videoMetrics?.snapshot
        Log.i(
            DOWNLINK_METRICS_EVIDENCE_TAG,
            "event=downlink_metrics_snapshot " +
                "connection_code=${connectionMetrics?.code ?: -1} " +
                "audio_code=${audioMetrics?.code ?: -1} " +
                "video_code=${videoMetrics?.code ?: -1} " +
                "video_first_output=${if (videoSnapshot?.startup?.hasFirstOutput == true) 1 else 0} " +
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
        playerOutputVolumeButton?.text = if (playerOutputMuted) "恢复声音" else "静音播放"
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
            text =
                when {
                    connecting -> "连接中"
                    running -> "停止播放"
                    else -> "开始播放"
                }
            isEnabled = !connecting
            alpha = if (isEnabled) 1.0f else 0.55f
        }
        updatePlayerLocalAudioButton(enabled = localAudioEnabled)
    }

    private fun updatePlayerLocalAudioButton(enabled: Boolean) {
        playerLocalAudioButton?.apply {
            text = if (playerTalkbackRunning) "停止麦克风" else "启动麦克风"
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
        val video = videoOutput
        downlinkMetricsPanel?.render(connection, audio, video)
    }

    private fun showMetricsExplanation() {
        AlertDialog.Builder(this)
            .setTitle("指标说明")
            .setMessage(DOWNLINK_METRICS_EXPLANATION)
            .setPositiveButton("知道了", null)
            .show()
    }

    private fun showCommandPanel() {
        val commandField = editText("0x00000000", formatCommandId(DEMO_CALL_COMMAND_ID))
        val preset = spinner(listOf("echo", CALL_START, CALL_READY, CALL_REJECT), 0)
        val mode = spinner(listOf("text", "hex"), 0)
        val payloadField = editText("输入文本内容", CALL_START, multiLine = true)
        val history = body(commandHistory)
        commandHistoryView = history
        val root =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(16), dp(10), dp(16), 0)
                addViewWithMargin(fieldBlock("命令 ID", commandField), bottom = 16)
                addView(spinnerBlock("call command schema", preset))
                addView(spinnerBlock("payload mode", mode))
                addViewWithMargin(fieldBlock("命令内容", payloadField), bottom = 16)
                addView(sectionTitle("history"))
                addView(history)
            }
        AlertDialog.Builder(this)
            .setTitle("发送命令")
            .setView(root)
            .setNegativeButton("关闭", null)
            .setPositiveButton("发送") { _, _ ->
                val command = parseCommandIdOrNull(commandField.text.toString(), ::toast) ?: return@setPositiveButton
                val payload =
                    if (preset.selectedItemPosition > 0) {
                        utf8Payload(demoCommandPresetPayload(preset.selectedItemPosition))
                    } else if (mode.selectedItemPosition == 1) {
                        parseHexPayloadOrNull(payloadField.text.toString(), ::toast) ?: return@setPositiveButton
                    } else {
                        utf8Payload(payloadField.text.toString())
                    }
                val code = conn?.sendCommand(command, payload) ?: -1
                appendCommand("sent code=$code", command, payload)
            }
            .show()
    }

    private fun uploadLogs() {
        appendStatus("log upload=start")
        TiRtcLogging.upload(
            TiRtcLogUploadCallback { code, logId ->
                appendStatus("log upload code=$code id=${logId ?: ""}")
            },
        )
    }

    private fun readClientConfig(
        appIdField: EditText,
        endpointField: EditText,
        remoteIdField: EditText,
        audioStreamField: EditText,
        videoStreamField: EditText,
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
        return ClientConfiguration(
            appId = appId,
            endpoint = endpointField.text.toString().trim(),
            remoteId = remoteId,
            audioStreamId = audioStreamField.text.toString().toIntOrNull() ?: DEFAULT_AUDIO_STREAM_ID,
            videoStreamId = videoStreamField.text.toString().toIntOrNull() ?: DEFAULT_VIDEO_STREAM_ID,
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
            val current = statusView?.text?.toString().orEmpty()
            statusView?.text = if (current.isBlank()) message else "$current\n$message"
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
        private const val STORE_SEEK_MAX = 1000
        private const val STORE_ACTION_STATUS_DURATION_MS = 4000L
        private const val METRICS_PERIOD_MS = 1000L
        private const val SCANNER_RETRY_DELAY_MS = 900L
        private const val AUDIO_VOLUME_EVIDENCE_TAG = "TiRtcVolumeEvidence"
        private const val DOWNLINK_METRICS_EVIDENCE_TAG = "TiRtcDomainEvidence"
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
