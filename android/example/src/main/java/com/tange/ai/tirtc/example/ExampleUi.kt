package com.tange.ai.tirtc.example

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView

internal fun Context.page(content: LinearLayout.() -> Unit): ScrollView {
    val horizontalPadding = if (resources.configuration.screenWidthDp >= ExampleTheme.formColumnsBreakpointDp) 24 else 16
    val root =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(horizontalPadding), statusBarInset() + dp(18), dp(horizontalPadding), dp(32))
            setBackgroundColor(ExampleTheme.background)
            content()
        }
    return ScrollView(this).apply {
        setBackgroundColor(ExampleTheme.background)
        isFillViewport = true
        addView(
            FrameLayout(context).apply {
                addView(
                    root,
                    FrameLayout.LayoutParams(
                        if (resources.configuration.screenWidthDp >= ExampleTheme.formColumnsBreakpointDp) {
                            dp(minOf(ExampleTheme.contentMaxWidthDp, resources.configuration.screenWidthDp))
                        } else {
                            match()
                        },
                        wrap(),
                        Gravity.TOP or Gravity.CENTER_HORIZONTAL,
                    ),
                )
            },
            ViewGroup.LayoutParams(match(), wrap()),
        )
    }
}

internal fun Context.frameScreen(
    top: View,
    stage: FrameLayout,
    overlay: View,
    bottom: View? = null,
): FrameLayout {
    return FrameLayout(this).apply {
        setBackgroundColor(ExampleTheme.videoBackground)
        addView(stage, FrameLayout.LayoutParams(match(), match()))
        addView(top, FrameLayout.LayoutParams(match(), wrap(), Gravity.TOP))
        addView(
            overlay,
            FrameLayout.LayoutParams(match(), wrap(), Gravity.TOP).apply {
                topMargin = statusBarInset() + dp(78)
                leftMargin = dp(18)
                rightMargin = dp(18)
            },
        )
        if (bottom != null) {
            addView(bottom, FrameLayout.LayoutParams(match(), wrap(), Gravity.BOTTOM))
        }
    }
}

internal fun LinearLayout.header(
    title: String,
    primaryAction: Pair<String, () -> Unit>,
    secondaryAction: Pair<String, () -> Unit>? = null,
) {
    val row =
        LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            val stacked = resources.configuration.fontScale >= 1.5f
            orientation = if (stacked) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
            addView(
                LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(
                        TextView(context).apply {
                            text = title
                            setTextColor(ExampleTheme.brandText)
                            textSize = 22f
                            typeface = Typeface.DEFAULT_BOLD
                        },
                    )
                    addView(
                        TextView(context).apply {
                            text = "Based on Android"
                            setTextColor(ExampleTheme.textHint)
                            textSize = 12f
                        },
                    )
                },
                if (stacked) LinearLayout.LayoutParams(match(), wrap()) else LinearLayout.LayoutParams(0, wrap(), 1f),
            )
            addView(context.chipButton(primaryAction.first, primaryAction.second), context.chipLayoutParams())
            if (secondaryAction != null) {
                addView(context.chipButton(secondaryAction.first, secondaryAction.second), context.chipLayoutParams())
            }
        }
    addViewWithMargin(row, bottom = 20)
}

internal fun LinearLayout.navigationHeader(
    title: String,
    back: () -> Unit,
) {
    val row =
        LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            orientation = LinearLayout.HORIZONTAL
            addView(context.chipButton("返回", back), context.chipLayoutParams())
            addView(
                TextView(context).apply {
                    text = title
                    setTextColor(ExampleTheme.primary)
                    textSize = 18f
                    typeface = Typeface.DEFAULT_BOLD
                    gravity = Gravity.END
                },
                LinearLayout.LayoutParams(0, wrap(), 1f),
            )
        }
    addViewWithMargin(row, bottom = 20)
}

