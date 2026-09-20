package com.tange.ai.tirtc.example

import android.view.View
import android.widget.GridLayout

internal fun layoutVideoMosaic(
    grid: GridLayout,
    orderedIds: List<Int>,
    lanes: Map<Int, View>,
    selectedId: Int?,
    maximizedId: Int?,
    wide: Boolean,
) {
    val cells = videoMosaicCells(orderedIds, selectedId, maximizedId, wide)

    when {
        maximizedId != null || orderedIds.size <= 1 -> {
            grid.columnCount = 1
            grid.rowCount = 1
        }
        orderedIds.size == 2 && !wide -> {
            grid.columnCount = 1
            grid.rowCount = 2
        }
        orderedIds.size == 2 -> {
            grid.columnCount = 2
            grid.rowCount = 1
        }
        else -> {
            grid.columnCount = 2
            grid.rowCount = 2
        }
    }

    cells.forEach { cell ->
        val lane = lanes[cell.id] ?: return@forEach
        lane.visibility = if (cell.visible) View.VISIBLE else View.GONE
        val params = weightedCell(cell.row, cell.rowSpan, cell.column, cell.columnSpan)
        val margin = grid.context.dp(3)
        params.setMargins(margin, margin, margin, margin)
        lane.layoutParams = params
        lane.alpha = if (cell.primary) 1f else 0.82f
    }
    grid.requestLayout()
}

private fun weightedCell(
    row: Int,
    rowSpan: Int,
    column: Int,
    columnSpan: Int,
): GridLayout.LayoutParams =
    GridLayout.LayoutParams(
        GridLayout.spec(row, rowSpan, 1f),
        GridLayout.spec(column, columnSpan, 1f),
    ).apply {
        width = 0
        height = 0
    }
