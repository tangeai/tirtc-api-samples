import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../demo_widget_keys.dart';

class ConfigureTokenAcquisitionSection extends StatelessWidget {
  const ConfigureTokenAcquisitionSection({
    super.key,
    required this.tokenController,
    required this.tokenServerAddressController,
    required this.enabled,
    required this.scanSupported,
    required this.validateOneTimeToken,
    required this.validateTokenServerAddress,
    required this.onScanToken,
  });

  final TextEditingController tokenController;
  final TextEditingController tokenServerAddressController;
  final bool enabled;
  final bool scanSupported;
  final FormFieldValidator<String> validateOneTimeToken;
  final FormFieldValidator<String> validateTokenServerAddress;
  final VoidCallback onScanToken;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _TokenField(
                controller: tokenController,
                enabled: enabled,
                validator: validateOneTimeToken,
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              key: DemoWidgetKeys.tokenScanButton,
              onPressed: enabled && scanSupported ? onScanToken : null,
              style: TextButton.styleFrom(
                foregroundColor: enabled && scanSupported ? ExampleTheme.primary : ExampleTheme.textHint,
                backgroundColor: ExampleTheme.inputSurface,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: ExampleTheme.inputBorder),
                ),
              ),
              child: const Text(
                '扫码',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '或',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ExampleTheme.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextFormField(
          key: DemoWidgetKeys.tokenServerAddressField,
          controller: tokenServerAddressController,
          enabled: enabled,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'TiRTC DevTools 服务地址',
            hintText: '例如 http://192.168.1.10:8966',
          ),
          validator: validateTokenServerAddress,
        ),
      ],
    );
  }
}

class _TokenField extends StatelessWidget {
  const _TokenField({
    required this.controller,
    required this.enabled,
    required this.validator,
  });

  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: DemoWidgetKeys.tokenField,
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: '一次性连接 Token',
        hintText: '粘贴 v1.xxx 一次性 Token，或点右侧扫码。',
      ),
      validator: validator,
    );
  }
}