internal fun Context.productTabs(
    selected: ConfigureProduct,
    onSelected: (ConfigureProduct) -> Unit,
): View =
    LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setPadding(dp(3), dp(3), dp(3), dp(3))
        minimumHeight = dp(ExampleTheme.minimumTouchTargetDp)
        background = rounded(0x1A659287, radius = 22, strokeColor = 0x1A659287)

        fun tab(
            label: String,
            product: ConfigureProduct,
        ): TextView =
            TextView(context).apply {
                text = label
                gravity = Gravity.CENTER
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(if (selected == product) ExampleTheme.foreground else ExampleTheme.textSecondary)
                background =
                    rounded(
                        if (selected == product) ExampleTheme.primary else 0x00000000,
                        radius = 19,
                        strokeColor = if (selected == product) ExampleTheme.primary else 0x00000000,
                    )
                setOnClickListener { onSelected(product) }
            }
        val rtc = tab("RTC", ConfigureProduct.RTC)
        rtc.id = R.id.tab_rtc
        val cloudStorage = tab("云录像", ConfigureProduct.CLOUD_STORAGE)
        cloudStorage.id = R.id.tab_cloud_storage
        addView(rtc, LinearLayout.LayoutParams(0, dp(ExampleTheme.minimumTouchTargetDp), 1f))
        addView(space(dp(3)))
        addView(cloudStorage, LinearLayout.LayoutParams(0, dp(ExampleTheme.minimumTouchTargetDp), 1f))
    }

internal fun Context.cloudStoragePlayerTopBar(
    onBack: () -> Unit,
    onSelectRecording: () -> Unit,
    onUploadLogs: () -> Unit,
): View =
    LinearLayout(this).apply {
        gravity = Gravity.CENTER_VERTICAL
        orientation = LinearLayout.HORIZONTAL
        setPadding(dp(16), statusBarInset() + dp(12), dp(12), dp(10))
        setBackgroundColor(ExampleTheme.background)
        addView(appBarBackButton(onBack).apply { id = R.id.cloud_storage_back_button }, appBarBackLayoutParams())
        addView(
            TextView(context).apply {
                text = "云录像"
                setTextColor(ExampleTheme.primary)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
            },
            LinearLayout.LayoutParams(0, wrap(), 1f),
        )
        addView(
            appBarActionButton("选择录像", onSelectRecording).apply {
                id = R.id.cloud_storage_recordings_button
                isFocusable = true
                isFocusableInTouchMode = true
            },
            appBarActionLayoutParams(),
        )
        addView(
            appBarActionButton("上传日志", onUploadLogs).apply { id = R.id.cloud_storage_upload_logs_button },
            appBarActionLayoutParams(),
        )
    }

internal fun Context.playerTopBar(
    remoteId: String,
    onBack: () -> Unit,
    onCommand: (View) -> Unit,
    onUploadLogs: () -> Unit,
): View {
    return LinearLayout(this).apply {
        gravity = Gravity.CENTER_VERTICAL
        orientation = LinearLayout.HORIZONTAL
        setPadding(dp(16), statusBarInset() + dp(12), dp(12), dp(10))
        setBackgroundColor(ExampleTheme.background)
        addView(appBarBackButton(onBack), appBarBackLayoutParams())
        addView(
            TextView(context).apply {
                text = remoteId
                setTextColor(ExampleTheme.primary)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                setSingleLine(true)
                ellipsize = TextUtils.TruncateAt.END
            },
            LinearLayout.LayoutParams(0, wrap(), 1f),
        )
        addView(
            appBarActionButton("发送命令") {}.apply {
                id = R.id.player_command_button
                isFocusable = true
                isFocusableInTouchMode = true
                setOnClickListener(onCommand)
            },
            appBarActionLayoutParams(),
        )
        addView(appBarActionButton("上传日志", onUploadLogs), appBarActionLayoutParams())
    }
}

