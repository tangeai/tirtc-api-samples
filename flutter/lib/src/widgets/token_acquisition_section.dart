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
            ConfigureScanButton(
              buttonKey: DemoWidgetKeys.tokenScanButton,
              enabled: enabled && scanSupported,
              onPressed: onScanToken,
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
          style: ExampleTheme.inputTextStyle,
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
      style: ExampleTheme.inputTextStyle,
      decoration: const InputDecoration(
        labelText: '一次性连接 Token',
        hintText: '粘贴 v1.xxx 一次性 Token，或点右侧扫码。',
      ),
      validator: validator,
    );
  }
}

class ConfigureScanButton extends StatelessWidget {
  const ConfigureScanButton({
    super.key,
    required this.buttonKey,
    required this.enabled,
    required this.onPressed,
  });

  final Key buttonKey;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ExampleTheme.inputControlHeight,
      child: TextButton(
        key: buttonKey,
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          foregroundColor: enabled ? ExampleTheme.primary : ExampleTheme.textHint,
          backgroundColor: ExampleTheme.inputSurface,
          disabledForegroundColor: ExampleTheme.textHint,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(56, ExampleTheme.inputControlHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ExampleTheme.inputRadius),
          ),
        ),
        child: const Text(
          '扫码',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
