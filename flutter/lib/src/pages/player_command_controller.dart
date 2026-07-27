import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../demo_downlink_session.dart';
import '../demo_echo_command.dart';
import '../widgets/command_panel_model.dart';
import '../widgets/command_panel_sheet.dart';

class DemoPlayerCommandController {
  DemoPlayerCommandController({
    required DemoDownlinkSession session,
    required VoidCallback onChanged,
  })  : _session = session,
        _onChanged = onChanged;

  final DemoDownlinkSession _session;
  final DemoEchoCommandResponder _echoResponder = DemoEchoCommandResponder();
  final VoidCallback _onChanged;

  List<DemoCommandPanelEvent> _events = <DemoCommandPanelEvent>[];
  StateSetter? _sheetSetState;

  void reset({bool notify = true}) {
    _events = <DemoCommandPanelEvent>[];
    _sheetSetState = null;
    if (notify) {
      _onChanged();
    }
  }

  void handleReceived({
    required int commandId,
    required Uint8List payload,
  }) {
    _append(
      DemoCommandPanelEvent(
        direction: DemoCommandEventDirection.received,
        commandId: commandId,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
    final int? echoCode = _echoResponder.handleReceived(
      commandId: commandId,
      payload: payload,
      sendCommand: (int commandId, Uint8List payload) => _session.sendCommand(
        commandId: commandId,
        payload: payload,
      ),
    );
    if (echoCode != null) {
      _append(
        DemoCommandPanelEvent(
          direction: DemoCommandEventDirection.sent,
          commandId: commandId,
          payload: payload,
          resultCode: echoCode,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  Future<int> send(int commandId, Uint8List payload) async {
    final int code = _session.sendCommand(commandId: commandId, payload: payload);
    _echoResponder.trackLocalSend(
      commandId: commandId,
      payload: payload,
      resultCode: code,
    );
    _append(
      DemoCommandPanelEvent(
        direction: DemoCommandEventDirection.sent,
        commandId: commandId,
        payload: payload,
        resultCode: code,
        createdAt: DateTime.now(),
      ),
    );
    return code;
  }

  Future<void> showPanel(
    BuildContext context, {
    required bool Function() connected,
  }) {
    return showDemoCommandPanelSheet(
      context: context,
      title: '发送命令',
      connected: connected,
      events: () => _events,
      onSendCommand: send,
      onSheetStateChanged: (StateSetter? setState) {
        _sheetSetState = setState;
      },
    );
  }

  void refreshSheet() {
    _sheetSetState?.call(() {});
  }

  void _append(DemoCommandPanelEvent event) {
    _events = trimDemoCommandEvents(<DemoCommandPanelEvent>[..._events, event]);
    _onChanged();
    refreshSheet();
  }
}