internal fun Context.playerBottomControls(
    bubble: TextView,
    recordingButton: View,
    snapshotButton: View,
    galleryButton: View,
    localAudioButton: TextView,
    outputVolumeButton: TextView,
    downlinkButton: TextView,
    moreButton: TextView,
): View {
    val wide = resources.configuration.expandPlaybackSecondaryActions()
    return LinearLayout(this).apply {
        gravity = Gravity.END
        orientation = LinearLayout.VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(12))
        addView(
            bubble,
            LinearLayout.LayoutParams(wrap(), wrap()).apply {
                gravity = Gravity.END
            },
        )
        addViewWithMargin(
            LinearLayout(context).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                orientation = LinearLayout.HORIZONTAL
                setPadding(dp(6), dp(6), dp(6), dp(6))
                background = rounded(ExampleTheme.controlSurface, ExampleTheme.radiusLarge, ExampleTheme.divider)
                addView(downlinkButton, context.controlButtonLayoutParams())
                addView(outputVolumeButton, context.controlButtonLayoutParams())
                addView(localAudioButton, context.controlButtonLayoutParams())
                if (wide) {
                    addView(recordingButton, context.mediaButtonLayoutParams())
                    addView(snapshotButton, context.mediaButtonLayoutParams())
                    addView(galleryButton, context.mediaButtonLayoutParams())
                }
                addView(moreButton, context.controlButtonLayoutParams())
            },
            top = 8,
            bottom = 0,
        )
    }
}

internal fun Context.cloudStoragePlayerControls(
    time: TextView,
    seek: android.widget.SeekBar,
    recording: TextView,
    snapshot: TextView,
    gallery: TextView,
    mute: TextView,
    speed: TextView,
    pause: TextView,
    more: TextView,
): View =
    LinearLayout(this).apply {
        val wide = resources.configuration.screenWidthDp >= ExampleTheme.compactBreakpointDp
        orientation = if (wide) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(8))
        background = rounded(ExampleTheme.controlSurface, ExampleTheme.radiusLarge, ExampleTheme.divider)
        val timeline =
            FrameLayout(context).apply {
                addView(seek, FrameLayout.LayoutParams(match(), dp(48), Gravity.CENTER_VERTICAL))
                time.textSize = 10f
                time.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                time.setBackgroundColor(0xCCFAFAF8.toInt())
                addView(time, FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.CENTER_HORIZONTAL))
            }
        addView(
            timeline,
            if (wide) LinearLayout.LayoutParams(0, dp(64), 1f) else LinearLayout.LayoutParams(match(), dp(48)),
        )
        val actions = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        actions.addView(pause, LinearLayout.LayoutParams(0, dp(48), 1f))
        actions.addView(mute, LinearLayout.LayoutParams(0, dp(48), 1f))
        actions.addView(speed, LinearLayout.LayoutParams(0, dp(48), 1f))
        if (resources.configuration.expandPlaybackSecondaryActions()) {
            actions.addView(recording, LinearLayout.LayoutParams(0, dp(48), 1f))
            actions.addView(snapshot, LinearLayout.LayoutParams(0, dp(48), 1f))
            actions.addView(gallery, LinearLayout.LayoutParams(0, dp(48), 1f))
        }
        actions.addView(more, LinearLayout.LayoutParams(0, dp(48), 1f))
        addView(actions, if (wide) LinearLayout.LayoutParams(dp(420), dp(48)) else LinearLayout.LayoutParams(match(), dp(48)))
    }

internal fun Context.mediaIconButton(
    iconResource: Int,
    description: String,
    action: () -> Unit,
): ImageButton =
    ImageButton(this).apply {
        setImageResource(iconResource)
        contentDescription = description
        setColorFilter(ExampleTheme.primary)
        background = rounded(0xFFD9E5E2.toInt(), radius = 24, strokeColor = 0xFFD9E5E2.toInt())
        setPadding(dp(13), dp(13), dp(13), dp(13))
        setOnClickListener { action() }
    }

private fun Context.mediaButtonLayoutParams(): LinearLayout.LayoutParams =
    LinearLayout.LayoutParams(dp(48), dp(48)).apply { marginStart = dp(6) }

