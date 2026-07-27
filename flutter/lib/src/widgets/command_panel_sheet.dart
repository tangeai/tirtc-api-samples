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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          onSheetStateChanged(setSheetState);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: Container(
              key: DemoWidgetKeys.commandPanelSheet,
              height: MediaQuery.sizeOf(context).height / 2,
              decoration: const BoxDecoration(
                color: ExampleTheme.background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
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
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: ExampleTheme.textHint,
                          ),
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
                        if (sheetContext.mounted) {
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
    },
  ).whenComplete(() {
    onSheetStateChanged(null);
  });
}
