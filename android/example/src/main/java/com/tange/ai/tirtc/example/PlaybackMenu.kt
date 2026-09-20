package com.tange.ai.tirtc.example

import android.content.Context
import android.view.View
import android.widget.PopupMenu
import androidx.core.view.MenuItemCompat

internal data class PlaybackMenuAction(
    val id: Int,
    val label: String,
    val accessibilitySelector: String,
    val enabled: () -> Boolean,
    val unavailableMessage: () -> String,
    val dispatch: () -> Unit,
)

internal fun Context.showPlaybackActionMenu(
    anchor: View,
    actions: List<PlaybackMenuAction>,
    showUnavailable: (String) -> Unit,
): PopupMenu =
    PopupMenu(this, anchor).apply {
        anchor.contentDescription = playbackMenuSummary(actions)
        actions.forEachIndexed { index, action ->
            val item = menu.add(0, action.id, index, action.label)
            item.isEnabled = action.enabled()
            MenuItemCompat.setContentDescription(
                item,
                if (item.isEnabled) action.accessibilitySelector else "${action.accessibilitySelector}，不可用：${action.unavailableMessage()}",
            )
        }
        setOnMenuItemClickListener { item ->
            val action = actions.first { it.id == item.itemId }
            dispatchPlaybackAction(action.enabled, action.unavailableMessage(), showUnavailable, action.dispatch)
            true
        }
        setOnDismissListener { anchor.requestFocus() }
        show()
    }

private fun playbackMenuSummary(actions: List<PlaybackMenuAction>): String =
    "更多；" +
        actions.joinToString("；") { action ->
            if (action.enabled()) action.label else "${action.label}不可用：${action.unavailableMessage()}"
        }