private fun Context.controlButtonLayoutParams(): LinearLayout.LayoutParams =
    LinearLayout.LayoutParams(0, dp(48), 1f).apply { marginStart = dp(4) }

internal fun Context.appBarActionButton(
    text: String,
    action: () -> Unit,
): TextView {
    return TextView(this).apply {
        this.text = text
        gravity = Gravity.CENTER
        setTextColor(ExampleTheme.primary)
        textSize = 12f
        typeface = Typeface.DEFAULT_BOLD
        background = rounded(ExampleTheme.background, radius = 10, strokeColor = ExampleTheme.primary)
        setPadding(dp(12), 0, dp(12), 0)
        setSingleLine(true)
        setOnClickListener { action() }
    }
}

internal fun Context.appBarBackButton(action: () -> Unit): TextView {
    return TextView(this).apply {
        text = "‹"
        contentDescription = "返回"
        gravity = Gravity.CENTER
        setTextColor(ExampleTheme.primary)
        textSize = 30f
        typeface = Typeface.DEFAULT_BOLD
        background = rounded(ExampleTheme.background, radius = 22, strokeColor = ExampleTheme.inputBorder)
        setOnClickListener { action() }
    }
}

internal fun Context.videoPanel(label: String): FrameLayout {
    return FrameLayout(this).apply {
        setBackgroundColor(ExampleTheme.videoBackground)
        addView(
            TextView(context).apply {
                text = label
                setTextColor(ExampleTheme.foreground)
                textSize = 16f
                gravity = Gravity.CENTER
            },
            FrameLayout.LayoutParams(match(), match()),
        )
    }
}

internal fun Context.addPlayerEmptyVideoState(
    stage: FrameLayout,
    audioStreamId: Int?,
): TextView =
    TextView(this).apply {
        id = R.id.player_empty_video_state
        text = if (audioStreamId == null) "未选择媒体流" else "仅音频播放"
        contentDescription = text
        gravity = Gravity.CENTER
        setTextColor(ExampleTheme.foreground)
        textSize = 16f
        stage.addView(this, FrameLayout.LayoutParams(match(), match()))
    }

internal fun Context.qrGuide(text: String): View {
    return surface {
        val details = body(text).apply {
            id = R.id.qr_guide_details
            visibility = View.GONE
            contentDescription = "二维码格式说明：$text"
        }
        addView(
            appBarActionButton("查看二维码格式帮助") {
                details.visibility = if (details.visibility == View.VISIBLE) View.GONE else View.VISIBLE
            }.apply {
                id = R.id.qr_guide_disclosure
                contentDescription = "展开或收起二维码格式帮助"
            },
            LinearLayout.LayoutParams(match(), dp(ExampleTheme.minimumTouchTargetDp)),
        )
        addView(details)
    }
}

internal fun Context.scannerPanel(scannerView: View): FrameLayout {
    val side = (resources.displayMetrics.widthPixels - dp(48)).coerceAtMost(dp(390))
    return FrameLayout(this).apply {
        id = R.id.qr_scanner_panel
        layoutParams =
            LinearLayout.LayoutParams(match(), side).apply {
                bottomMargin = dp(14)
            }
        background = rounded(ExampleTheme.videoBackground, radius = ExampleTheme.radiusLarge, strokeColor = ExampleTheme.inputBorder)
        clipToOutline = true
        addView(scannerView, FrameLayout.LayoutParams(match(), match()))
        addView(
            TextView(context).apply {
                text = "对准二维码"
                gravity = Gravity.CENTER
                setTextColor(ExampleTheme.foreground)
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                background = rounded(0x66000000, radius = 16, strokeColor = 0x00000000)
                setPadding(dp(12), dp(6), dp(12), dp(6))
            },
            FrameLayout.LayoutParams(wrap(), wrap(), Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply {
                topMargin = dp(16)
            },
        )
    }
}

internal fun Context.fieldBlock(
    label: String,
    control: View,
): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        addView(inputLabel(label))
        addView(control)
    }
}

