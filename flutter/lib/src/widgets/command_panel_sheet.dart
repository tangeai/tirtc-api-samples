import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../demo_widget_keys.dart';
import 'command_panel.dart';
import 'command_panel_model.dart';

typedef DemoCommandPanelConnectedGetter = bool Function();
typedef DemoCommandPanelEventsGetter = List<DemoCommandPanelEvent> Function();
typedef DemoCommandPanelSheetStateChanged = void Function(StateSetter? setState);

Future<void> showDemoCommandPanelSheet({
  required BuildContext context,
  required String title,
  required DemoCommandPanelConnectedGetter connected,
  required DemoCommandPanelEventsGetter events,
  required DemoCommandSender onSendCommand,
  required DemoCommandPanelSheetStateChanged onSheetStateChanged,
}) {
  Widget buildPanel(BuildContext panelContext, {required bool wide}) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setSheetState) {
        onSheetStateChanged(setSheetState);
        final MediaQueryData media = MediaQuery.of(context);
        final double maximumHeight = wide ? 560 : media.size.height * 0.75;
        final double availableHeight = media.size.height - media.viewInsets.bottom - 24;
        final double panelHeight = availableHeight.clamp(120, maximumHeight);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: Container(
            key: DemoWidgetKeys.commandPanelSheet,
            width: wide ? 720 : null,
            height: panelHeight,
            decoration: BoxDecoration(
              color: ExampleTheme.background,
              borderRadius:
                  wide
                      ? BorderRadius.circular(ExampleTheme.radiusLarge)
                      : const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: ExampleTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        key: DemoWidgetKeys.commandPanelCloseButton,
                        tooltip: '关闭命令面板',
                        onPressed: () => Navigator.of(panelContext).pop(),
                        icon: const Icon(Icons.close_rounded, color: ExampleTheme.textHint),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: ExampleTheme.inputBorder),
                Expanded(
                  child: DemoCommandPanel(
                    connected: connected(),
                    events: events(),
                    onSendCommand: (int commandId, Uint8List payload) async {
                      final int code = await onSendCommand(commandId, payload);
                      if (panelContext.mounted) {
                        setSheetState(() {});
                      }
                      return code;
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  final bool wide = MediaQuery.sizeOf(context).width >= ExampleTheme.compactBreakpoint;
  final Future<void> route =
      wide
          ? showDialog<void>(
            context: context,
            builder: (BuildContext dialogContext) => Dialog(child: buildPanel(dialogContext, wide: true)),
          )
          : showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (BuildContext sheetContext) => buildPanel(sheetContext, wide: false),
          );
  return route.whenComplete(() {
    onSheetStateChanged(null);
  });
}
