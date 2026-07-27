import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tirtc_flutter/tirtc_flutter.dart';

import '../app_theme.dart';
import '../demo_widget_keys.dart';
import 'command_panel_model.dart';

typedef DemoCommandSender = FutureOr<int> Function(int commandId, Uint8List payload);

class DemoCommandPanel extends StatefulWidget {
  const DemoCommandPanel({
    super.key,
    required this.connected,
    required this.events,
    required this.onSendCommand,
  });

  final bool connected;
  final List<DemoCommandPanelEvent> events;
  final DemoCommandSender onSendCommand;

  @override
  State<DemoCommandPanel> createState() => _DemoCommandPanelState();
}

class _DemoCommandPanelState extends State<DemoCommandPanel> {
  final TextEditingController _commandIdController = TextEditingController(text: '0x00000000');
  final TextEditingController _payloadController = TextEditingController();
  DemoCommandPayloadMode _payloadMode = DemoCommandPayloadMode.hex;
  String? _inputError;
  bool _sending = false;

  @override
  void dispose() {
    _commandIdController.dispose();
    _payloadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<DemoCommandPanelEvent> events = trimDemoCommandEvents(widget.events).reversed.toList();

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: _ConnectionPill(connected: widget.connected),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: DemoWidgetKeys.commandPanelCommandIdField,
                  controller: _commandIdController,
                  enabled: !_sending,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: '命令 ID',
                    hintText: '0x00000000',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<DemoCommandPayloadMode>(
                segments: const <ButtonSegment<DemoCommandPayloadMode>>[
                  ButtonSegment<DemoCommandPayloadMode>(
                    value: DemoCommandPayloadMode.hex,
                    label: Text('HEX'),
                  ),
                  ButtonSegment<DemoCommandPayloadMode>(
                    value: DemoCommandPayloadMode.text,
                    label: Text('文本'),
                  ),
                ],
                selected: <DemoCommandPayloadMode>{_payloadMode},
                showSelectedIcon: false,
                onSelectionChanged: _sending
                    ? null
                    : (Set<DemoCommandPayloadMode> selected) {
                        setState(() {
                          _payloadMode = selected.single;
                          _inputError = null;
                        });
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: DemoWidgetKeys.commandPanelPayloadField,
            controller: _payloadController,
            enabled: !_sending,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              labelText: '命令内容',
              hintText: _payloadMode == DemoCommandPayloadMode.hex ? '00 FF, 10 20' : '输入文本内容',
              errorText: _inputError,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          _CommonCommandPresetBar(
            enabled: !_sending,
            onSelected: _applyPreset,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: DemoWidgetKeys.commandPanelSendButton,
              onPressed: widget.connected && !_sending ? _send : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                minimumSize: const Size(96, 40),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(_sending ? '发送中' : '发送'),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: events.isEmpty
                ? const _EmptyCommandEvents()
                : ListView.separated(
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (BuildContext context, int index) {
                      return _CommandEventRow(event: events[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final DemoCommandParseResult<int> commandIdResult = parseDemoCommandId(_commandIdController.text);
    if (!commandIdResult.valid) {
      setState(() {
        _inputError = commandIdResult.error;
      });
      return;
    }

    final DemoCommandParseResult<Uint8List> payloadResult = parseDemoCommandPayload(
      input: _payloadController.text,
      mode: _payloadMode,
    );
    if (!payloadResult.valid) {
      setState(() {
        _inputError = payloadResult.error;
      });
      return;
    }

    setState(() {
      _inputError = null;
      _sending = true;
    });

    try {
      await widget.onSendCommand(commandIdResult.value!, payloadResult.value!);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _applyPreset(DemoCommandPreset preset) {
    setState(() {
      _commandIdController.text = preset.commandIdLabel;
      _payloadMode = preset.payloadMode;
      _payloadController.text = preset.payloadText;
      _inputError = null;
    });
  }
}

class _CommonCommandPresetBar extends StatelessWidget {
  const _CommonCommandPresetBar({
    required this.enabled,
    required this.onSelected,
  });

  final bool enabled;
  final ValueChanged<DemoCommandPreset> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '常用命令',
          style: TextStyle(
            color: ExampleTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: demoCommonCommandPresets.map((DemoCommandPreset preset) {
            return ActionChip(
              key: preset.commandId == demoCommandEchoPresetId ? DemoWidgetKeys.commandPanelEchoPreset : null,
              label: Text(preset.label),
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? () => onSelected(preset) : null,
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final Color color = connected ? ExampleTheme.primary : ExampleTheme.textSecondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(82)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          connected ? '已连接' : '未连接',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EmptyCommandEvents extends StatelessWidget {
  const _EmptyCommandEvents();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Text(
        '暂无命令记录',
        style: TextStyle(fontSize: 12, color: ExampleTheme.textSecondary),
      ),
    );
  }
}

class _CommandEventRow extends StatelessWidget {
  const _CommandEventRow({required this.event});

  final DemoCommandPanelEvent event;

  @override
  Widget build(BuildContext context) {
    final bool sent = event.direction == DemoCommandEventDirection.sent;
    final Color color = sent ? ExampleTheme.primary : ExampleTheme.textPrimary;
    return DecoratedBox(
      key: DemoWidgetKeys.commandPanelEvent(sent ? 'sent' : 'received', event.commandIdLabel),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(sent ? Icons.north_east_rounded : Icons.south_west_rounded, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${sent ? '已发送' : '已收到'} ${event.commandIdLabel}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
                if (event.resultCode != null)
                  Text(
                    event.resultCode == 0 ? '#0' : TiRtc.formatError(event.resultCode!),
                    style: const TextStyle(fontSize: 11, color: ExampleTheme.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              event.payloadHex.isEmpty ? '内容：空' : '内容：${event.payloadHex}',
              style: const TextStyle(fontSize: 11, color: ExampleTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