internal fun Context.formSection(
    title: String,
    content: LinearLayout.() -> Unit,
): LinearLayout =
    surface {
        addView(sectionTitle(title).apply { textSize = 15f })
        content()
    }

internal fun Context.responsiveFormSections(sections: List<View>): View {
    val wide = resources.configuration.screenWidthDp >= ExampleTheme.formColumnsBreakpointDp
    if (!wide) {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            sections.forEachIndexed { index, section ->
                addView(section, LinearLayout.LayoutParams(match(), wrap()).apply { bottomMargin = if (index == sections.lastIndex) 0 else dp(12) })
            }
        }
    }
    val left = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    val right = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    sections.forEachIndexed { index, section ->
        val column = if (index % 2 == 0) left else right
        column.addView(section, LinearLayout.LayoutParams(match(), wrap()).apply { bottomMargin = dp(12) })
    }
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        addView(left, LinearLayout.LayoutParams(0, wrap(), 1f))
        addView(space(dp(16)))
        addView(right, LinearLayout.LayoutParams(0, wrap(), 1f))
    }
}

internal fun Context.twoColumnFields(
    firstLabel: String,
    first: EditText,
    secondLabel: String,
    second: EditText,
): View {
    return LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        addView(fieldBlock(firstLabel, first), LinearLayout.LayoutParams(0, wrap(), 1f))
        addView(space(dp(16)))
        addView(fieldBlock(secondLabel, second), LinearLayout.LayoutParams(0, wrap(), 1f))
    }
}

internal fun Context.spinnerBlock(
    label: String,
    spinner: Spinner,
): View {
    return surface {
        addView(sectionTitle(label))
        addView(spinner)
    }
}

internal fun Context.editText(
    placeholder: String,
    value: String = "",
    multiLine: Boolean = false,
    isSecret: Boolean = false,
    viewId: Int = View.NO_ID,
): EditText {
    return EditText(this).apply {
        id = viewId
        hint = placeholder
        setText(value)
        setTextColor(ExampleTheme.textPrimary)
        setHintTextColor(ExampleTheme.textHint)
        setSingleLine(!multiLine)
        textSize = 13f
        minHeight = if (multiLine) dp(118) else dp(56)
        minLines = if (multiLine) 3 else 1
        gravity = if (multiLine) Gravity.TOP or Gravity.START else Gravity.CENTER_VERTICAL or Gravity.START
        setPadding(dp(20), dp(12), dp(20), dp(12))
        inputType =
            when {
                isSecret -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                multiLine -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
                else -> InputType.TYPE_CLASS_TEXT
            }
        background = rounded(ExampleTheme.surface, radius = ExampleTheme.radiusMedium, strokeColor = ExampleTheme.inputBorder)
    }
}

internal fun Context.spinner(
    values: List<String>,
    selected: Int,
): Spinner {
    return Spinner(this).apply {
        adapter = ArrayAdapter(this@spinner, android.R.layout.simple_spinner_dropdown_item, values)
        setSelection(selected)
        onItemSelectedListener =
            object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(
                    parent: AdapterView<*>?,
                    view: View?,
                    position: Int,
                    id: Long,
                ) = Unit

                override fun onNothingSelected(parent: AdapterView<*>?) = Unit
            }
    }
}

internal fun Context.surface(content: LinearLayout.() -> Unit): LinearLayout {
    return LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(18), dp(14), dp(18), dp(14))
        background = rounded(ExampleTheme.surface, radius = ExampleTheme.radiusLarge, strokeColor = ExampleTheme.inputBorder)
        content()
    }
}

internal fun Context.primaryButton(
    text: String,
    action: () -> Unit,
): TextView {
    return TextView(this).apply {
        this.text = text
        gravity = Gravity.CENTER
        minHeight = dp(56)
        setTextColor(ExampleTheme.foreground)
        textSize = 16f
        typeface = Typeface.DEFAULT_BOLD
        background = rounded(ExampleTheme.primary, radius = 28, strokeColor = ExampleTheme.primary)
        setPadding(dp(18), dp(14), dp(18), dp(14))
        setOnClickListener { action() }
    }
}

internal fun Context.compactFilledButton(
    text: String,
    backgroundColor: Int = ExampleTheme.primary,
    foregroundColor: Int = ExampleTheme.foreground,
    action: () -> Unit,
): TextView {
    return TextView(this).apply {
        this.text = text
        gravity = Gravity.CENTER
        minHeight = dp(54)
        minWidth = dp(116)
        setTextColor(foregroundColor)
        textSize = 14f
        typeface = Typeface.DEFAULT_BOLD
        background = rounded(backgroundColor, radius = 28, strokeColor = backgroundColor)
        setPadding(dp(16), dp(12), dp(16), dp(12))
        setOnClickListener { action() }
    }
}

internal fun Context.playbackControlButton(
    compactText: String,
    description: String,
    wideText: String = description,
    emphasized: Boolean = false,
    action: () -> Unit,
): TextView =
    TextView(this).apply {
        val wide = resources.configuration.expandPlaybackLabels()
        text = if (wide) wideText else compactText
        contentDescription = description
        gravity = Gravity.CENTER
        minHeight = dp(ExampleTheme.minimumTouchTargetDp)
        minimumWidth = 0
        setTextColor(if (emphasized) ExampleTheme.foreground else ExampleTheme.primary)
        textSize = 12f
        typeface = Typeface.DEFAULT_BOLD
        background =
            rounded(
                if (emphasized) ExampleTheme.primary else ExampleTheme.controlSurface,
                radius = ExampleTheme.radiusMedium,
                strokeColor = if (emphasized) ExampleTheme.primary else ExampleTheme.divider,
            )
        setPadding(dp(6), 0, dp(6), 0)
        setOnClickListener { action() }
    }

internal fun Context.playbackMoreButton(action: () -> Unit): TextView =
    playbackControlButton("⋯", "更多", action = action).apply {
        isFocusable = true
        isFocusableInTouchMode = true
    }

internal fun TextView.updatePlaybackControl(
    compactText: String,
    wideText: String,
    description: String,
) {
    text = if (resources.configuration.expandPlaybackLabels()) wideText else compactText
    contentDescription = description
}

internal fun Context.playbackStatusSurface(status: TextView): View =
    LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(12), dp(8), dp(12), dp(8))
        background = rounded(0xE6FAFAF8.toInt(), ExampleTheme.radiusMedium, ExampleTheme.divider)
        status.maxLines = 2
        status.ellipsize = TextUtils.TruncateAt.END
        status.textSize = 12f
        addView(status, LinearLayout.LayoutParams(match(), wrap()))
    }

internal fun android.content.res.Configuration.expandPlaybackSecondaryActions(): Boolean =
    screenWidthDp >= ExampleTheme.secondaryActionsBreakpointDp && fontScale <= 1.3f

internal fun android.content.res.Configuration.expandPlaybackLabels(): Boolean =
    screenWidthDp >= ExampleTheme.secondaryActionsBreakpointDp && fontScale <= 1.3f

internal fun Context.outlinedButton(
    text: String,
    action: () -> Unit,
): TextView {
    return TextView(this).apply {
        this.text = text
        gravity = Gravity.CENTER
        minHeight = dp(48)
        setTextColor(ExampleTheme.primary)
        textSize = 14f
        typeface = Typeface.DEFAULT_BOLD
        background = rounded(ExampleTheme.surface, radius = 24, strokeColor = ExampleTheme.primary)
        setPadding(dp(16), dp(10), dp(16), dp(10))
        setOnClickListener { action() }
    }
}

internal fun Context.chipButton(
    text: String,
    action: () -> Unit,
): TextView {
    return TextView(this).apply {
        this.text = text
        gravity = Gravity.CENTER
        textSize = 13f
        minHeight = dp(ExampleTheme.minimumTouchTargetDp)
        minWidth = dp(76)
        typeface = Typeface.DEFAULT_BOLD
        setPadding(dp(14), 0, dp(14), 0)
        setTextColor(ExampleTheme.primary)
        background = rounded(ExampleTheme.surface, radius = 28, strokeColor = ExampleTheme.primary)
        setOnClickListener { action() }
    }
}

internal fun Context.linkButton(
    text: String,
    action: () -> Unit,
): TextView {
    return TextView(this).apply {
        this.text = text
        gravity = Gravity.CENTER
        setTextColor(ExampleTheme.textSecondary)
        textSize = 13f
        typeface = Typeface.defaultFromStyle(Typeface.ITALIC)
        setPadding(dp(8), dp(14), dp(8), dp(14))
        setOnClickListener { action() }
    }
}

internal fun Context.sectionTitle(text: String): TextView {
    return TextView(this).apply {
        this.text = text
        setTextColor(ExampleTheme.textPrimary)
        textSize = 13f
        typeface = Typeface.DEFAULT_BOLD
        setPadding(0, 0, 0, dp(8))
    }
}

internal fun Context.inputLabel(text: String): TextView {
    return TextView(this).apply {
        this.text = text
        setTextColor(ExampleTheme.textSecondary)
        textSize = 14f
        typeface = Typeface.DEFAULT_BOLD
        setPadding(dp(20), 0, dp(20), dp(4))
    }
}

internal fun Context.body(text: String): TextView {
    return TextView(this).apply {
        this.text = text
        setTextColor(ExampleTheme.textSecondary)
        textSize = 14f
    }
}

internal fun Context.streamBubbleView(text: String): TextView {
    return TextView(this).apply {
        this.text = text
        setTextColor(ExampleTheme.textPrimary)
        textSize = 13f
        background = rounded(ExampleTheme.surface, radius = 18, strokeColor = ExampleTheme.primary)
        setPadding(dp(14), dp(10), dp(14), dp(10))
    }
}

internal fun Context.space(width: Int): View {
    return View(this).apply {
        layoutParams = LinearLayout.LayoutParams(width, 1)
    }
}

internal fun LinearLayout.addViewWithMargin(
    view: View,
    top: Int = 0,
    bottom: Int = 14,
) {
    addView(
        view,
        LinearLayout.LayoutParams(match(), wrap()).apply {
            topMargin = top
            bottomMargin = bottom
        },
    )
}

private fun Context.compactButtonLayoutParams(): LinearLayout.LayoutParams {
    return LinearLayout.LayoutParams(wrap(), wrap()).apply {
        leftMargin = dp(12)
    }
}

private fun Context.appBarBackLayoutParams(): LinearLayout.LayoutParams {
    return LinearLayout.LayoutParams(dp(ExampleTheme.minimumTouchTargetDp), dp(ExampleTheme.minimumTouchTargetDp)).apply {
        rightMargin = dp(8)
    }
}

private fun Context.appBarActionLayoutParams(): LinearLayout.LayoutParams {
    return LinearLayout.LayoutParams(wrap(), dp(ExampleTheme.minimumTouchTargetDp)).apply {
        leftMargin = dp(8)
    }
}

private fun Context.rounded(
    color: Int,
    radius: Int,
    strokeColor: Int,
): GradientDrawable {
    return GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius).toFloat()
        setStroke(1, strokeColor)
    }
}

internal fun Context.dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

private fun Context.statusBarInset(): Int {
    val resourceId = resources.getIdentifier("status_bar_height", "dimen", "android")
    return if (resourceId > 0) resources.getDimensionPixelSize(resourceId) else dp(28)
}

private fun Context.chipLayoutParams(): LinearLayout.LayoutParams {
    return LinearLayout.LayoutParams(wrap(), dp(48)).apply {
        leftMargin = dp(8)
    }
}

private fun match(): Int = ViewGroup.LayoutParams.MATCH_PARENT

private fun wrap(): Int = ViewGroup.LayoutParams.WRAP_CONTENT
